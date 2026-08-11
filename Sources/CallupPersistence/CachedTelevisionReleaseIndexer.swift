import CallupCore
import Foundation

public struct CachedTelevisionReleaseIndexer: TelevisionReleaseIndexer {
    private let upstream: any TelevisionReleaseIndexer
    private let store: ApplicationStore
    private let timeToLive: TimeInterval

    public init(
        upstream: any TelevisionReleaseIndexer,
        store: ApplicationStore,
        timeToLive: TimeInterval = 5 * 60
    ) {
        self.upstream = upstream
        self.store = store
        self.timeToLive = timeToLive
    }

    public func searchTelevision(
        query: String,
        tvmazeID: String?,
        tvdbID: String?,
        imdbID: String?,
        season: Int?,
        episode: Int?
    ) async throws -> ReleaseSearchPage {
        let key = [
            query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            tvmazeID ?? "-",
            tvdbID ?? "-",
            imdbID ?? "-",
            season.map(String.init) ?? "-",
            episode.map(String.init) ?? "-",
        ].joined(separator: "|")

        return try await store.cachedValue(
            namespace: "newznab.television-search",
            key: key,
            timeToLive: timeToLive,
            schemaVersion: 2
        ) {
            try await upstream.searchTelevision(
                query: query,
                tvmazeID: tvmazeID,
                tvdbID: tvdbID,
                imdbID: imdbID,
                season: season,
                episode: episode
            )
        }
    }
}
