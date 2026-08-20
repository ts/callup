import CallupCore
import CallupAutomation
import CallupDownloadClients
import CallupNewznab
import CallupPersistence
import CallupTMDB
import CallupTVMaze
import CallupUpdates
import Foundation
import Vapor

@main
enum CallupServer {
    static func main() async {
        do {
            var environment = try Environment.detect()
            try LoggingSystem.bootstrap(from: &environment)
            let application = try await Application.make(environment)
            let store = try await configuredStore()
            let connectionSettings = try configuredConnectionSettings()
            try configure(application, store: store, connectionSettings: connectionSettings)
            try await application.execute()
            try await application.asyncShutdown()
        } catch {
            print("Callup failed to start: \(error)")
        }
    }

    private static func configure(
        _ application: Application,
        store: ApplicationStore,
        connectionSettings: ConnectionSettingsStore
    ) throws {
        application.http.server.configuration.hostname = configuredHost()
        application.http.server.configuration.port = configuredPort()

        let metadata = TelevisionMetadataCatalog(
            suppliers: [
                CachedTelevisionMetadataProvider(
                    upstream: TVMazeClient(),
                    store: store
                )
            ]
        )
        let movieMetadata = ConfiguredMovieMetadataProvider(
            store: store,
            connections: connectionSettings
        )
        let downloadClientProbe = DownloadClientProbe()
        let sabnzbdClient = SABnzbdClient()
        let library = LibraryInventory()
        let reconciliationWorker = DownloadReconciliationWorker(
            store: store,
            connections: connectionSettings,
            statuses: sabnzbdClient
        ) { event in
            switch event {
            case let .completed(result) where result.updated > 0 || result.failures > 0:
                application.logger.info(
                    "Reconciled SABnzbd downloads",
                    metadata: [
                        "examined": "\(result.examined)",
                        "updated": "\(result.updated)",
                        "failures": "\(result.failures)",
                    ]
                )
            case .completed:
                break
            case let .failed(message):
                application.logger.warning(
                    "SABnzbd download reconciliation failed",
                    metadata: ["error": "\(message)"]
                )
            }
        }
        let revision = ProcessInfo.processInfo.environment["CALLUP_REVISION"] ?? "unknown"
        let updateRepository = ProcessInfo.processInfo.environment["CALLUP_UPDATE_REPOSITORY"]
            ?? "ts/callup"
        let updateDirectory = ProcessInfo.processInfo.environment["CALLUP_UPDATE_DIRECTORY"]
            ?? "/var/lib/callup/updates"
        let updates = CallupUpdateService(
            revision: revision,
            provider: GitHubCallupUpdateClient(repository: updateRepository),
            directory: URL(fileURLWithPath: updateDirectory, isDirectory: true)
        )
        application.lifecycle.use(StoreLifecycle(store: store))
        application.lifecycle.use(
            DownloadReconciliationLifecycle(worker: reconciliationWorker)
        )

        try registerRoutes(
            on: application,
            store: store,
            connectionSettings: connectionSettings,
            metadata: metadata,
            movieMetadata: movieMetadata,
            downloadClientProbe: downloadClientProbe,
            sabnzbdClient: sabnzbdClient,
            library: library,
            updates: updates,
            revision: revision
        )
    }

    static func metadataAbort(_ error: Error) -> Abort {
        switch error {
        case TVMazeError.emptyQuery:
            Abort(.badRequest, reason: "Enter a show name.")
        case TVMazeError.invalidIdentifier, TVMazeError.unsupportedProvider:
            Abort(.badRequest, reason: "The show identifier is invalid.")
        case TVMazeError.rateLimited:
            Abort(.serviceUnavailable, reason: "TVmaze is busy. Try again shortly.")
        case let TVMazeError.httpStatus(status):
            Abort(.badGateway, reason: "TVmaze returned HTTP \(status).")
        default:
            Abort(.badGateway, reason: "TVmaze could not be reached.")
        }
    }

    static func movieMetadataAbort(_ error: Error) -> Abort {
        switch error {
        case MovieMetadataConfigurationError.unavailable:
            Abort(.serviceUnavailable, reason: "Connect TMDB in Settings before searching movies.")
        case TMDBError.invalidIdentifier, TMDBError.unsupportedProvider,
             MetadataCatalogError.unsupportedReference:
            Abort(.badRequest, reason: "The movie identifier is invalid.")
        case TMDBError.rateLimited:
            Abort(.serviceUnavailable, reason: "TMDB is busy. Try again shortly.")
        case TMDBError.unauthorized:
            Abort(.badGateway, reason: "TMDB rejected its access token.")
        case let TMDBError.httpStatus(status):
            Abort(.badGateway, reason: "TMDB returned HTTP \(status).")
        default:
            Abort(.badGateway, reason: "TMDB could not be reached.")
        }
    }

