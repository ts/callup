import CallupCore
import Foundation
import SQLiteNIO

public actor ApplicationStore {
    public enum DownloadReservation: Sendable {
        case reserved(DownloadSubmission)
        case existing(DownloadSubmission)
    }

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
        case seriesNotTracked
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

    public func trackedTelevisionSeries() async throws -> [TrackedTelevisionSeries] {
        let rows = try await connection.query(
            """
            SELECT payload, added_at, season_folders, preferred_resolution, preferred_video_codec
            FROM tracked_television_series
            ORDER BY title COLLATE NOCASE, provider, external_id
            """
        )
        return try rows.map { row in
            guard
                let payload = row.column("payload").flatMap(Data.init(sqliteData:)),
                let addedAt = row.column("added_at").flatMap(Date.init(sqliteData:))
            else {
                throw StoreError.malformedCacheEntry
            }
            return TrackedTelevisionSeries(
                series: try decoder.decode(TelevisionSeries.self, from: payload),
                addedAt: addedAt,
                downloadSettings: TelevisionDownloadSettings(
                    seasonFolders: row.column("season_folders").flatMap(Int.init(sqliteData:)) != 0,
                    preferredResolution: row.column("preferred_resolution")
                        .flatMap(String.init(sqliteData:))
                        .flatMap(TelevisionResolutionPreference.init(rawValue:)) ?? .p1080,
                    preferredVideoCodec: row.column("preferred_video_codec")
                        .flatMap(String.init(sqliteData:))
                        .flatMap(TelevisionVideoCodecPreference.init(rawValue:)) ?? .hevc
                )
            )
        }
    }

    @discardableResult
    public func trackTelevisionSeries(
        _ series: TelevisionSeries,
        addedAt: Date = Date()
    ) async throws -> TrackedTelevisionSeries {
        try validate(namespace: series.id.provider, key: series.id.value)
        let payload = try encoder.encode(series)
        _ = try await connection.query(
            """
            INSERT INTO tracked_television_series (
                provider, external_id, title, payload, added_at
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(provider, external_id) DO UPDATE SET
                title = excluded.title,
                payload = excluded.payload
            """,
            [
                .text(series.id.provider),
                .text(series.id.value),
                .text(series.title),
                payload.sqliteData!,
                addedAt.sqliteData!,
            ]
        )
        let rows = try await connection.query(
            """
            SELECT added_at, season_folders, preferred_resolution, preferred_video_codec
            FROM tracked_television_series
            WHERE provider = ? AND external_id = ?
            """,
            [.text(series.id.provider), .text(series.id.value)]
        )
        guard let storedAddedAt = rows.first?.column("added_at").flatMap(Date.init(sqliteData:)) else {
            throw StoreError.malformedCacheEntry
        }
        let row = rows.first!
        return TrackedTelevisionSeries(
            series: series,
            addedAt: storedAddedAt,
            downloadSettings: TelevisionDownloadSettings(
                seasonFolders: row.column("season_folders").flatMap(Int.init(sqliteData:)) != 0,
                preferredResolution: row.column("preferred_resolution")
                    .flatMap(String.init(sqliteData:))
                    .flatMap(TelevisionResolutionPreference.init(rawValue:)) ?? .p1080,
                preferredVideoCodec: row.column("preferred_video_codec")
                    .flatMap(String.init(sqliteData:))
                    .flatMap(TelevisionVideoCodecPreference.init(rawValue:)) ?? .hevc
            )
        )
    }

    public func trackedTelevisionSeries(id: ProviderReference) async throws -> TrackedTelevisionSeries? {
        try validate(namespace: id.provider, key: id.value)
        let rows = try await connection.query(
            """
            SELECT payload, added_at, season_folders, preferred_resolution, preferred_video_codec
            FROM tracked_television_series
            WHERE provider = ? AND external_id = ?
            """,
            [.text(id.provider), .text(id.value)]
        )
        guard let row = rows.first else { return nil }
        guard
            let payload = row.column("payload").flatMap(Data.init(sqliteData:)),
            let addedAt = row.column("added_at").flatMap(Date.init(sqliteData:))
        else {
            throw StoreError.malformedCacheEntry
        }
        return TrackedTelevisionSeries(
            series: try decoder.decode(TelevisionSeries.self, from: payload),
            addedAt: addedAt,
            downloadSettings: TelevisionDownloadSettings(
                seasonFolders: row.column("season_folders").flatMap(Int.init(sqliteData:)) != 0,
                preferredResolution: row.column("preferred_resolution")
                    .flatMap(String.init(sqliteData:))
                    .flatMap(TelevisionResolutionPreference.init(rawValue:)) ?? .p1080,
                preferredVideoCodec: row.column("preferred_video_codec")
                    .flatMap(String.init(sqliteData:))
                    .flatMap(TelevisionVideoCodecPreference.init(rawValue:)) ?? .hevc
            )
        )
    }

    @discardableResult
    public func setTelevisionDownloadSettings(
        seriesID: ProviderReference,
        settings: TelevisionDownloadSettings
    ) async throws -> TelevisionDownloadSettings {
        try await ensureTracked(seriesID)
        _ = try await connection.query(
            """
            UPDATE tracked_television_series
            SET season_folders = ?, preferred_resolution = ?, preferred_video_codec = ?
            WHERE provider = ? AND external_id = ?
            """,
            [
                (settings.seasonFolders ? 1 : 0).sqliteData!,
                .text(settings.preferredResolution.rawValue),
                .text(settings.preferredVideoCodec.rawValue),
                .text(seriesID.provider),
                .text(seriesID.value),
            ]
        )
        return settings
    }

    public func untrackTelevisionSeries(id: ProviderReference) async throws {
        try validate(namespace: id.provider, key: id.value)
        _ = try await connection.query(
            "DELETE FROM tracked_television_series WHERE provider = ? AND external_id = ?",
            [.text(id.provider), .text(id.value)]
        )
    }

    public func televisionLineup(seriesID: ProviderReference) async throws -> TelevisionLineup {
        try validate(namespace: seriesID.provider, key: seriesID.value)
        let rows = try await connection.query(
            """
            SELECT payload
            FROM television_lineups
            WHERE series_provider = ? AND series_external_id = ?
            """,
            [.text(seriesID.provider), .text(seriesID.value)]
        )
        guard let row = rows.first else { return TelevisionLineup() }
        guard let payload = row.column("payload").flatMap(Data.init(sqliteData:)) else {
            throw StoreError.malformedCacheEntry
        }
        return try decoder.decode(TelevisionLineup.self, from: payload)
    }

    public func setTelevisionSeasonIncluded(
        seriesID: ProviderReference,
        seasonNumber: Int,
        episodeIDs: [ProviderReference],
        included: Bool
    ) async throws {
        for episodeID in episodeIDs {
            try validate(namespace: episodeID.provider, key: episodeID.value)
        }
        try await ensureTracked(seriesID)
        try await transaction {
            var lineup = try await televisionLineup(seriesID: seriesID)
            if included {
                lineup.excludedSeasons.remove(seasonNumber)
                lineup.includedEpisodes.formUnion(episodeIDs)
                lineup.excludedEpisodes.subtract(episodeIDs)
            } else {
                lineup.excludedSeasons.insert(seasonNumber)
                lineup.includedEpisodes.subtract(episodeIDs)
                lineup.excludedEpisodes.subtract(episodeIDs)
            }
            try await putTelevisionLineup(lineup, seriesID: seriesID)
        }
    }

    public func setTelevisionEpisodeMonitoring(
        seriesID: ProviderReference,
        monitoring: TelevisionEpisodeMonitoring,
        futureCutoffDate: String? = nil
    ) async throws {
        try await ensureTracked(seriesID)
        if monitoring == .future,
           futureCutoffDate?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw StoreError.invalidCacheIdentity
        }
        try await transaction {
            var lineup = try await televisionLineup(seriesID: seriesID)
            lineup.monitoring = monitoring
            lineup.futureCutoffDate = monitoring == .future ? futureCutoffDate : nil
            lineup.excludedSeasons.removeAll()
            lineup.excludedEpisodes.removeAll()
            lineup.includedEpisodes.removeAll()
            try await putTelevisionLineup(lineup, seriesID: seriesID)
        }
    }

    public func setTelevisionEpisodeIncluded(
        seriesID: ProviderReference,
        seasonNumber: Int,
        episodeID: ProviderReference,
        seasonEpisodeIDs: [ProviderReference],
        included: Bool
    ) async throws {
        try validate(namespace: episodeID.provider, key: episodeID.value)
        for seasonEpisodeID in seasonEpisodeIDs {
            try validate(namespace: seasonEpisodeID.provider, key: seasonEpisodeID.value)
        }
        try await ensureTracked(seriesID)
        try await transaction {
            var lineup = try await televisionLineup(seriesID: seriesID)
            if included {
                if lineup.excludedSeasons.remove(seasonNumber) != nil {
                    lineup.excludedEpisodes.formUnion(seasonEpisodeIDs)
                }
                lineup.excludedEpisodes.remove(episodeID)
                lineup.includedEpisodes.insert(episodeID)
            } else {
                lineup.excludedEpisodes.insert(episodeID)
                lineup.includedEpisodes.remove(episodeID)
            }
            try await putTelevisionLineup(lineup, seriesID: seriesID)
        }
    }

    public func downloadSubmission(candidateID: ProviderReference) async throws -> DownloadSubmission? {
        try validate(namespace: candidateID.provider, key: candidateID.value)
        let rows = try await connection.query(
            """
            SELECT title, client, state, client_job_id, series_payload,
                   episode_ids_payload, created_at, updated_at
            FROM download_submissions
            WHERE candidate_provider = ? AND candidate_external_id = ?
            """,
            [.text(candidateID.provider), .text(candidateID.value)]
        )
        guard let row = rows.first else { return nil }
        guard
            let title = row.column("title").flatMap(String.init(sqliteData:)),
            let rawClient = row.column("client").flatMap(String.init(sqliteData:)),
            let client = DownloadClientKind(rawValue: rawClient),
            let rawState = row.column("state").flatMap(String.init(sqliteData:)),
            let state = DownloadSubmissionState(rawValue: rawState),
            let createdAt = row.column("created_at").flatMap(Date.init(sqliteData:)),
            let updatedAt = row.column("updated_at").flatMap(Date.init(sqliteData:))
        else {
            throw StoreError.malformedCacheEntry
        }
        return DownloadSubmission(
            candidateID: candidateID,
            seriesID: try row.column("series_payload")
                .flatMap(Data.init(sqliteData:))
                .map { try decoder.decode(ProviderReference.self, from: $0) },
            episodeIDs: try row.column("episode_ids_payload")
                .flatMap(Data.init(sqliteData:))
                .map { try decoder.decode([ProviderReference].self, from: $0) } ?? [],
            title: title,
            client: client,
            state: state,
            clientJobID: row.column("client_job_id").flatMap(String.init(sqliteData:)),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    public func reserveDownloadSubmission(
        candidateID: ProviderReference,
        title: String,
        client: DownloadClientKind,
        at date: Date = Date()
    ) async throws -> DownloadReservation {
        try validate(namespace: candidateID.provider, key: candidateID.value)
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoreError.invalidCacheIdentity
        }
        if let existing = try await downloadSubmission(candidateID: candidateID),
           existing.state != .blocked {
            return .existing(existing)
        }
        _ = try await connection.query(
            """
            INSERT INTO download_submissions (
                candidate_provider, candidate_external_id, title, client, state,
                client_job_id, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?)
            ON CONFLICT(candidate_provider, candidate_external_id) DO UPDATE SET
                title = excluded.title,
                client = excluded.client,
                state = excluded.state,
                client_job_id = NULL,
                updated_at = excluded.updated_at
            """,
            [
                .text(candidateID.provider), .text(candidateID.value), .text(title),
                .text(client.rawValue), .text(DownloadSubmissionState.sending.rawValue),
                date.sqliteData!, date.sqliteData!,
            ]
        )
        return .reserved(try await downloadSubmission(candidateID: candidateID)!)
    }

    public func finishDownloadSubmission(
        candidateID: ProviderReference,
        jobID: String,
        at date: Date = Date()
    ) async throws -> DownloadSubmission {
        try validate(namespace: candidateID.provider, key: candidateID.value)
        guard !jobID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoreError.invalidCacheIdentity
        }
        _ = try await connection.query(
            """
            UPDATE download_submissions
            SET state = ?, client_job_id = ?, updated_at = ?
            WHERE candidate_provider = ? AND candidate_external_id = ? AND state = ?
            """,
            [
                .text(DownloadSubmissionState.snatched.rawValue), .text(jobID), date.sqliteData!,
                .text(candidateID.provider), .text(candidateID.value),
                .text(DownloadSubmissionState.sending.rawValue),
            ]
        )
        guard let submission = try await downloadSubmission(candidateID: candidateID),
              submission.state == .snatched else { throw StoreError.malformedCacheEntry }
        return submission
    }

    public func failDownloadSubmission(
        candidateID: ProviderReference,
        at date: Date = Date()
    ) async throws {
        try validate(namespace: candidateID.provider, key: candidateID.value)
        _ = try await connection.query(
            """
            UPDATE download_submissions
            SET state = ?, updated_at = ?
            WHERE candidate_provider = ? AND candidate_external_id = ? AND state = ?
            """,
            [
                .text(DownloadSubmissionState.blocked.rawValue), date.sqliteData!,
                .text(candidateID.provider), .text(candidateID.value),
                .text(DownloadSubmissionState.sending.rawValue),
            ]
        )
    }

    public func updateDownloadSubmissionState(
        candidateID: ProviderReference,
        state: DownloadSubmissionState,
        at date: Date = Date()
    ) async throws -> DownloadSubmission {
        try validate(namespace: candidateID.provider, key: candidateID.value)
        _ = try await connection.query(
            """
            UPDATE download_submissions SET state = ?, updated_at = ?
            WHERE candidate_provider = ? AND candidate_external_id = ?
            """,
            [
                .text(state.rawValue), date.sqliteData!,
                .text(candidateID.provider), .text(candidateID.value),
            ]
        )
        guard let submission = try await downloadSubmission(candidateID: candidateID) else {
            throw StoreError.malformedCacheEntry
        }
        return submission
    }

    public func associateDownloadSubmission(
        candidateID: ProviderReference,
        seriesID: ProviderReference,
        episodeIDs: [ProviderReference],
        at date: Date = Date()
    ) async throws -> DownloadSubmission {
        try validate(namespace: candidateID.provider, key: candidateID.value)
        try validate(namespace: seriesID.provider, key: seriesID.value)
        for episodeID in episodeIDs {
            try validate(namespace: episodeID.provider, key: episodeID.value)
        }
        let seriesPayload = try encoder.encode(seriesID)
        let episodePayload = try encoder.encode(episodeIDs)
        _ = try await connection.query(
            """
            UPDATE download_submissions
            SET series_payload = ?, episode_ids_payload = ?, updated_at = ?
            WHERE candidate_provider = ? AND candidate_external_id = ?
            """,
            [
                seriesPayload.sqliteData!, episodePayload.sqliteData!, date.sqliteData!,
                .text(candidateID.provider), .text(candidateID.value),
            ]
        )
        guard let submission = try await downloadSubmission(candidateID: candidateID) else {
            throw StoreError.malformedCacheEntry
        }
        return submission
    }

    public func downloadSubmissions() async throws -> [DownloadSubmission] {
        let rows = try await connection.query(
            """
            SELECT candidate_provider, candidate_external_id
            FROM download_submissions ORDER BY updated_at DESC
            """
        )
        var submissions: [DownloadSubmission] = []
        for row in rows {
            guard
                let provider = row.column("candidate_provider").flatMap(String.init(sqliteData:)),
                let identifier = row.column("candidate_external_id").flatMap(String.init(sqliteData:)),
                let submission = try await downloadSubmission(
                    candidateID: ProviderReference(provider: provider, value: identifier)
                )
            else {
                throw StoreError.malformedCacheEntry
            }
            submissions.append(submission)
        }
        return submissions
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

        let versionOneRows = try await connection.query(
            "SELECT version FROM schema_migrations WHERE version = 1"
        )
        if versionOneRows.isEmpty {
            try await migrate(version: 1) {
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
            }
        }

        let versionTwoRows = try await connection.query(
            "SELECT version FROM schema_migrations WHERE version = 2"
        )
        if versionTwoRows.isEmpty {
            try await migrate(version: 2) {
                _ = try await connection.query(
                    """
                    CREATE TABLE tracked_television_series (
                        provider TEXT NOT NULL,
                        external_id TEXT NOT NULL,
                        title TEXT NOT NULL,
                        payload BLOB NOT NULL,
                        added_at REAL NOT NULL,
                        PRIMARY KEY (provider, external_id)
                    ) WITHOUT ROWID
                    """
                )
            }
        }
        let versionThreeRows = try await connection.query(
            "SELECT version FROM schema_migrations WHERE version = 3"
        )
        if versionThreeRows.isEmpty {
            try await migrate(version: 3) {
                _ = try await connection.query(
                    """
                    CREATE TABLE television_lineups (
                        series_provider TEXT NOT NULL,
                        series_external_id TEXT NOT NULL,
                        payload BLOB NOT NULL,
                        updated_at REAL NOT NULL,
                        PRIMARY KEY (series_provider, series_external_id),
                        FOREIGN KEY (series_provider, series_external_id)
                            REFERENCES tracked_television_series(provider, external_id)
                            ON DELETE CASCADE
                    ) WITHOUT ROWID
                    """
                )
            }
        }
        let versionFourRows = try await connection.query(
            "SELECT version FROM schema_migrations WHERE version = 4"
        )
        if versionFourRows.isEmpty {
            try await migrate(version: 4) {
                _ = try await connection.query(
                    """
                    CREATE TABLE download_submissions (
                        candidate_provider TEXT NOT NULL,
                        candidate_external_id TEXT NOT NULL,
                        title TEXT NOT NULL,
                        client TEXT NOT NULL,
                        state TEXT NOT NULL,
                        client_job_id TEXT,
                        created_at REAL NOT NULL,
                        updated_at REAL NOT NULL,
                        PRIMARY KEY (candidate_provider, candidate_external_id)
                    ) WITHOUT ROWID
                    """
                )
            }
        }
        let versionFiveRows = try await connection.query(
            "SELECT version FROM schema_migrations WHERE version = 5"
        )
        if versionFiveRows.isEmpty {
            try await migrate(version: 5) {
                _ = try await connection.query(
                    "ALTER TABLE download_submissions ADD COLUMN series_payload BLOB"
                )
                _ = try await connection.query(
                    "ALTER TABLE download_submissions ADD COLUMN episode_ids_payload BLOB"
                )
            }
        }
        let versionSixRows = try await connection.query(
            "SELECT version FROM schema_migrations WHERE version = 6"
        )
        if versionSixRows.isEmpty {
            try await migrate(version: 6) {
                _ = try await connection.query(
                    "ALTER TABLE tracked_television_series ADD COLUMN season_folders INTEGER NOT NULL DEFAULT 1"
                )
            }
        }
        let versionSevenRows = try await connection.query(
            "SELECT version FROM schema_migrations WHERE version = 7"
        )
        if versionSevenRows.isEmpty {
            try await migrate(version: 7) {
                _ = try await connection.query(
                    "ALTER TABLE tracked_television_series ADD COLUMN preferred_resolution TEXT NOT NULL DEFAULT '1080p'"
                )
                _ = try await connection.query(
                    "ALTER TABLE tracked_television_series ADD COLUMN preferred_video_codec TEXT NOT NULL DEFAULT 'HEVC'"
                )
            }
        }
    }

    private func putTelevisionLineup(
        _ lineup: TelevisionLineup,
        seriesID: ProviderReference
    ) async throws {
        let payload = try encoder.encode(lineup)
        _ = try await connection.query(
            """
            INSERT INTO television_lineups (
                series_provider, series_external_id, payload, updated_at
            ) VALUES (?, ?, ?, ?)
            ON CONFLICT DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at
            """,
            [
                .text(seriesID.provider), .text(seriesID.value),
                payload.sqliteData!, Date().sqliteData!,
            ]
        )
    }

    private func ensureTracked(_ seriesID: ProviderReference) async throws {
        try validate(namespace: seriesID.provider, key: seriesID.value)
        let rows = try await connection.query(
            """
            SELECT 1 FROM tracked_television_series
            WHERE provider = ? AND external_id = ?
            """,
            [.text(seriesID.provider), .text(seriesID.value)]
        )
        guard !rows.isEmpty else { throw StoreError.seriesNotTracked }
    }

    private func migrate(version: Int, changes: () async throws -> Void) async throws {
        try await transaction {
            try await changes()
            _ = try await connection.query(
                "INSERT INTO schema_migrations (version, applied_at) VALUES (?, ?)",
                [version.sqliteData!, Date().sqliteData!]
            )
        }
    }

    private func transaction(changes: () async throws -> Void) async throws {
        _ = try await connection.query("BEGIN IMMEDIATE")
        do {
            try await changes()
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
