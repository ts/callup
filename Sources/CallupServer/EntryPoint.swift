import CallupCore
import CallupAutomation
import CallupDownloadClients
import CallupNewznab
import CallupPersistence
import CallupTMDB
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
        let movieMetadata = configuredMovieMetadata(store: store)
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
        application.lifecycle.use(StoreLifecycle(store: store))
        application.lifecycle.use(
            DownloadReconciliationLifecycle(worker: reconciliationWorker)
        )

        application.get { _ in
            indexResponse()
        }
        application.get("downloads") { _ in
            indexResponse()
        }
        application.get("settings") { _ in
            indexResponse()
        }

        application.get("api", "search") { request async throws -> MediaSearchResponse in
            guard let rawQuery = request.query[String.self, at: "q"] else {
                throw Abort(.badRequest, reason: "Query parameter 'q' is required.")
            }
            let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else {
                throw Abort(.badRequest, reason: "Enter a title.")
            }

            async let television = searchResult {
                try await metadata.searchSeries(query: query)
            }
            async let movies = searchResult {
                guard let movieMetadata else {
                    throw MovieMetadataConfigurationError.unavailable
                }
                return try await movieMetadata.searchMovies(query: query)
            }
            let (televisionResult, movieResult) = await (television, movies)
            var metadataIssues: [MetadataIssue] = []
            let series: [TelevisionSeries]
            let movieItems: [Movie]

            switch televisionResult {
            case let .success(results):
                series = results
            case let .failure(error):
                series = []
                metadataIssues.append(metadataIssue(source: "TVMaze", error: error))
            }
            switch movieResult {
            case let .success(results):
                movieItems = results
            case let .failure(error):
                movieItems = []
                metadataIssues.append(metadataIssue(source: "TMDB", error: error))
            }

            guard metadataIssues.count < 2 else {
                throw Abort(.badGateway, reason: "Metadata suppliers could not be reached.")
            }
            return MediaSearchResponse(
                results: MediaSearchResult.interleaving(
                    televisionSeries: series,
                    movies: movieItems
                ),
                metadataIssues: metadataIssues
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

        application.get("api", "movies", "tracked") { _ async throws -> TrackedMovieListResponse in
            let settings = configuredLibrarySettings()
            let snapshot = await library.snapshot(for: settings)
            let tracked = try await store.trackedMovies()
            return TrackedMovieListResponse(results: tracked.map {
                TrackedMovieResponse(movie: $0.movie, addedAt: $0.addedAt,
                                     downloadSettings: $0.downloadSettings,
                                     onDisk: snapshot.contains($0.movie))
            })
        }

        application.post("api", "movies", "tracked") { request async throws -> TrackedMovie in
            let input = try request.content.decode(TrackMovieRequest.self)
            let tracked = try await store.trackMovie(input.movie)
            if let movieMetadata {
                Task {
                    guard let movie = try? await movieMetadata.movie(for: input.movie.id) else {
                        return
                    }
                    _ = try? await store.updateTrackedMovieMetadata(movie)
                }
            }
            return tracked
        }

        application.delete("api", "movies", "tracked", ":provider", ":id") {
            request async throws -> HTTPStatus in
            let provider = try request.parameters.require("provider")
            let id = try request.parameters.require("id")
            try await store.untrackMovie(
                id: ProviderReference(provider: provider, value: id)
            )
            return .noContent
        }

        application.put("api", "movies", "tracked", ":provider", ":id", "download-settings") {
            request async throws -> MovieDownloadSettings in
            let movieID = ProviderReference(
                provider: try request.parameters.require("provider"),
                value: try request.parameters.require("id")
            )
            let input = try request.content.decode(SetMovieDownloadSettingsRequest.self)
            do {
                return try await store.setMovieDownloadSettings(
                    movieID: movieID,
                    settings: MovieDownloadSettings(
                        preferredResolution: input.preferredResolution,
                        preferredVideoCodec: input.preferredVideoCodec
                    )
                )
            } catch ApplicationStore.StoreError.mediaNotTracked {
                throw Abort(.notFound, reason: "That movie is not tracked.")
            }
        }

        application.get("api", "movies", "tracked", ":provider", ":id", "releases") {
            request async throws -> ReleaseSearchResponse in
            guard let movieMetadata else {
                throw Abort(.serviceUnavailable, reason: "Movie metadata is not configured.")
            }
            guard let client = await configuredIndexer(using: connectionSettings) else {
                throw Abort(.serviceUnavailable, reason: "No search indexer is connected.")
            }
            let movieID = ProviderReference(
                provider: try request.parameters.require("provider"),
                value: try request.parameters.require("id")
            )
            guard try await store.trackedMovie(id: movieID) != nil else {
                throw Abort(.notFound, reason: "That movie is not tracked.")
            }

            do {
                let movie = try await movieMetadata.movie(for: movieID)
                let tracked = try await store.trackMovie(movie)
                let indexer = CachedMovieReleaseIndexer(upstream: client, store: store)
                let page = try await indexer.searchMovies(
                    query: movie.title,
                    imdbID: movie.imdbID
                )
                let candidates = page.candidates.filter {
                    ReleaseIdentityFilter.matches(
                        $0,
                        movie: movie,
                        requireReportedIdentity: false
                    )
                }
                return ReleaseSearchResponse(
                    offset: page.offset,
                    total: candidates.count,
                    results: ReleasePreferenceRanker.sorted(
                        candidates,
                        settings: tracked.downloadSettings
                    )
                )
            } catch {
                if error is TMDBError || error is MetadataCatalogError {
                    throw movieMetadataAbort(error)
                }
                throw indexerAbort(error)
            }
        }

        application.post("api", "movies", "tracked", ":provider", ":id", "downloads") {
            request async throws -> DownloadSubmissionResponse in
            guard let movieMetadata else {
                throw Abort(.serviceUnavailable, reason: "Movie metadata is not configured.")
            }
            guard let downloadConnection = await connectionSettings.load().downloadClient,
                  downloadConnection.kind == .sabnzbd else {
                throw Abort(.serviceUnavailable, reason: "Connect SABnzbd before sending a release.")
            }
            let input = try request.content.decode(SubmitMovieDownloadRequest.self)
            guard let indexerConnection = await configuredIndexerConnection(using: connectionSettings),
                  input.candidateID.provider == indexerConnection.name.lowercased(),
                  let indexer = await configuredIndexer(using: connectionSettings) else {
                throw Abort(.badRequest, reason: "That release does not belong to the connected indexer.")
            }
            let movieID = ProviderReference(
                provider: try request.parameters.require("provider"),
                value: try request.parameters.require("id")
            )
            guard try await store.trackedMovie(id: movieID) != nil else {
                throw Abort(.conflict, reason: "Add the movie before sending one of its releases.")
            }

            let verifiedCandidate: ReleaseCandidate
            do {
                let movie = try await movieMetadata.movie(for: movieID)
                let page = try await CachedMovieReleaseIndexer(upstream: indexer, store: store)
                    .searchMovies(query: movie.title, imdbID: movie.imdbID)
                guard let candidate = page.candidates.first(where: {
                    $0.id == input.candidateID && ReleaseIdentityFilter.matches(
                        $0,
                        movie: movie,
                        requireReportedIdentity: false
                    )
                }) else {
                    throw Abort(
                        .conflict,
                        reason: "The indexer did not verify that release for this movie. Search again."
                    )
                }
                verifiedCandidate = candidate
            } catch let abort as Abort {
                throw abort
            } catch {
                if error is TMDBError || error is MetadataCatalogError {
                    throw movieMetadataAbort(error)
                }
                throw indexerAbort(error)
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
                    let result = try await sabnzbdClient.submit(
                        nzb: nzb,
                        title: verifiedCandidate.title,
                        category: "movies",
                        connection: downloadConnection
                    )
                    _ = try await store.finishDownloadSubmission(
                        candidateID: input.candidateID,
                        jobID: result.jobID
                    )
                    let associated = try await store.associateDownloadSubmission(
                        candidateID: input.candidateID,
                        acquisitionContext: .movie(movieID)
                    )
                    return DownloadSubmissionResponse(
                        submission: associated,
                        alreadySubmitted: false
                    )
                } catch {
                    if case let SABnzbdClientError.requestFailed(code) = error {
                        request.logger.warning(
                            "SABnzbd movie submission transport failed",
                            metadata: ["url-error-code": "\(code?.rawValue ?? 0)"]
                        )
                    }
                    try? await store.failDownloadSubmission(candidateID: input.candidateID)
                    throw submissionAbort(error)
                }
            }
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
                async let series = metadata.series(for: reference)
                async let episodes = metadata.episodes(for: reference)
                let (resolvedSeries, resolvedEpisodes) = try await (series, episodes)
                let snapshot = await library.snapshot(
                    for: configuredLibrarySettings()
                )
                return SeasonListResponse(
                    seasons: TelevisionCatalog.seasons(from: resolvedEpisodes),
                    onDiskEpisodeIDs: Array(
                        snapshot.episodeIDsOnDisk(for: resolvedSeries, episodes: resolvedEpisodes)
                    )
                )
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
            await connectionResponse(using: connectionSettings)
        }

        application.get("api", "settings", "backup") { request async throws -> Response in
            let includeConnections = request.query[Bool.self, at: "includeConnections"] == true
            let backup = try await store.exportBackup(
                connections: includeConnections ? await connectionSettings.load() : nil
            )
            var headers = HTTPHeaders()
            headers.contentType = .json
            headers.replaceOrAdd(
                name: .contentDisposition,
                value: "attachment; filename=\"callup-backup.json\""
            )
            headers.replaceOrAdd(name: .cacheControl, value: "no-store")
            return try await backup.encodeResponse(status: .ok, headers: headers, for: request)
        }

        application.on(
            .POST,
            "api", "settings", "backup", "restore",
            body: .collect(maxSize: "10mb")
        ) {
            request async throws -> BackupRestoreSummary in
            guard request.query[Bool.self, at: "confirm"] == true else {
                throw Abort(
                    .badRequest,
                    reason: "Confirm that this backup should replace Callup's current data."
                )
            }
            let backup: CallupBackup
            do {
                backup = try request.content.decode(CallupBackup.self)
            } catch {
                throw Abort(.badRequest, reason: "That file is not a valid Callup backup.")
            }
            let previousConnections = await connectionSettings.load()
            if let restoredConnections = backup.connections {
                try await connectionSettings.replace(with: restoredConnections)
            }
            do {
                let summary = try await store.restoreBackup(backup)
                await library.invalidate()
                return summary
            } catch let error as ApplicationStore.StoreError {
                if backup.connections != nil {
                    try? await connectionSettings.replace(with: previousConnections)
                }
                switch error {
                case let .unsupportedBackupVersion(version):
                    throw Abort(
                        .unprocessableEntity,
                        reason: "Backup format version \(version) is not supported by this Callup version."
                    )
                default:
                    throw Abort(.unprocessableEntity, reason: "That Callup backup is invalid.")
                }
            } catch {
                if backup.connections != nil {
                    try? await connectionSettings.replace(with: previousConnections)
                }
                throw error
            }
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

        application.post("api", "library", "refresh") { _ async -> HTTPStatus in
            await library.invalidate()
            _ = await library.snapshot(
                for: configuredLibrarySettings(), force: true
            )
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
            guard try await store.trackedTelevisionSeries(id: input.seriesID) != nil else {
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
                    let result = try await sabnzbdClient.submit(
                        nzb: nzb,
                        title: verifiedCandidate.title,
                        category: "tv",
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
                metadata: ["TVmaze"] + (movieMetadata == nil ? [] : ["TMDB"]),
                indexer: indexer == nil ? "not-configured" : indexer?.name.lowercased() ?? "configured",
                downloader: downloader?.kind.rawValue ?? "not-configured",
                database: "sqlite",
                revision: revision
            )
        }
    }

    private static func indexResponse() -> Response {
        Response(
            status: .ok,
            headers: ["content-type": "text/html; charset=utf-8"],
            body: .init(string: indexHTML)
        )
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

    private static func movieMetadataAbort(_ error: Error) -> Abort {
        switch error {
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

    private static func configuredMovieMetadata(
        store: ApplicationStore
    ) -> MovieMetadataCatalog? {
        guard let token = TMDBCredentialResolver.resolve() else {
            return nil
        }
        return MovieMetadataCatalog(suppliers: [
            CachedMovieMetadataProvider(
                upstream: TMDBClient(token: token),
                store: store
            )
        ])
    }

    private static func searchResult<Value: Sendable>(
        _ operation: @Sendable () async throws -> Value
    ) async -> Result<Value, any Error> {
        do {
            return .success(try await operation())
        } catch {
            return .failure(error)
        }
    }

    private static func metadataIssue(source: String, error: any Error) -> MetadataIssue {
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

    private static func configuredLibrarySettings() -> LibrarySettings {
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

private enum MovieMetadataConfigurationError: Error {
    case unavailable
}

private struct SeriesSearchResponse: Content {
    let results: [TelevisionSeries]
}

private struct MediaSearchResponse: Content {
    let results: [MediaSearchResult]
    let metadataIssues: [MetadataIssue]
}

private struct MetadataIssue: Content {
    let source: String
    let message: String
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

private struct TrackedMovieListResponse: Content {
    let results: [TrackedMovieResponse]
}

private struct TrackedMovieResponse: Content {
    let movie: Movie
    let addedAt: Date
    let downloadSettings: MovieDownloadSettings
    let onDisk: Bool
}

private struct TrackMovieRequest: Content {
    let movie: Movie
}

private struct SetMovieDownloadSettingsRequest: Content {
    let preferredResolution: VideoResolutionPreference
    let preferredVideoCodec: VideoCodecPreference
}

private struct SubmitMovieDownloadRequest: Content {
    let candidateID: ProviderReference
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
extension TrackedMovie: Content {}
extension MovieDownloadSettings: Content {}
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
    let onDiskEpisodeIDs: [ProviderReference]
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
extension CallupBackup: Content {}
extension BackupRestoreSummary: Content {}

private struct HealthResponse: Content {
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