    static func verifiedReleasePage(
        metadata: any TelevisionMetadataProvider,
        indexer: any TelevisionReleaseIndexer,
        seriesID: ProviderReference,
        season: Int?,
        episode: Int?
    ) async throws -> ReleaseSearchPage {
        let series = try await metadata.series(for: seriesID)
        // Newznab indexers commonly support TheTVDB as their canonical TV key,
        // but may treat multiple simultaneous IDs as an impossible AND query.
        // Send the strongest single ID instead of combining every known ID.
        let usesTVDB = series.theTVDBID != nil
        let page = try await indexer.searchTelevision(
            query: series.title,
            tvmazeID: usesTVDB ? nil : series.id.value,
            tvdbID: series.theTVDBID,
            imdbID: nil,
            season: season,
            episode: episode
        )
        let candidates = page.candidates.filter {
            ReleaseIdentityFilter.matches(
                $0,
                series: series,
                requireReportedIdentity: false
            )
        }
        return ReleaseSearchPage(
            offset: page.offset,
            total: candidates.count,
            candidates: candidates
        )
    }

    static func configuredIndexer(
        using settings: ConnectionSettingsStore
    ) async -> NewznabClient? {
        guard let connection = await configuredIndexerConnection(using: settings),
              let apiKey = try? NewznabAPIKey(connection.apiKey) else { return nil }
        return NewznabClient(
            provider: connection.name.lowercased(),
            endpoint: connection.endpoint,
            apiKey: apiKey
        )
    }

    static func searchResult<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async -> Result<Value, any Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    static func metadataIssue(source: String, error: any Error) -> MetadataIssue {
        let message: String
        switch error {
        case MovieMetadataConfigurationError.unavailable:
            message = "Movie metadata is unavailable in this Callup build."
        case TMDBError.unauthorized:
            message = "TMDB rejected its access token."
        case TMDBError.rateLimited:
            message = "TMDB is busy. Try again shortly."
        case let TMDBError.httpStatus(status):
            message = "TMDB returned HTTP \(status)."
        case is DecodingError:
            message = "\(source) returned data Callup could not read."
        default:
            message = "\(source) could not be reached."
        }
        return MetadataIssue(source: source, message: message)
    }

    static func configuredIndexerConnection(
        using settings: ConnectionSettingsStore
    ) async -> IndexerConnection? {
        if let saved = await settings.load().indexer { return saved }
        let environment = ProcessInfo.processInfo.environment
        guard let rawKey = environment["CALLUP_NZBGEEK_API_KEY"],
              let endpoint = URL(
                string: environment["CALLUP_NZBGEEK_URL"] ?? "https://api.nzbgeek.info/api"
              ) else {
            return nil
        }
        return IndexerConnection(name: "NZBGeek", endpoint: endpoint, apiKey: rawKey)
    }

    static func configuredLibrarySettings() -> LibrarySettings {
        let environment = ProcessInfo.processInfo.environment
        return LibrarySettings(
            televisionRoot: environment["CALLUP_TV_LIBRARY_PATH"]
                ?? "/data/complete/Television",
            movieRoot: environment["CALLUP_MOVIE_LIBRARY_PATH"]
                ?? "/data/complete/Movies"
        )
    }

    private static func configuredPort() -> Int {
        guard
            let rawPort = ProcessInfo.processInfo.environment["CALLUP_PORT"],
            let port = Int(rawPort),
            (1...65_535).contains(port)
        else {
            return 8484
        }
        return port
    }

    static func lastDownloadedAt(
        for mediaID: ProviderReference,
        downloads: [DownloadSubmission]
    ) -> Date? {
        downloads.compactMap { submission -> Date? in
            guard submission.state == .downloaded,
                  let context = submission.acquisitionContext else {
                return nil
            }
            let matches = context.targets.contains { target in
                target.media.id == mediaID || target.ancestors.contains { $0.id == mediaID }
            }
            return matches ? submission.updatedAt : nil
        }.max()
    }

