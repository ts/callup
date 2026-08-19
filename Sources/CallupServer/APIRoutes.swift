import CallupCore
import CallupAutomation
import CallupDownloadClients
import CallupNewznab
import CallupPersistence
import CallupTMDB
import CallupTVMaze
import Foundation
import Vapor

extension CallupServer {
    static func registerAPIRoutes(
        on application: Application,
        store: ApplicationStore,
        connectionSettings: ConnectionSettingsStore,
        metadata: TelevisionMetadataCatalog,
        movieMetadata: ConfiguredMovieMetadataProvider,
        downloadClientProbe: DownloadClientProbe,
        sabnzbdClient: SABnzbdClient,
        library: LibraryInventory,
        revision: String
    ) {
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
                try await movieMetadata.searchMovies(query: query)
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

        application.get("api", "lineup") { request async throws -> LineupResponse in
            let sort = LineupSort(rawValue: request.query[String.self, at: "sort"] ?? "nextAiring")
                ?? .nextAiring
            let today = localDateString()
            let television = try await store.trackedTelevisionSeries()
            let movies = try await store.trackedMovies()
            let downloads = try await store.downloadSubmissions()
            let librarySnapshot = await library.snapshot(for: configuredLibrarySettings())

            var seriesResults: [TrackedSeriesResponse] = []
            for item in television {
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
                seriesResults.append(TrackedSeriesResponse(
                    series: item.series,
                    addedAt: item.addedAt,
                    nextAirDate: nextAirDate,
                    downloadSettings: item.downloadSettings
                ))
            }
            let movieResults = movies.map {
                let files = librarySnapshot.filesOnDisk(for: $0.movie)
                return TrackedMovieResponse(movie: $0.movie, addedAt: $0.addedAt,
                                            downloadSettings: $0.downloadSettings,
                                            onDisk: !files.isEmpty,
                                            libraryFiles: files)
            }

            var order: [LineupOrderItem] = seriesResults.map {
                LineupOrderItem(kind: .televisionSeries, id: $0.series.id,
                                title: $0.series.title, nextAvailableDate: $0.nextAirDate,
                                lastDownloadedAt: lastDownloadedAt(for: $0.series.id, downloads: downloads))
            }
            order += movieResults.map {
                LineupOrderItem(kind: .movie, id: $0.movie.id, title: $0.movie.title,
                                nextAvailableDate: $0.movie.releaseDate,
                                lastDownloadedAt: lastDownloadedAt(for: $0.movie.id, downloads: downloads))
            }
            order.sort { sort.areInIncreasingOrder($0, $1) }
            return LineupResponse(series: seriesResults, movies: movieResults, order: order)
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
                let files = snapshot.filesOnDisk(for: $0.movie)
                return TrackedMovieResponse(movie: $0.movie, addedAt: $0.addedAt,
                                            downloadSettings: $0.downloadSettings,
                                            onDisk: !files.isEmpty,
                                            libraryFiles: files)
            })
        }

        application.post("api", "movies", "tracked") { request async throws -> TrackedMovie in
            let input = try request.content.decode(TrackMovieRequest.self)
            let tracked = try await store.trackMovie(input.movie)
            Task {
                guard let movie = try? await movieMetadata.movie(for: input.movie.id) else {
                    return
                }
                _ = try? await store.updateTrackedMovieMetadata(movie)
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
                if error is TMDBError || error is MetadataCatalogError
                    || error is MovieMetadataConfigurationError {
                    throw movieMetadataAbort(error)
                }
                throw indexerAbort(error)
            }
        }

        application.post("api", "movies", "tracked", ":provider", ":id", "downloads") {
            request async throws -> DownloadSubmissionResponse in
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
                if error is TMDBError || error is MetadataCatalogError
                    || error is MovieMetadataConfigurationError {
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
                let episodeFiles = snapshot.episodeFilesOnDisk(
                    for: resolvedSeries,
                    episodes: resolvedEpisodes
                )
                return SeasonListResponse(
                    seasons: TelevisionCatalog.seasons(from: resolvedEpisodes),
                    onDiskEpisodeIDs: Array(episodeFiles.keys),
                    onDiskEpisodes: episodeFiles.map {
                        OnDiskEpisodeResponse(episodeID: $0.key, libraryFiles: $0.value)
                    }
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

        application.put("api", "settings", "connections", "metadata", ":provider") {
            request async throws -> ConnectionSettingsResponse in
            let provider = try request.parameters.require("provider").lowercased()
            guard provider == TMDBClient.providerName else {
                throw Abort(.badRequest, reason: "That metadata provider is not supported.")
            }
            let input = try request.content.decode(SetMetadataProviderConnectionRequest.self)
            let saved = await connectionSettings.load().metadataProviders
                .first { $0.provider == provider }
            let supplied = input.secret?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = supplied.flatMap({ $0.isEmpty ? nil : $0 }) ?? saved?.secret,
                  let token = try? TMDBAccessToken(value) else {
                throw Abort(.badRequest, reason: "Enter the TMDB API Read Access Token.")
            }
            do {
                try await TMDBClient(token: token).validateCredential()
            } catch {
                throw movieMetadataAbort(error)
            }
            try await connectionSettings.setMetadataProvider(
                MetadataProviderConnection(provider: provider, secret: value)
            )
            return await connectionResponse(using: connectionSettings)
        }

        application.delete("api", "settings", "connections", "metadata", ":provider") {
            request async throws -> HTTPStatus in
            let provider = try request.parameters.require("provider").lowercased()
            try await connectionSettings.removeMetadataProvider(provider)
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
            let submissions = try await store.downloadSubmissions()
            return DownloadSubmissionListResponse(
                results: submissions,
                groups: await downloadActivityGroups(
                    for: submissions,
                    store: store,
                    metadata: metadata
                )
            )
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
                        episodes: episodes
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
            let episodes: [TelevisionEpisode]
            do {
                let requested = Set(input.episodeIDs)
                episodes = try await metadata.episodes(for: input.seriesID).filter {
                    requested.contains($0.id)
                }
            } catch {
                throw metadataAbort(error)
            }
            guard episodes.count == Set(input.episodeIDs).count else {
                throw Abort(.badRequest, reason: "The download context must use known episodes.")
            }
            return try await store.associateDownloadSubmission(
                candidateID: candidateID,
                seriesID: input.seriesID,
                episodes: episodes
            )
        }

        application.get("health") { _ async in
            let indexer = await configuredIndexerConnection(using: connectionSettings)
            let downloader = await connectionSettings.load().downloadClient
            let tmdbConfigured = await movieMetadata.isConfigured
            return HealthResponse(
                status: "ok",
                mode: "tracking",
                metadata: ["TVmaze"] + (tmdbConfigured ? ["TMDB"] : []),
                indexer: indexer == nil ? "not-configured" : indexer?.name.lowercased() ?? "configured",
                downloader: downloader?.kind.rawValue ?? "not-configured",
                database: "sqlite",
                revision: revision
            )
        }
    }
}

private func downloadActivityGroups(
    for submissions: [DownloadSubmission],
    store: ApplicationStore,
    metadata: TelevisionMetadataCatalog
) async -> [DownloadActivityGroup] {
    var cachedEpisodes: [ProviderReference: [TelevisionEpisode]] = [:]
    var groups: [String: DownloadActivityGroup] = [:]
    var order: [String] = []

    for submission in submissions {
        let group = await downloadActivityGroup(
            for: submission,
            store: store,
            metadata: metadata,
            cachedEpisodes: &cachedEpisodes
        ) ?? DownloadActivityGroup(
            id: "release:\(submission.candidateID.provider):\(submission.candidateID.value)",
            title: "Other downloads",
            detail: nil,
            results: []
        )

        if var existing = groups[group.id] {
            existing = DownloadActivityGroup(
                id: existing.id,
                title: existing.title,
                detail: existing.detail,
                results: existing.results + [submission]
            )
            groups[group.id] = existing
        } else {
            groups[group.id] = DownloadActivityGroup(
                id: group.id,
                title: group.title,
                detail: group.detail,
                results: [submission]
            )
            order.append(group.id)
        }
    }

    return order.compactMap { groups[$0] }
}

private func downloadActivityGroup(
    for submission: DownloadSubmission,
    store: ApplicationStore,
    metadata: TelevisionMetadataCatalog,
    cachedEpisodes: inout [ProviderReference: [TelevisionEpisode]]
) async -> DownloadActivityGroup? {
    guard let context = submission.acquisitionContext else { return nil }
    let episodeTargets = context.targets.filter { $0.media.kind == .televisionEpisode }
    guard !episodeTargets.isEmpty,
          episodeTargets.count == context.targets.count,
          let seriesID = context.televisionSeriesID else {
        return nil
    }

    let season: Int
    if let persistedSeason = context.televisionSeasonNumber {
        season = persistedSeason
    } else {
        let episodes: [TelevisionEpisode]
        if let cached = cachedEpisodes[seriesID] {
            episodes = cached
        } else if let fetched = try? await metadata.episodes(for: seriesID) {
            cachedEpisodes[seriesID] = fetched
            episodes = fetched
        } else {
            return nil
        }
        let seasonNumbers = Set(episodeTargets.compactMap { target in
            episodes.first(where: { $0.id == target.media.id })?.seasonNumber
        })
        guard seasonNumbers.count == 1, let legacySeason = seasonNumbers.first else { return nil }
        season = legacySeason
    }

    guard let series = try? await store.trackedTelevisionSeries(id: seriesID)?.series else {
        return nil
    }

    return DownloadActivityGroup(
        id: "television:\(seriesID.provider):\(seriesID.value):season:\(season)",
        title: series.title,
        detail: "Season \(season)",
        results: []
    )
}
