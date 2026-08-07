import CallupCore
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
            configure(application, store: store)
            try await application.execute()
        } catch {
            application.logger.report(error: error)
            try await application.asyncShutdown()
            throw error
        }

        try await application.asyncShutdown()
    }

    private static func configure(_ application: Application, store: ApplicationStore) {
        application.http.server.configuration.hostname = "127.0.0.1"
        application.http.server.configuration.port = configuredPort()

        let metadata = CachedTelevisionMetadataProvider(
            upstream: TVMazeClient(),
            store: store
        )
        let indexer = configuredIndexer().map {
            CachedTelevisionReleaseIndexer(upstream: $0, store: store)
        }
        let revision = ProcessInfo.processInfo.environment["CALLUP_REVISION"] ?? "unknown"
        application.lifecycle.use(StoreLifecycle(store: store))

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
            guard let indexer else {
                throw Abort(.serviceUnavailable, reason: "NZBGeek is not configured.")
            }
            guard let query = request.query[String.self, at: "q"] else {
                throw Abort(.badRequest, reason: "Query parameter 'q' is required.")
            }

            do {
                let page = try await indexer.searchTelevision(
                    query: query,
                    tvmazeID: request.query[String.self, at: "tvmazeID"],
                    season: request.query[Int.self, at: "season"],
                    episode: request.query[Int.self, at: "episode"]
                )
                return ReleaseSearchResponse(
                    offset: page.offset,
                    total: page.total,
                    results: page.candidates
                )
            } catch {
                throw indexerAbort(error)
            }
        }

        application.get("health") { _ in
            HealthResponse(
                status: "ok",
                mode: "read-only",
                metadata: "tvmaze",
                indexer: indexer == nil ? "not-configured" : "nzbgeek",
                database: "sqlite",
                revision: revision
            )
        }
    }

    private static func metadataAbort(_ error: Error) -> Abort {
        switch error {
        case TVMazeError.emptyQuery:
            Abort(.badRequest, reason: "Enter a series name.")
        case TVMazeError.invalidIdentifier, TVMazeError.unsupportedProvider:
            Abort(.badRequest, reason: "The series identifier is invalid.")
        case TVMazeError.rateLimited:
            Abort(.serviceUnavailable, reason: "TVmaze is busy. Try again shortly.")
        case let TVMazeError.httpStatus(status):
            Abort(.badGateway, reason: "TVmaze returned HTTP \(status).")
        default:
            Abort(.badGateway, reason: "TVmaze could not be reached.")
        }
    }

    private static func configuredIndexer() -> NewznabClient? {
        let environment = ProcessInfo.processInfo.environment
        guard let rawKey = environment["CALLUP_NZBGEEK_API_KEY"],
              let apiKey = try? NewznabAPIKey(rawKey),
              let endpoint = URL(
                string: environment["CALLUP_NZBGEEK_URL"] ?? "https://api.nzbgeek.info/api"
              ) else {
            return nil
        }
        return NewznabClient(provider: "nzbgeek", endpoint: endpoint, apiKey: apiKey)
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

    private static func indexerAbort(_ error: Error) -> Abort {
        switch error {
        case NewznabRequestError.emptyQuery:
            Abort(.badRequest, reason: "Enter a series name.")
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

private struct SeasonListResponse: Content {
    let seasons: [TelevisionSeason]
}

private struct ReleaseSearchResponse: Content {
    let offset: Int
    let total: Int
    let results: [ReleaseCandidate]
}

private struct HealthResponse: Content {
    let status: String
    let mode: String
    let metadata: String
    let indexer: String
    let database: String
    let revision: String
}

private struct StoreLifecycle: LifecycleHandler {
    let store: ApplicationStore

    func shutdownAsync(_ application: Application) async {
        try? await store.close()
    }
}