    private static func configuredHost() -> String {
        let configured = ProcessInfo.processInfo.environment["CALLUP_HOST"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (configured?.isEmpty == false ? configured : nil) ?? "127.0.0.1"
    }

    private static func configuredStore() async throws -> ApplicationStore {
        let environment = ProcessInfo.processInfo.environment
        let fileURL: URL
        if let path = environment["CALLUP_DATABASE_PATH"] {
            fileURL = URL(fileURLWithPath: path)
        } else {
            #if os(macOS)
            fileURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
                .appending(path: "Callup", directoryHint: .isDirectory)
                .appending(path: "callup.sqlite")
            #else
            fileURL = URL(fileURLWithPath: "/var/lib/callup/callup.sqlite")
            #endif
        }
        return try await ApplicationStore.open(fileURL: fileURL)
    }

    private static func configuredConnectionSettings() throws -> ConnectionSettingsStore {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["CALLUP_CONNECTIONS_PATH"] {
            return try ConnectionSettingsStore(fileURL: URL(fileURLWithPath: path))
        }
        let databasePath: URL
        if let path = environment["CALLUP_DATABASE_PATH"] {
            databasePath = URL(fileURLWithPath: path)
        } else {
            #if os(macOS)
            databasePath = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            )[0]
                .appending(path: "Callup", directoryHint: .isDirectory)
                .appending(path: "callup.sqlite")
            #else
            databasePath = URL(fileURLWithPath: "/var/lib/callup/callup.sqlite")
            #endif
        }
        return try ConnectionSettingsStore(
            fileURL: databasePath.deletingLastPathComponent().appending(path: "connections.json")
        )
    }

    static func connectionURL(_ value: String) throws -> URL {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw Abort(.badRequest, reason: "Enter a complete http:// or https:// address.")
        }
        return url
    }

    static func connectionResponse(
        using settings: ConnectionSettingsStore
    ) async -> ConnectionSettingsResponse {
        let saved = await settings.load()
        let indexer = await configuredIndexerConnection(using: settings)
        let movieMetadataSource = await resolvedTMDBCredential(using: settings)?.source
        return ConnectionSettingsResponse(
            indexer: indexer.map {
                IndexerConnectionResponse(
                    name: $0.name,
                    endpoint: $0.endpoint.absoluteString,
                    configured: true,
                    source: saved.indexer == nil ? "environment" : "saved"
                )
            },
            downloadClient: saved.downloadClient.map {
                DownloadClientConnectionResponse(
                    kind: $0.kind,
                    name: $0.kind.displayName,
                    endpoint: $0.endpoint.absoluteString,
                    username: $0.username,
                    configured: true
                )
            },
            metadata: movieMetadataSource.map {
                [MetadataConnectionResponse(
                    provider: TMDBClient.providerName,
                    name: "TMDB",
                    configured: true,
                    source: $0
                )]
            } ?? []
        )
    }

    static func downloadClientAbort(_ error: Error, kind: DownloadClientKind) -> Abort {
        let name = kind.displayName
        return switch error {
        case DownloadClientProbeError.invalidEndpoint:
            Abort(.badRequest, reason: "The \(name) connection details are incomplete.")
        case let DownloadClientProbeError.httpStatus(status):
            Abort(.badGateway, reason: "\(name) returned HTTP \(status).")
        case DownloadClientProbeError.rejected:
            Abort(.badGateway, reason: "\(name) rejected the credentials.")
        default:
            Abort(.badGateway, reason: "\(name) could not be reached.")
        }
    }

    static func submissionAbort(_ error: Error) -> Abort {
        switch error {
        case let NewznabClientError.httpStatus(status):
            Abort(.badGateway, reason: "The indexer returned HTTP \(status) while fetching the NZB.")
        case NewznabClientError.requestFailed, NewznabClientError.invalidDownload:
            Abort(.badGateway, reason: "The NZB could not be fetched from the indexer.")
        case let SABnzbdClientError.httpStatus(status):
            Abort(.badGateway, reason: "SABnzbd returned HTTP \(status).")
        case SABnzbdClientError.rejected, SABnzbdClientError.invalidResponse:
            Abort(.badGateway, reason: "SABnzbd did not accept the download or its destination folder.")
        case SABnzbdClientError.requestFailed:
            Abort(.badGateway, reason: "SABnzbd could not be reached while sending the NZB.")
        default:
            Abort(.badGateway, reason: "The release could not be sent to SABnzbd.")
        }
    }

    static func indexerAbort(_ error: Error) -> Abort {
        switch error {
        case NewznabRequestError.emptyQuery:
            Abort(.badRequest, reason: "Enter a show name.")
        case let NewznabClientError.httpStatus(status):
            Abort(.badGateway, reason: "NZBGeek returned HTTP \(status).")
        case let NewznabResponseError.providerError(code, _):
            Abort(.badGateway, reason: "NZBGeek returned API error \(code).")
        default:
            Abort(.badGateway, reason: "NZBGeek could not be reached.")
        }
    }
}

