import CallupCore
import CallupAutomation
import CallupDownloadClients
import CallupNewznab
import CallupPersistence
import CallupTVMaze
import Foundation
import Vapor

@main
enum CallupServer {
    static func main() async throws {
        var environment = try Environment.detect()
        try LoggingSystem.bootstrap(from: &environment)
        let application = try await Application.make(environment)

        do {
            let store = try await configuredStore()
            let connectionSettings = try configuredConnectionSettings()
            configure(application, store: store, connectionSettings: connectionSettings)
            try await application.execute()
        } catch {
            application.logger.report(error: error)
            try await application.asyncShutdown()
            throw error
        }

        try await application.asyncShutdown()
    }

    private static func configure(
        _ application: Application,
        store: ApplicationStore,
        connectionSettings: ConnectionSettingsStore
    ) {
        application.http.server.configuration.hostname = "127.0.0.1"
        application.http.server.configuration.port = configuredPort()

        let metadata = TelevisionMetadataCatalog(
            suppliers: [
                CachedTelevisionMetadataProvider(
                    upstream: TVMazeClient(),
                    store: store
                )
            ]
        )
        let downloadClientProbe = DownloadClientProbe()
        let sabnzbdClient = SABnzbdClient()
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
        application.lifecycle.use(StoreLifecycle(store: store))
        application.lifecycle.use(
            DownloadReconciliationLifecycle(worker: reconciliationWorker)
        )

        application.get { _ in
            Response(
                status: .ok,
                headers: ["content-type": "text/html; charset=utf-8"],
                body: .init(string: indexHTML)
            )
        }

        application.get("api", "tv", "search") { request async throws -> SeriesSearchResponse in
            guard let query = request.query[String.self, at: "q"] else {
                throw Abort(.badRequest, reason: "Query parameter 'q' is required.")
            }

            do {
                return SeriesSearchResponse(results: try await metadata.searchSeries(query: query))
            } catch {
                throw metadataAbort(error)
            }
        }

        application.get("api", "tv", "tracked") { _ async throws -> TrackedSeriesListResponse in
            let tracked = try await store.trackedTelevisionSeries()
            let today = localDateString()
            var results: [TrackedSeriesResponse] = []

            for item in tracked {
                let hasEnded = item.series.status?.caseInsensitiveCompare("ended") == .orderedSame
                let nextAirDate: String?
                if hasEnded {
                    nextAirDate = nil
                } else {
                    let episodes = try? await metadata.episodes(for: item.series.id)
                    nextAirDate = episodes.flatMap {
                        TelevisionCatalog.nextAirDate(from: $0, onOrAfter: today)
                    }
                }
                results.append(TrackedSeriesResponse(
                    series: item.series,
                    addedAt: item.addedAt,
                    nextAirDate: nextAirDate,
                    downloadSettings: item.downloadSettings
                ))
            }

            return TrackedSeriesListResponse(results: results)
        }

        application.post("api", "tv", "tracked") { request async throws -> TrackedTelevisionSeries in
            let input = try request.content.decode(TrackSeriesRequest.self)
            let wasTracked = try await store.trackedTelevisionSeries(id: input.series.id) != nil
            let tracked = try await store.trackTelevisionSeries(input.series)
            if !wasTracked {
                try await store.setTelevisionEpisodeMonitoring(
                    seriesID: input.series.id,
                    monitoring: .future,
                    futureCutoffDate: localDateString()
                )
            }
            return tracked
        }

        application.delete("api", "tv", "tracked", ":provider", ":id") {
            request async throws -> HTTPStatus in
            let provider = try request.parameters.require("provider")
            let id = try request.parameters.require("id")
            try await store.untrackTelevisionSeries(
                id: ProviderReference(provider: provider, value: id)
            )
            return .noContent
        }

        application.get("api", "tv", "tracked", ":provider", ":id", "lineup") {
            request async throws -> TelevisionLineup in
            let seriesID = ProviderReference(
                provider: try request.parameters.require("provider"),
                value: try request.parameters.require("id")
            )
            return try await store.televisionLineup(seriesID: seriesID)
        }

        application.put("api", "tv", "tracked", ":provider", ":id", "lineup") {
            request async throws -> TelevisionLineup in
            let seriesID = ProviderReference(
                provider: try request.parameters.require("provider"),
                value: try request.parameters.require("id")
            )
            let input = try request.content.decode(SetLineupRequest.self)
            do {
                if let monitoring = input.monitoring {
                    try await store.setTelevisionEpisodeMonitoring(
                        seriesID: seriesID,
                        monitoring: monitoring,
                        futureCutoffDate: monitoring == .future ? localDateString() : nil
                    )
                } else if let episodeID = input.episodeID {
                    guard let seasonNumber = input.seasonNumber,
                          let seasonEpisodeIDs = input.episodeIDs,
                          seasonEpisodeIDs.contains(episodeID),
                          let included = input.included else {
                        throw Abort(.badRequest, reason: "The episode's season is required.")
                    }
                    try await store.setTelevisionEpisodeIncluded(
                        seriesID: seriesID,
                        seasonNumber: seasonNumber,
                        episodeID: episodeID,
                        seasonEpisodeIDs: seasonEpisodeIDs,
                        included: included
                    )
                } else {
                    guard let seasonNumber = input.seasonNumber,
                          let included = input.included else {
                        throw Abort(.badRequest, reason: "A season number is required.")
                    }
                    try await store.setTelevisionSeasonIncluded(
                        seriesID: seriesID,
                        seasonNumber: seasonNumber,
                        episodeIDs: input.episodeIDs ?? [],
                        included: included
                    )
                }
            } catch ApplicationStore.StoreError.seriesNotTracked {
                throw Abort(.conflict, reason: "Add the show before choosing its lineup.")
            }
            return try await store.televisionLineup(seriesID: seriesID)
        }

        application.put("api", "tv", "tracked", ":provider", ":id", "download-settings") {
            request async throws -> TelevisionDownloadSettings in
            let seriesID = ProviderReference(
                provider: try request.parameters.require("provider"),
                value: try request.parameters.require("id")
            )
            let input = try request.content.decode(SetTelevisionDownloadSettingsRequest.self)
            do {
                return try await store.setTelevisionDownloadSettings(
                    seriesID: seriesID,
                    settings: TelevisionDownloadSettings(
                        seasonFolders: input.seasonFolders,
                        preferredResolution: input.preferredResolution,
                        preferredVideoCodec: input.preferredVideoCodec
                    )
                )
            } catch ApplicationStore.StoreError.seriesNotTracked {
                throw Abort(.notFound, reason: "That show is not tracked.")
            }
        }

        application.get("api", "tv", "series", ":id", "seasons") {
            request async throws -> SeasonListResponse in
            let id = try request.parameters.require("id")
            let reference = ProviderReference(provider: TVMazeClient.providerName, value: id)

            do {
                let episodes = try await metadata.episodes(for: reference)
                return SeasonListResponse(seasons: TelevisionCatalog.seasons(from: episodes))
            } catch {
                throw metadataAbort(error)
            }
        }

        application.get("api", "tv", "releases") { request async throws -> ReleaseSearchResponse in
            guard let client = await configuredIndexer(using: connectionSettings) else {
                throw Abort(.serviceUnavailable, reason: "No search indexer is connected.")
            }
            let indexer = CachedTelevisionReleaseIndexer(upstream: client, store: store)
            guard let tvmazeID = request.query[String.self, at: "tvmazeID"] else {
                throw Abort(.badRequest, reason: "A TVmaze show identifier is required.")
            }

            do {
                let seriesID = ProviderReference(provider: TVMazeClient.providerName, value: tvmazeID)
                let page = try await verifiedReleasePage(
                    metadata: metadata,
                    indexer: indexer,
                    seriesID: seriesID,
                    season: request.query[Int.self, at: "season"],
                    episode: request.query[Int.self, at: "episode"]
                )
                let settings = try await store.trackedTelevisionSeries(id: seriesID)?.downloadSettings
                    ?? TelevisionDownloadSettings(
                        preferredResolution: .any,
                        preferredVideoCodec: .any
                    )
                return ReleaseSearchResponse(
                    offset: page.offset,
                    total: page.total,
                    results: ReleasePreferenceRanker.sorted(page.candidates, settings: settings)
                )
            } catch {
                if error is TVMazeError { throw metadataAbort(error) }
                throw indexerAbort(error)
            }
        }

        application.get("api", "settings", "connections") { _ async -> ConnectionSettingsResponse in
            let saved = await connectionSettings.load()
            let indexer = await configuredIndexerConnection(using: connectionSettings)
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
                }
            )
        }

        application.put("api", "settings", "connections", "indexer") {
            request async throws -> ConnectionSettingsResponse in
            let input = try request.content.decode(SetIndexerConnectionRequest.self)
            let endpoint = try connectionURL(input.endpoint)
            let existing = await configuredIndexerConnection(using: connectionSettings)
            let apiKey = input.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let secret = apiKey.flatMap({ $0.isEmpty ? nil : $0 }) ?? existing?.apiKey else {
                throw Abort(.badRequest, reason: "Enter the indexer API key.")
            }
            let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw Abort(.badRequest, reason: "Enter an indexer name.") }
            try await connectionSettings.setIndexer(
                IndexerConnection(name: name, endpoint: endpoint, apiKey: secret)
            )
            return await connectionResponse(using: connectionSettings)
        }

        application.delete("api", "settings", "connections", "indexer") {
            _ async throws -> HTTPStatus in
            try await connectionSettings.setIndexer(nil)
            return .noContent
        }

        application.put("api", "settings", "connections", "download-client") {
            request async throws -> ConnectionSettingsResponse in
            let input = try request.content.decode(SetDownloadClientConnectionRequest.self)
            let endpoint = try connectionURL(input.endpoint)
            let saved = await connectionSettings.load().downloadClient
            let suppliedSecret = input.secret?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let secret = suppliedSecret.flatMap({ $0.isEmpty ? nil : $0 })
                ?? (saved?.kind == input.kind ? saved?.secret : nil) else {
                throw Abort(.badRequest, reason: input.kind == .sabnzbd
                    ? "Enter the SABnzbd API key."
                    : "Enter the NZBGet password.")
            }
            let username = input.username?.trimmingCharacters(in: .whitespacesAndNewlines)
            if input.kind == .nzbget, username?.isEmpty != false {
                throw Abort(.badRequest, reason: "Enter the NZBGet username.")
            }
            let connection = DownloadClientConnection(
                kind: input.kind,
                endpoint: endpoint,
                username: input.kind == .nzbget ? username : nil,
                secret: secret
            )
            do {
                _ = try await downloadClientProbe.test(connection)
            } catch {
                throw downloadClientAbort(error, kind: input.kind)
            }
            try await connectionSettings.setDownloadClient(connection)
            return await connectionResponse(using: connectionSettings)
        }

        application.delete("api", "settings", "connections", "download-client") {
            _ async throws -> HTTPStatus in
            try await connectionSettings.setDownloadClient(nil)
            return .noContent
        }

        application.get("api", "downloads") { _ async throws -> DownloadSubmissionListResponse in
            DownloadSubmissionListResponse(results: try await store.downloadSubmissions())
        }

        application.post("api", "downloads") { request async throws -> DownloadSubmissionResponse in
            let input = try request.content.decode(SubmitDownloadRequest.self)
            guard let downloadConnection = await connectionSettings.load().downloadClient,
                  downloadConnection.kind == .sabnzbd else {
                throw Abort(.serviceUnavailable, reason: "Connect SABnzbd before sending a release.")
            }
            guard let indexerConnection = await configuredIndexerConnection(using: connectionSettings),
                  input.candidateID.provider == indexerConnection.name.lowercased(),
                  let indexer = await configuredIndexer(using: connectionSettings) else {
                throw Abort(.badRequest, reason: "That release does not belong to the connected indexer.")
            }

            let episodes: [TelevisionEpisode]
            do {
                let allEpisodes = try await metadata.episodes(for: input.seriesID)
                let requestedIDs = Set(input.episodeIDs)
                episodes = allEpisodes.filter { requestedIDs.contains($0.id) }
            } catch {
                throw metadataAbort(error)
            }
            guard !input.episodeIDs.isEmpty,
                  episodes.count == Set(input.episodeIDs).count,
                  let season = episodes.first?.seasonNumber,
                  episodes.allSatisfy({ $0.seasonNumber == season && $0.episodeNumber != nil }) else {
                throw Abort(.badRequest, reason: "The release must identify valid episodes from one season.")
            }
            guard let tracked = try await store.trackedTelevisionSeries(id: input.seriesID) else {
                throw Abort(.conflict, reason: "Add the show before sending one of its releases.")
            }

            var verifiedCandidate: ReleaseCandidate?
            do {
                for episode in episodes {
                    let page = try await verifiedReleasePage(
                        metadata: metadata,
                        indexer: indexer,
                        seriesID: input.seriesID,
                        season: season,
                        episode: episode.episodeNumber
                    )
                    guard let candidate = page.candidates.first(where: { $0.id == input.candidateID }) else {
                        throw Abort(
                            .conflict,
                            reason: "The indexer did not verify that release for this exact series. Search again."
                        )
                    }
                    verifiedCandidate = candidate
                }
            } catch let abort as Abort {
                throw abort
            } catch {
                if error is TVMazeError { throw metadataAbort(error) }
                throw indexerAbort(error)
            }
            guard let verifiedCandidate else {
                throw Abort(.conflict, reason: "The release could not be verified.")
            }

            switch try await store.reserveDownloadSubmission(
                candidateID: input.candidateID,
                title: verifiedCandidate.title,
                client: .sabnzbd
            ) {
            case let .existing(submission):
                return DownloadSubmissionResponse(submission: submission, alreadySubmitted: true)
            case .reserved:
                do {
                    let nzb = try await indexer.download(identifier: input.candidateID.value)
                    let destination = TelevisionDownloadDestination(
                        series: tracked.series,
                        seasonNumber: season,
                        settings: tracked.downloadSettings
                    )
                    let televisionCategory = try await sabnzbdClient.category(
                        named: "tv",
                        connection: downloadConnection
                    )
                    let category = televisionCategory.appending(
                        name: destination.categoryName,
                        relativeDirectory: destination.relativeDirectory
                    )
                    try await sabnzbdClient.ensureCategory(category, connection: downloadConnection)
                    let result = try await sabnzbdClient.submit(
                        nzb: nzb,
                        title: verifiedCandidate.title,
                        category: category.name,
                        connection: downloadConnection
                    )
                    _ = try await store.finishDownloadSubmission(
                        candidateID: input.candidateID,
                        jobID: result.jobID
                    )
                    let associated = try await store.associateDownloadSubmission(
                        candidateID: input.candidateID,
                        seriesID: input.seriesID,
                        episodeIDs: input.episodeIDs
                    )
                    return DownloadSubmissionResponse(
                        submission: associated,
                        alreadySubmitted: false
                    )
                } catch {
                    if case let SABnzbdClientError.requestFailed(code) = error {
                        request.logger.warning(
                            "SABnzbd submission transport failed",
                            metadata: ["url-error-code": "\(code?.rawValue ?? 0)"]
                        )
                    }
                    try? await store.failDownloadSubmission(candidateID: input.candidateID)
                    throw submissionAbort(error)
                }
            }
        }

        application.put("api", "downloads", ":provider", ":id", "context") {
            request async throws -> DownloadSubmission in
            let candidateID = ProviderReference(
                provider: try request.parameters.require("provider"),
                value: try request.parameters.require("id")
            )
            let input = try request.content.decode(AssociateDownloadRequest.self)
            guard try await store.downloadSubmission(candidateID: candidateID) != nil else {
                throw Abort(.notFound, reason: "That download is not known to Callup.")
            }
            return try await store.associateDownloadSubmission(
                candidateID: candidateID,
                seriesID: input.seriesID,
                episodeIDs: input.episodeIDs
            )
        }

        application.get("health") { _ async in
            let indexer = await configuredIndexerConnection(using: connectionSettings)
            let downloader = await connectionSettings.load().downloadClient
            return HealthResponse(
                status: "ok",
                mode: "tracking",
                metadata: "tvmaze",
                indexer: indexer == nil ? "not-configured" : indexer?.name.lowercased() ?? "configured",
                downloader: downloader?.kind.rawValue ?? "not-configured",
                database: "sqlite",
                revision: revision
            )
        }
    }

    private static func metadataAbort(_ error: Error) -> Abort {
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

    private static func verifiedReleasePage(
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

    private static func configuredIndexer(
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

    private static func configuredIndexerConnection(
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

    private static func connectionURL(_ value: String) throws -> URL {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            throw Abort(.badRequest, reason: "Enter a complete http:// or https:// address.")
        }
        return url
    }

    private static func connectionResponse(
        using settings: ConnectionSettingsStore
    ) async -> ConnectionSettingsResponse {
        let saved = await settings.load()
        let indexer = await configuredIndexerConnection(using: settings)
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
            }
        )
    }

    private static func downloadClientAbort(_ error: Error, kind: DownloadClientKind) -> Abort {
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

    private static func submissionAbort(_ error: Error) -> Abort {
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

    private static func indexerAbort(_ error: Error) -> Abort {
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

private struct SeriesSearchResponse: Content {
    let results: [TelevisionSeries]
}

private struct TrackedSeriesListResponse: Content {
    let results: [TrackedSeriesResponse]
}

private struct TrackedSeriesResponse: Content {
    let series: TelevisionSeries
    let addedAt: Date
    let nextAirDate: String?
    let downloadSettings: TelevisionDownloadSettings
}

private struct TrackSeriesRequest: Content {
    let series: TelevisionSeries
}

private struct SetLineupRequest: Content {
    let monitoring: TelevisionEpisodeMonitoring?
    let seasonNumber: Int?
    let episodeID: ProviderReference?
    let episodeIDs: [ProviderReference]?
    let included: Bool?
}

private struct SetTelevisionDownloadSettingsRequest: Content {
    let seasonFolders: Bool
    let preferredResolution: TelevisionResolutionPreference
    let preferredVideoCodec: TelevisionVideoCodecPreference
}

extension TrackedTelevisionSeries: Content {}
extension TelevisionLineup: Content {}
extension TelevisionDownloadSettings: Content {}

private func localDateString(_ date: Date = Date()) -> String {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(
        format: "%04d-%02d-%02d",
        components.year ?? 0,
        components.month ?? 0,
        components.day ?? 0
    )
}

private struct SeasonListResponse: Content {
    let seasons: [TelevisionSeason]
}

private struct ReleaseSearchResponse: Content {
    let offset: Int
    let total: Int
    let results: [ReleaseCandidate]
}

private struct SetIndexerConnectionRequest: Content {
    let name: String
    let endpoint: String
    let apiKey: String?
}

private struct SetDownloadClientConnectionRequest: Content {
    let kind: DownloadClientKind
    let endpoint: String
    let username: String?
    let secret: String?
}

private struct IndexerConnectionResponse: Content {
    let name: String
    let endpoint: String
    let configured: Bool
    let source: String
}

private struct DownloadClientConnectionResponse: Content {
    let kind: DownloadClientKind
    let name: String
    let endpoint: String
    let username: String?
    let configured: Bool
}

private struct ConnectionSettingsResponse: Content {
    let indexer: IndexerConnectionResponse?
    let downloadClient: DownloadClientConnectionResponse?
}

private struct SubmitDownloadRequest: Content {
    let candidateID: ProviderReference
    let seriesID: ProviderReference
    let episodeIDs: [ProviderReference]
}

private struct AssociateDownloadRequest: Content {
    let seriesID: ProviderReference
    let episodeIDs: [ProviderReference]
}

private struct DownloadSubmissionResponse: Content {
    let submission: DownloadSubmission
    let alreadySubmitted: Bool
}

private struct DownloadSubmissionListResponse: Content {
    let results: [DownloadSubmission]
}

extension DownloadSubmission: Content {}

private struct HealthResponse: Content {
    let status: String
    let mode: String
    let metadata: String
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
