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

    private struct StoredTrackedMedia<Metadata: Codable & Sendable, Settings: Codable & Sendable> {
        let metadata: Metadata
        let settings: Settings
        let addedAt: Date
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
        case mediaNotTracked
        case unsupportedBackupVersion(Int)
        case invalidBackup
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
        let stored: [StoredTrackedMedia<TelevisionSeries, TelevisionDownloadSettings>] =
            try await trackedMedia(kind: .televisionSeries)
        return stored.map {
            TrackedTelevisionSeries(
                series: $0.metadata,
                addedAt: $0.addedAt,
                downloadSettings: $0.settings
            )
        }
    }

    @discardableResult
    public func trackTelevisionSeries(
        _ series: TelevisionSeries,
        addedAt: Date = Date()
    ) async throws -> TrackedTelevisionSeries {
        let stored: StoredTrackedMedia<TelevisionSeries, TelevisionDownloadSettings> =
            try await trackMedia(
                kind: .televisionSeries,
                id: series.id,
                title: series.title,
                metadata: series,
                defaultSettings: TelevisionDownloadSettings(),
                addedAt: addedAt
            )
        return TrackedTelevisionSeries(
            series: stored.metadata,
            addedAt: stored.addedAt,
            downloadSettings: stored.settings
        )
    }

    public func trackedTelevisionSeries(id: ProviderReference) async throws -> TrackedTelevisionSeries? {
        let stored: StoredTrackedMedia<TelevisionSeries, TelevisionDownloadSettings>? =
            try await trackedMedia(kind: .televisionSeries, id: id)
        guard let stored else { return nil }
        return TrackedTelevisionSeries(
            series: stored.metadata,
            addedAt: stored.addedAt,
            downloadSettings: stored.settings
        )
    }

    @discardableResult
    public func setTelevisionDownloadSettings(
        seriesID: ProviderReference,
        settings: TelevisionDownloadSettings
    ) async throws -> TelevisionDownloadSettings {
        do {
            try await setTrackedMediaSettings(
                media: MediaReference(kind: .televisionSeries, id: seriesID),
                settings: settings
            )
        } catch StoreError.mediaNotTracked {
            throw StoreError.seriesNotTracked
        }
        return settings
    }

    public func untrackTelevisionSeries(id: ProviderReference) async throws {
        try await untrackMedia(MediaReference(kind: .televisionSeries, id: id))
    }

    public func trackedMovies() async throws -> [TrackedMovie] {
        let stored: [StoredTrackedMedia<Movie, MovieDownloadSettings>] =
            try await trackedMedia(kind: .movie)
        return stored.map {
            return TrackedMovie(
                movie: $0.metadata,
                addedAt: $0.addedAt,
                downloadSettings: $0.settings
            )
        }
    }

    public func trackedMovie(id: ProviderReference) async throws -> TrackedMovie? {
        let stored: StoredTrackedMedia<Movie, MovieDownloadSettings>? =
            try await trackedMedia(kind: .movie, id: id)
        guard let stored else { return nil }
        return TrackedMovie(
            movie: stored.metadata,
            addedAt: stored.addedAt,
            downloadSettings: stored.settings
        )
    }

    @discardableResult
    public func trackMovie(
        _ movie: Movie,
        addedAt: Date = Date()
    ) async throws -> TrackedMovie {
        let stored: StoredTrackedMedia<Movie, MovieDownloadSettings> = try await trackMedia(
            kind: .movie,
            id: movie.id,
            title: movie.title,
            metadata: movie,
            defaultSettings: MovieDownloadSettings(),
            addedAt: addedAt
        )
        return TrackedMovie(
            movie: stored.metadata,
            addedAt: stored.addedAt,
            downloadSettings: stored.settings
        )
    }

    @discardableResult
    public func updateTrackedMovieMetadata(_ movie: Movie) async throws -> TrackedMovie? {
        try validate(namespace: movie.id.provider, key: movie.id.value)
        let payload = try encoder.encode(movie)
        _ = try await connection.query(
            """
            UPDATE tracked_media
            SET title = ?, metadata_payload = ?
            WHERE media_kind = ? AND provider = ? AND external_id = ?
            """,
            [
                .text(movie.title), payload.sqliteData!, .text(MediaKind.movie.rawValue),
                .text(movie.id.provider), .text(movie.id.value),
            ]
        )
        return try await trackedMovie(id: movie.id)
    }

    @discardableResult
    public func setMovieDownloadSettings(
        movieID: ProviderReference,
        settings: MovieDownloadSettings
    ) async throws -> MovieDownloadSettings {
        try await setTrackedMediaSettings(
            media: MediaReference(kind: .movie, id: movieID),
            settings: settings
        )
        return settings
    }

    public func untrackMovie(id: ProviderReference) async throws {
        try await untrackMedia(MediaReference(kind: .movie, id: id))
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
            SELECT title, client, state, client_job_id, acquisition_payload,
                   created_at, updated_at
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
        let acquisitionContext = try row.column("acquisition_payload")
            .flatMap(Data.init(sqliteData:))
            .map { try decoder.decode(AcquisitionContext.self, from: $0) }
        return DownloadSubmission(
            candidateID: candidateID,
            acquisitionContext: acquisitionContext,
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
        try await associateDownloadSubmission(
            candidateID: candidateID,
            acquisitionContext: .television(seriesID: seriesID, episodeIDs: episodeIDs),
            at: date
        )
    }

    public func associateDownloadSubmission(
        candidateID: ProviderReference,
        seriesID: ProviderReference,
        episodes: [TelevisionEpisode],
        at date: Date = Date()
    ) async throws -> DownloadSubmission {
        try await associateDownloadSubmission(
            candidateID: candidateID,
            acquisitionContext: .television(seriesID: seriesID, episodes: episodes),
            at: date
        )
    }

    public func associateDownloadSubmission(
        candidateID: ProviderReference,
        acquisitionContext: AcquisitionContext,
        at date: Date = Date()
    ) async throws -> DownloadSubmission {
        try validate(namespace: candidateID.provider, key: candidateID.value)
        for target in acquisitionContext.targets {
            try validate(namespace: target.media.id.provider, key: target.media.id.value)
            for ancestor in target.ancestors {
                try validate(namespace: ancestor.id.provider, key: ancestor.id.value)
            }
        }
        let acquisitionPayload = try encoder.encode(acquisitionContext)
        _ = try await connection.query(
            """
            UPDATE download_submissions
            SET acquisition_payload = ?, updated_at = ?
            WHERE candidate_provider = ? AND candidate_external_id = ?
            """,
            [
                acquisitionPayload.sqliteData!, date.sqliteData!,
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

    public func exportBackup(
        exportedAt: Date = Date(),
        connections: ConnectionSettings? = nil
    ) async throws -> CallupBackup {
        let trackedTelevision = try await trackedTelevisionSeries()
        var television: [TelevisionBackupItem] = []
        for tracked in trackedTelevision {
            television.append(TelevisionBackupItem(
                tracked: tracked,
                lineup: try await televisionLineup(seriesID: tracked.series.id)
            ))
        }
        return CallupBackup(
            exportedAt: exportedAt,
            television: television,
            movies: try await trackedMovies(),
            downloads: try await downloadSubmissions(),
            connections: connections
        )
    }

    @discardableResult
    public func restoreBackup(_ backup: CallupBackup) async throws -> BackupRestoreSummary {
        guard backup.formatVersion == CallupBackup.currentFormatVersion else {
            throw StoreError.unsupportedBackupVersion(backup.formatVersion)
        }
        try validateBackup(backup)

        try await transaction {
            _ = try await connection.query("DELETE FROM download_submissions")
            _ = try await connection.query("DELETE FROM tracked_media")
            _ = try await connection.query("DELETE FROM cache_entries")

            for item in backup.television {
                let series = item.tracked.series
                let metadata = try encoder.encode(series)
                let settings = try encoder.encode(item.tracked.downloadSettings)
                try await insertTrackedMedia(
                    kind: .televisionSeries,
                    id: series.id,
                    title: series.title,
                    metadata: metadata,
                    settings: settings,
                    addedAt: item.tracked.addedAt
                )
                try await putTelevisionLineup(item.lineup, seriesID: series.id)
            }

            for tracked in backup.movies {
                let movie = tracked.movie
                try await insertTrackedMedia(
                    kind: .movie,
                    id: movie.id,
                    title: movie.title,
                    metadata: try encoder.encode(movie),
                    settings: try encoder.encode(tracked.downloadSettings),
                    addedAt: tracked.addedAt
                )
            }

            for submission in backup.downloads {
                let acquisition = try submission.acquisitionContext.map(encoder.encode)
                _ = try await connection.query(
                    """
                    INSERT INTO download_submissions (
                        candidate_provider, candidate_external_id, title, client, state,
                        client_job_id, acquisition_payload, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        .text(submission.candidateID.provider),
                        .text(submission.candidateID.value),
                        .text(submission.title),
                        .text(submission.client.rawValue),
                        .text(submission.state.rawValue),
                        submission.clientJobID.map(SQLiteData.text) ?? .null,
                        acquisition?.sqliteData ?? .null,
                        submission.createdAt.sqliteData!,
                        submission.updatedAt.sqliteData!,
                    ]
                )
            }
        }

        return BackupRestoreSummary(
            televisionCount: backup.television.count,
            movieCount: backup.movies.count,
            downloadCount: backup.downloads.count,
            restoredConnections: backup.connections != nil
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

        let versionEightRows = try await connection.query(
            "SELECT version FROM schema_migrations WHERE version = 8"
        )
        if versionEightRows.isEmpty {
            try await migrate(version: 8) {
                _ = try await connection.query(
                    """
                    CREATE TABLE tracked_media (
                        media_kind TEXT NOT NULL,
                        provider TEXT NOT NULL,
                        external_id TEXT NOT NULL,
                        title TEXT NOT NULL,
                        metadata_payload BLOB NOT NULL,
                        settings_payload BLOB NOT NULL,
                        added_at REAL NOT NULL,
                        PRIMARY KEY (media_kind, provider, external_id)
                    ) WITHOUT ROWID
                    """
                )

                let televisionRows = try await connection.query(
                    """
                    SELECT provider, external_id, title, payload, added_at,
                           season_folders, preferred_resolution, preferred_video_codec
                    FROM tracked_television_series
                    """
                )
                for row in televisionRows {
                    guard
                        let provider = row.column("provider").flatMap(String.init(sqliteData:)),
                        let externalID = row.column("external_id").flatMap(String.init(sqliteData:)),
                        let title = row.column("title").flatMap(String.init(sqliteData:)),
                        let metadata = row.column("payload").flatMap(Data.init(sqliteData:)),
                        let addedAt = row.column("added_at").flatMap(Date.init(sqliteData:))
                    else {
                        throw StoreError.malformedCacheEntry
                    }
                    let settings = TelevisionDownloadSettings(
                        seasonFolders: row.column("season_folders")
                            .flatMap(Int.init(sqliteData:)) != 0,
                        preferredResolution: row.column("preferred_resolution")
                            .flatMap(String.init(sqliteData:))
                            .flatMap(VideoResolutionPreference.init(rawValue:)) ?? .p1080,
                        preferredVideoCodec: row.column("preferred_video_codec")
                            .flatMap(String.init(sqliteData:))
                            .flatMap(VideoCodecPreference.init(rawValue:)) ?? .hevc
                    )
                    let settingsPayload = try encoder.encode(settings)
                    _ = try await connection.query(
                        """
                        INSERT INTO tracked_media (
                            media_kind, provider, external_id, title,
                            metadata_payload, settings_payload, added_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                        [
                            .text(MediaKind.televisionSeries.rawValue),
                            .text(provider), .text(externalID), .text(title),
                            metadata.sqliteData!, settingsPayload.sqliteData!, addedAt.sqliteData!,
                        ]
                    )
                }

                _ = try await connection.query(
                    """
                    CREATE TABLE television_lineups_next (
                        series_media_kind TEXT NOT NULL
                            CHECK (series_media_kind = 'televisionSeries'),
                        series_provider TEXT NOT NULL,
                        series_external_id TEXT NOT NULL,
                        payload BLOB NOT NULL,
                        updated_at REAL NOT NULL,
                        PRIMARY KEY (
                            series_media_kind, series_provider, series_external_id
                        ),
                        FOREIGN KEY (
                            series_media_kind, series_provider, series_external_id
                        ) REFERENCES tracked_media(media_kind, provider, external_id)
                            ON DELETE CASCADE
                    ) WITHOUT ROWID
                    """
                )
                _ = try await connection.query(
                    """
                    INSERT INTO television_lineups_next (
                        series_media_kind, series_provider, series_external_id,
                        payload, updated_at
                    )
                    SELECT 'televisionSeries', series_provider, series_external_id,
                           payload, updated_at
                    FROM television_lineups
                    """
                )
                _ = try await connection.query("DROP TABLE television_lineups")
                _ = try await connection.query(
                    "ALTER TABLE television_lineups_next RENAME TO television_lineups"
                )
                _ = try await connection.query("DROP TABLE tracked_television_series")
            }
        }

        let versionNineRows = try await connection.query(
            "SELECT version FROM schema_migrations WHERE version = 9"
        )
        if versionNineRows.isEmpty {
            try await migrate(version: 9) {
                _ = try await connection.query(
                    "ALTER TABLE download_submissions ADD COLUMN acquisition_payload BLOB"
                )
                let rows = try await connection.query(
                    """
                    SELECT candidate_provider, candidate_external_id,
                           series_payload, episode_ids_payload
                    FROM download_submissions
                    WHERE series_payload IS NOT NULL
                    """
                )
                for row in rows {
                    guard
                        let provider = row.column("candidate_provider")
                            .flatMap(String.init(sqliteData:)),
                        let externalID = row.column("candidate_external_id")
                            .flatMap(String.init(sqliteData:)),
                        let seriesData = row.column("series_payload")
                            .flatMap(Data.init(sqliteData:))
                    else {
                        throw StoreError.malformedCacheEntry
                    }
                    let seriesID = try decoder.decode(ProviderReference.self, from: seriesData)
                    let episodeIDs = try row.column("episode_ids_payload")
                        .flatMap(Data.init(sqliteData:))
                        .map { try decoder.decode([ProviderReference].self, from: $0) } ?? []
                    let context = AcquisitionContext.television(
                        seriesID: seriesID,
                        episodeIDs: episodeIDs
                    )
                    let payload = try encoder.encode(context)
                    _ = try await connection.query(
                        """
                        UPDATE download_submissions SET acquisition_payload = ?
                        WHERE candidate_provider = ? AND candidate_external_id = ?
                        """,
                        [payload.sqliteData!, .text(provider), .text(externalID)]
                    )
                }
            }
        }

        let versionTenRows = try await connection.query(
            "SELECT version FROM schema_migrations WHERE version = 10"
        )
        if versionTenRows.isEmpty {
            try await migrate(version: 10) {
                _ = try await connection.query(
                    """
                    CREATE TABLE download_submissions_next (
                        candidate_provider TEXT NOT NULL,
                        candidate_external_id TEXT NOT NULL,
                        title TEXT NOT NULL,
                        client TEXT NOT NULL,
                        state TEXT NOT NULL,
                        client_job_id TEXT,
                        acquisition_payload BLOB,
                        created_at REAL NOT NULL,
                        updated_at REAL NOT NULL,
                        PRIMARY KEY (candidate_provider, candidate_external_id)
                    ) WITHOUT ROWID
                    """
                )
                _ = try await connection.query(
                    """
                    INSERT INTO download_submissions_next (
                        candidate_provider, candidate_external_id, title, client, state,
                        client_job_id, acquisition_payload, created_at, updated_at
                    )
                    SELECT candidate_provider, candidate_external_id, title, client, state,
                           client_job_id, acquisition_payload, created_at, updated_at
                    FROM download_submissions
                    """
                )
                _ = try await connection.query("DROP TABLE download_submissions")
                _ = try await connection.query(
                    "ALTER TABLE download_submissions_next RENAME TO download_submissions"
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
                series_media_kind, series_provider, series_external_id, payload, updated_at
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at
            """,
            [
                .text(MediaKind.televisionSeries.rawValue),
                .text(seriesID.provider), .text(seriesID.value),
                payload.sqliteData!, Date().sqliteData!,
            ]
        )
    }

    private func ensureTracked(_ seriesID: ProviderReference) async throws {
        do {
            try await ensureTracked(MediaReference(kind: .televisionSeries, id: seriesID))
        } catch StoreError.mediaNotTracked {
            throw StoreError.seriesNotTracked
        }
    }

    private func ensureTracked(_ media: MediaReference) async throws {
        try validate(namespace: media.id.provider, key: media.id.value)
        let rows = try await connection.query(
            """
            SELECT 1 FROM tracked_media
            WHERE media_kind = ? AND provider = ? AND external_id = ?
            """,
            [.text(media.kind.rawValue), .text(media.id.provider), .text(media.id.value)]
        )
        guard !rows.isEmpty else { throw StoreError.mediaNotTracked }
    }

    private func trackedMedia<Metadata: Codable & Sendable, Settings: Codable & Sendable>(
        kind: MediaKind
    ) async throws -> [StoredTrackedMedia<Metadata, Settings>] {
        let rows = try await connection.query(
            """
            SELECT metadata_payload, settings_payload, added_at
            FROM tracked_media
            WHERE media_kind = ?
            ORDER BY title COLLATE NOCASE, provider, external_id
            """,
            [.text(kind.rawValue)]
        )
        return try rows.map { try decodeTrackedMedia(row: $0) }
    }

    private func trackedMedia<Metadata: Codable & Sendable, Settings: Codable & Sendable>(
        kind: MediaKind,
        id: ProviderReference
    ) async throws -> StoredTrackedMedia<Metadata, Settings>? {
        try validate(namespace: id.provider, key: id.value)
        let rows = try await connection.query(
            """
            SELECT metadata_payload, settings_payload, added_at
            FROM tracked_media
            WHERE media_kind = ? AND provider = ? AND external_id = ?
            """,
            [.text(kind.rawValue), .text(id.provider), .text(id.value)]
        )
        guard let row = rows.first else { return nil }
        return try decodeTrackedMedia(row: row)
    }

    private func trackMedia<Metadata: Codable & Sendable, Settings: Codable & Sendable>(
        kind: MediaKind,
        id: ProviderReference,
        title: String,
        metadata: Metadata,
        defaultSettings: Settings,
        addedAt: Date
    ) async throws -> StoredTrackedMedia<Metadata, Settings> {
        try validate(namespace: id.provider, key: id.value)
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoreError.invalidCacheIdentity
        }
        let metadataPayload = try encoder.encode(metadata)
        let settingsPayload = try encoder.encode(defaultSettings)
        _ = try await connection.query(
            """
            INSERT INTO tracked_media (
                media_kind, provider, external_id, title,
                metadata_payload, settings_payload, added_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(media_kind, provider, external_id) DO UPDATE SET
                title = excluded.title,
                metadata_payload = excluded.metadata_payload
            """,
            [
                .text(kind.rawValue), .text(id.provider), .text(id.value), .text(title),
                metadataPayload.sqliteData!, settingsPayload.sqliteData!, addedAt.sqliteData!,
            ]
        )
        let stored: StoredTrackedMedia<Metadata, Settings>? = try await trackedMedia(
            kind: kind,
            id: id
        )
        guard let stored else { throw StoreError.malformedCacheEntry }
        return stored
    }

    private func insertTrackedMedia(
        kind: MediaKind,
        id: ProviderReference,
        title: String,
        metadata: Data,
        settings: Data,
        addedAt: Date
    ) async throws {
        _ = try await connection.query(
            """
            INSERT INTO tracked_media (
                media_kind, provider, external_id, title,
                metadata_payload, settings_payload, added_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .text(kind.rawValue), .text(id.provider), .text(id.value), .text(title),
                metadata.sqliteData!, settings.sqliteData!, addedAt.sqliteData!,
            ]
        )
    }

    private func validateBackup(_ backup: CallupBackup) throws {
        var media = Set<MediaReference>()
        for item in backup.television {
            let series = item.tracked.series
            try validate(namespace: series.id.provider, key: series.id.value)
            for episodeID in item.lineup.excludedEpisodes.union(item.lineup.includedEpisodes) {
                try validate(namespace: episodeID.provider, key: episodeID.value)
            }
            guard !series.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  media.insert(MediaReference(kind: .televisionSeries, id: series.id)).inserted
            else { throw StoreError.invalidBackup }
        }
        for tracked in backup.movies {
            let movie = tracked.movie
            try validate(namespace: movie.id.provider, key: movie.id.value)
            guard !movie.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  media.insert(MediaReference(kind: .movie, id: movie.id)).inserted
            else { throw StoreError.invalidBackup }
        }
        var candidates = Set<ProviderReference>()
        for submission in backup.downloads {
            try validate(
                namespace: submission.candidateID.provider,
                key: submission.candidateID.value
            )
            guard !submission.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  candidates.insert(submission.candidateID).inserted
            else { throw StoreError.invalidBackup }
            for target in submission.acquisitionContext?.targets ?? [] {
                try validate(namespace: target.media.id.provider, key: target.media.id.value)
                for ancestor in target.ancestors {
                    try validate(namespace: ancestor.id.provider, key: ancestor.id.value)
                }
            }
        }
    }

    private func setTrackedMediaSettings<Settings: Codable & Sendable>(
        media: MediaReference,
        settings: Settings
    ) async throws {
        try await ensureTracked(media)
        let payload = try encoder.encode(settings)
        _ = try await connection.query(
            """
            UPDATE tracked_media SET settings_payload = ?
            WHERE media_kind = ? AND provider = ? AND external_id = ?
            """,
            [
                payload.sqliteData!, .text(media.kind.rawValue),
                .text(media.id.provider), .text(media.id.value),
            ]
        )
    }

    private func untrackMedia(_ media: MediaReference) async throws {
        try validate(namespace: media.id.provider, key: media.id.value)
        _ = try await connection.query(
            "DELETE FROM tracked_media WHERE media_kind = ? AND provider = ? AND external_id = ?",
            [.text(media.kind.rawValue), .text(media.id.provider), .text(media.id.value)]
        )
    }

    private func decodeTrackedMedia<Metadata: Codable & Sendable, Settings: Codable & Sendable>(
        row: SQLiteRow
    ) throws -> StoredTrackedMedia<Metadata, Settings> {
        guard
            let metadata = row.column("metadata_payload").flatMap(Data.init(sqliteData:)),
            let settings = row.column("settings_payload").flatMap(Data.init(sqliteData:)),
            let addedAt = row.column("added_at").flatMap(Date.init(sqliteData:))
        else {
            throw StoreError.malformedCacheEntry
        }
        return StoredTrackedMedia(
            metadata: try decoder.decode(Metadata.self, from: metadata),
            settings: try decoder.decode(Settings.self, from: settings),
            addedAt: addedAt
        )
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