struct ResolvedTMDBCredential: Sendable {
    let token: TMDBAccessToken
    let source: String
}

private func resolvedTMDBCredential(
    using connections: ConnectionSettingsStore
) async -> ResolvedTMDBCredential? {
    let environmentValue = ProcessInfo.processInfo.environment["CALLUP_TMDB_ACCESS_TOKEN"]
    let savedValue = await connections.load().metadataProviders
        .first { $0.provider == TMDBClient.providerName }?.secret
    let candidates: [(String?, String)] = [
        (environmentValue, "environment"),
        (savedValue, "saved"),
        (BundledTMDBCredential.accessToken, "bundled"),
    ]
    for (value, source) in candidates {
        if let value, let token = try? TMDBAccessToken(value) {
            return ResolvedTMDBCredential(token: token, source: source)
        }
    }
    return nil
}

struct ConfiguredMovieMetadataProvider: MovieMetadataSupplier {
    let store: ApplicationStore
    let connections: ConnectionSettingsStore

    let metadataSupplier = MetadataSupplier(
        id: TMDBClient.providerName,
        displayName: "TMDB",
        supportedMediaKinds: [.movie]
    )

    var isConfigured: Bool {
        get async {
            await resolvedTMDBCredential(using: connections) != nil
        }
    }

    func searchMovies(query: String) async throws -> [Movie] {
        try await provider().searchMovies(query: query)
    }

    func movie(for movieID: ProviderReference) async throws -> Movie {
        try await provider().movie(for: movieID)
    }

    private func provider() async throws -> CachedMovieMetadataProvider {
        guard let credential = await resolvedTMDBCredential(using: connections) else {
            throw MovieMetadataConfigurationError.unavailable
        }
        return CachedMovieMetadataProvider(
            upstream: TMDBClient(token: credential.token),
            store: store
        )
    }
}

enum MovieMetadataConfigurationError: Error {
    case unavailable
}

struct SeriesSearchResponse: Content {
    let results: [TelevisionSeries]
}

struct MediaSearchResponse: Content {
    let results: [MediaSearchResult]
    let metadataIssues: [MetadataIssue]
}

struct MetadataIssue: Content {
    let source: String
    let message: String
}

struct TrackedSeriesListResponse: Content {
    let results: [TrackedSeriesResponse]
}

struct TrackedSeriesResponse: Content {
    let series: TelevisionSeries
    let addedAt: Date
    let nextAirDate: String?
    let downloadSettings: TelevisionDownloadSettings
}

struct TrackSeriesRequest: Content {
    let series: TelevisionSeries
}

struct TrackedMovieListResponse: Content {
    let results: [TrackedMovieResponse]
}

struct TrackedMovieResponse: Content {
    let movie: Movie
    let addedAt: Date
    let downloadSettings: MovieDownloadSettings
    let onDisk: Bool
    let libraryFiles: [LibraryFileDetails]
}

struct LineupResponse: Content {
    let series: [TrackedSeriesResponse]
    let movies: [TrackedMovieResponse]
    let order: [LineupOrderItem]
}

struct LineupOrderItem: Content {
    let kind: MediaKind
    let id: ProviderReference
    let title: String
    let nextAvailableDate: String?
    let lastDownloadedAt: Date?
}

enum LineupSort: String {
    case title
    case nextAiring
    case lastDownloaded

    func areInIncreasingOrder(_ lhs: LineupOrderItem, _ rhs: LineupOrderItem) -> Bool {
        switch self {
        case .title:
            return titleOrder(lhs, rhs)
        case .nextAiring:
            let lhsDate = lhs.nextAvailableDate ?? "9999-12-31"
            let rhsDate = rhs.nextAvailableDate ?? "9999-12-31"
            return lhsDate == rhsDate ? titleOrder(lhs, rhs) : lhsDate < rhsDate
        case .lastDownloaded:
            switch (lhs.lastDownloadedAt, rhs.lastDownloadedAt) {
            case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                return lhsDate > rhsDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return titleOrder(lhs, rhs)
            }
        }
    }

    private func titleOrder(_ lhs: LineupOrderItem, _ rhs: LineupOrderItem) -> Bool {
        lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }
}

struct TrackMovieRequest: Content {
    let movie: Movie
}

struct SetMovieDownloadSettingsRequest: Content {
    let preferredResolution: VideoResolutionPreference
    let preferredVideoCodec: VideoCodecPreference
}

