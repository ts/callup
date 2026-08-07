import Foundation
import SQLiteNIO

public actor ApplicationStore {
    private struct CacheIdentity: Hashable {
        let namespace: String
        let key: String
    }

    public struct CacheEntry<Value: Codable & Sendable>: Sendable {
        public let value: Value
        public let fetchedAt: Date
        public let expiresAt: Date
        public let schemaVersion: Int

        public var isFresh: Bool {
            isFresh(at: Date())
        }

        public func isFresh(at date: Date) -> Bool {
            expiresAt > date
        }
    }

    public enum StoreError: Error, Equatable {
        case invalidCacheIdentity
        case malformedCacheEntry
    }

    private let connection: SQLiteConnection
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var refreshing: Set<CacheIdentity> = []

    private init(connection: SQLiteConnection) {
        self.connection = connection
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public static func open(fileURL: URL) async throws -> ApplicationStore {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        let connection = try await SQLiteConnection.open(storage: .file(path: fileURL.path))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
        let store = ApplicationStore(connection: connection)
        try await store.prepare()
        return store
    }

    public static func inMemory() async throws -> ApplicationStore {
        let connection = try await SQLiteConnection.open(storage: .memory)
        let store = ApplicationStore(connection: connection)
        try await store.prepare()
        return store
    }

    public func cacheEntry<Value: Codable & Sendable>(
        namespace: String,
        key: String,
        as type: Value.Type = Value.self
    ) async throws -> CacheEntry<Value>? {
        try validate(namespace: namespace, key: key)
        let rows = try await connection.query(
            """
            SELECT payload, fetched_at, expires_at, schema_version
            FROM cache_entries
            WHERE namespace = ? AND cache_key = ?
            """,
            [.text(namespace), .text(key)]
        )
        guard let row = rows.first else { return nil }
        guard
            let payload = row.column("payload").flatMap(Data.init(sqliteData:)),
            let fetchedAt = row.column("fetched_at").flatMap(Date.init(sqliteData:)),
            let expiresAt = row.column("expires_at").flatMap(Date.init(sqliteData:)),
            let schemaVersion = row.column("schema_version").flatMap(Int.init(sqliteData:))
        else {
            throw StoreError.malformedCacheEntry
        }

        return CacheEntry(
            value: try decoder.decode(Value.self, from: payload),
            fetchedAt: fetchedAt,
            expiresAt: expiresAt,
            schemaVersion: schemaVersion
        )
    }

    public func putCacheEntry<Value: Codable & Sendable>(
        namespace: String,
        key: String,
        value: Value,
        fetchedAt: Date = Date(),
        expiresAt: Date,
        schemaVersion: Int = 1
    ) async throws {
        try validate(namespace: namespace, key: key)
        let payload = try encoder.encode(value)
        _ = try await connection.query(
            """
            INSERT INTO cache_entries (
                namespace, cache_key, payload, fetched_at, expires_at, schema_version
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(namespace, cache_key) DO UPDATE SET
                payload = excluded.payload,
                fetched_at = excluded.fetched_at,
                expires_at = excluded.expires_at,
                schema_version = excluded.schema_version
            """,
            [
                .text(namespace),
                .text(key),
                payload.sqliteData!,
                fetchedAt.sqliteData!,
                expiresAt.sqliteData!,
                schemaVersion.sqliteData!,
            ]
        )
    }

    public func cachedValue<Value: Codable & Sendable>(
        namespace: String,
        key: String,
        timeToLive: TimeInterval,
        schemaVersion: Int = 1,
        load: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let cached: CacheEntry<Value>?
        do {
            cached = try await cacheEntry(namespace: namespace, key: key)
        } catch is DecodingError {
            try await removeCacheEntry(namespace: namespace, key: key)
            cached = nil
        }

        if let cached, cached.schemaVersion == schemaVersion {
            if !cached.isFresh {
                scheduleRefresh(
                    namespace: namespace,
                    key: key,
                    timeToLive: timeToLive,
                    schemaVersion: schemaVersion,
                    load: load
                )
            }
            return cached.value
        }

        let value = try await load()
        let fetchedAt = Date()
        try await putCacheEntry(
            namespace: namespace,
            key: key,
            value: value,
            fetchedAt: fetchedAt,
            expiresAt: fetchedAt.addingTimeInterval(timeToLive),
            schemaVersion: schemaVersion
        )
        return value
    }

    public func removeCacheEntry(namespace: String, key: String) async throws {
        try validate(namespace: namespace, key: key)
        _ = try await connection.query(
            "DELETE FROM cache_entries WHERE namespace = ? AND cache_key = ?",
            [.text(namespace), .text(key)]
        )
    }

    public func close() async throws {
        try await connection.close()
    }

    private func prepare() async throws {
        _ = try await connection.query("PRAGMA foreign_keys = ON")
        _ = try await connection.query("PRAGMA journal_mode = WAL")
        _ = try await connection.query("PRAGMA synchronous = NORMAL")
        _ = try await connection.query(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                applied_at REAL NOT NULL
            )
            """
        )

        let rows = try await connection.query(
            "SELECT version FROM schema_migrations WHERE version = 1"
        )
        guard rows.isEmpty else { return }

        _ = try await connection.query("BEGIN IMMEDIATE")
        do {
            _ = try await connection.query(
                """
                CREATE TABLE cache_entries (
                    namespace TEXT NOT NULL,
                    cache_key TEXT NOT NULL,
                    payload BLOB NOT NULL,
                    fetched_at REAL NOT NULL,
                    expires_at REAL NOT NULL,
                    schema_version INTEGER NOT NULL,
                    PRIMARY KEY (namespace, cache_key)
                ) WITHOUT ROWID
                """
            )
            _ = try await connection.query(
                "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                [1.sqliteData!, Date().sqliteData!]
            )
            _ = try await connection.query("COMMIT")
        } catch {
            _ = try? await connection.query("ROLLBACK")
            throw error
        }
    }

    private func validate(namespace: String, key: String) throws {
        guard
            !namespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw StoreError.invalidCacheIdentity
        }
    }

    private func scheduleRefresh<Value: Codable & Sendable>(
        namespace: String,
        key: String,
        timeToLive: TimeInterval,
        schemaVersion: Int,
        load: @escaping @Sendable () async throws -> Value
    ) {
        let identity = CacheIdentity(namespace: namespace, key: key)
        guard refreshing.insert(identity).inserted else { return }

        Task {
            if let value = try? await load() {
                let fetchedAt = Date()
                try? await putCacheEntry(
                    namespace: namespace,
                    key: key,
                    value: value,
                    fetchedAt: fetchedAt,
                    expiresAt: fetchedAt.addingTimeInterval(timeToLive),
                    schemaVersion: schemaVersion
                )
            }
            refreshing.remove(identity)
        }
    }
}
