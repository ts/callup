import CallupCore
import Foundation

public struct CachedTelevisionMetadataProvider: TelevisionMetadataProvider {
    private enum Namespace {
        static let seriesSearch = "tvmaze.series-search"
        static let series = "tvmaze.series"
        static let episodes = "tvmaze.episodes"
    }

    private let upstream: any TelevisionMetadataProvider
    private let store: ApplicationStore
    private let seriesSearchTTL: TimeInterval
    private let episodesTTL: TimeInterval

    public init(
        upstream: any TelevisionMetadataProvider,
        store: ApplicationStore,
        seriesSearchTTL: TimeInterval = 15 * 60,
        episodesTTL: TimeInterval = 60 * 60
    ) {
        self.upstream = upstream
        self.store = store
        self.seriesSearchTTL = seriesSearchTTL
        self.episodesTTL = episodesTTL
    }

    public func searchSeries(query: String) async throws -> [TelevisionSeries] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return try await upstream.searchSeries(query: query)
        }

        return try await store.cachedValue(
            namespace: Namespace.seriesSearch,
            key: normalized,
            timeToLive: seriesSearchTTL,
            schemaVersion: 2
        ) {
            try await upstream.searchSeries(query: query)
        }
    }

    public func episodes(for seriesID: ProviderReference) async throws -> [TelevisionEpisode] {
        let key = "\(seriesID.provider):\(seriesID.value)"
        return try await store.cachedValue(
            namespace: Namespace.episodes,
            key: key,
            timeToLive: episodesTTL
        ) {
            try await upstream.episodes(for: seriesID)
        }
    }

    public func series(for seriesID: ProviderReference) async throws -> TelevisionSeries {
        let key = "\(seriesID.provider):\(seriesID.value)"
        return try await store.cachedValue(
            namespace: Namespace.series,
            key: key,
            timeToLive: seriesSearchTTL,
            schemaVersion: 2
        ) {
            try await upstream.series(for: seriesID)
        }
    }
}