struct SubmitMovieDownloadRequest: Content {
    let candidateID: ProviderReference
}

struct SetLineupRequest: Content {
    let monitoring: TelevisionEpisodeMonitoring?
    let seasonNumber: Int?
    let episodeID: ProviderReference?
    let episodeIDs: [ProviderReference]?
    let included: Bool?
}

struct SetTelevisionDownloadSettingsRequest: Content {
    let seasonFolders: Bool
    let preferredResolution: TelevisionResolutionPreference
    let preferredVideoCodec: TelevisionVideoCodecPreference
}

struct ResolveQualityRequest: Content {
    let target: MediaReference
    let ancestors: [MediaReference]
}

struct SetQualityOverrideRequest: Content {
    let media: MediaReference
    let preference: VideoQualityPreference?
}

extension TrackedTelevisionSeries: Content {}
extension TrackedMovie: Content {}
extension MovieDownloadSettings: Content {}
extension TelevisionLineup: Content {}
extension TelevisionDownloadSettings: Content {}
extension QualityDefaults: Content {}
extension VideoQualityPreference: Content {}
extension AcquisitionPreferenceSnapshot: Content {}
extension MediaReference: Content {}
extension LibraryFileDetails: Content {}

func localDateString(_ date: Date = Date()) -> String {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(
        format: "%04d-%02d-%02d",
        components.year ?? 0,
        components.month ?? 0,
        components.day ?? 0
    )
}

struct SeasonListResponse: Content {
    let seasons: [TelevisionSeason]
    let onDiskEpisodeIDs: [ProviderReference]
    let onDiskEpisodes: [OnDiskEpisodeResponse]
}

struct OnDiskEpisodeResponse: Content {
    let episodeID: ProviderReference
    let libraryFiles: [LibraryFileDetails]
}

struct ReleaseSearchResponse: Content {
    let offset: Int
    let total: Int
    let results: [ReleaseCandidate]
}

struct SetIndexerConnectionRequest: Content {
    let name: String
    let endpoint: String
    let apiKey: String?
}

struct SetDownloadClientConnectionRequest: Content {
    let kind: DownloadClientKind
    let endpoint: String
    let username: String?
    let secret: String?
}

struct SetMetadataProviderConnectionRequest: Content {
    let secret: String?
}

struct IndexerConnectionResponse: Content {
    let name: String
    let endpoint: String
    let configured: Bool
    let source: String
}

struct DownloadClientConnectionResponse: Content {
    let kind: DownloadClientKind
    let name: String
    let endpoint: String
    let username: String?
    let configured: Bool
}

struct MetadataConnectionResponse: Content {
    let provider: String
    let name: String
    let configured: Bool
    let source: String
}

struct ConnectionSettingsResponse: Content {
    let indexer: IndexerConnectionResponse?
    let downloadClient: DownloadClientConnectionResponse?
    let metadata: [MetadataConnectionResponse]
}

struct RequestUpdateRequest: Content {
    let version: String
    let confirm: Bool
}

extension CallupUpdateStatus: Content {}

struct SubmitDownloadRequest: Content {
    let candidateID: ProviderReference
    let seriesID: ProviderReference
    let episodeIDs: [ProviderReference]
}

struct AssociateDownloadRequest: Content {
    let seriesID: ProviderReference
    let episodeIDs: [ProviderReference]
}

struct DownloadSubmissionResponse: Content {
    let submission: DownloadSubmission
    let alreadySubmitted: Bool
}

struct DownloadSubmissionListResponse: Content {
    let results: [DownloadSubmission]
    let groups: [DownloadActivityGroup]
}

struct DownloadActivityGroup: Content {
    let id: String
    let title: String
    let detail: String?
    let results: [DownloadSubmission]
}

extension DownloadSubmission: Content {}
extension CallupBackup: Content {}
extension BackupRestoreSummary: Content {}

struct HealthResponse: Content {
    let status: String
    let mode: String
    let metadata: [String]
    let indexer: String
    let downloader: String
    let database: String
    let revision: String
}

private struct StoreLifecycle: LifecycleHandler {
    let store: ApplicationStore

    func shutdownAsync(_ application: Application) async {
        try? await store.close()
    }
}

private struct DownloadReconciliationLifecycle: LifecycleHandler {
    let worker: DownloadReconciliationWorker

    func didBootAsync(_ application: Application) async throws {
        await worker.start()
    }

    func shutdownAsync(_ application: Application) async {
        await worker.stop()
    }
}
