import CallupCore
import Foundation

public struct CachedMovieReleaseIndexer: MovieReleaseIndexer {
    private let upstream: any MovieReleaseIndexer
    private let store: ApplicationStore
    private let timeToLive: TimeInterval

    public init(
        upstream: any MovieReleaseIndexer,
        store: ApplicationStore,
        timeToLive: TimeInterval = 5 * 60
    ) {
        self.upstream = upstream
        self.store = store
        self.timeToLive = timeToLive
    }

    public func searchMovies(
        query: String,
        imdbID: String?
    ) async throws -> ReleaseSearchPage {
        let key = [
            query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            imdbID?.lowercased() ?? "-",
        ].joined(separator: "|")

        return try await store.cachedValue(
            namespace: "newznab.movie-search",
            key: key,
            timeToLive: timeToLive
        ) {
            try await upstream.searchMovies(query: query, imdbID: imdbID)
        }
    }
}
