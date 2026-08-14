import CallupCore
import Foundation

public struct CachedMovieMetadataProvider: MovieMetadataSupplier {
    private let upstream: any MovieMetadataSupplier
    private let store: ApplicationStore
    private let searchTTL: TimeInterval
    private let movieTTL: TimeInterval

    public init(
        upstream: any MovieMetadataSupplier,
        store: ApplicationStore,
        searchTTL: TimeInterval = 15 * 60,
        movieTTL: TimeInterval = 24 * 60 * 60
    ) {
        self.upstream = upstream
        self.store = store
        self.searchTTL = searchTTL
        self.movieTTL = movieTTL
    }

    public var metadataSupplier: MetadataSupplier {
        upstream.metadataSupplier
    }

    public func searchMovies(query: String) async throws -> [Movie] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return try await upstream.searchMovies(query: query)
        }

        return try await store.cachedValue(
            namespace: namespace("movie.search"),
            key: normalized,
            timeToLive: searchTTL
        ) {
            try await upstream.searchMovies(query: query)
        }
    }

    public func movie(for movieID: ProviderReference) async throws -> Movie {
        let key = "\(movieID.provider):\(movieID.value)"
        return try await store.cachedValue(
            namespace: namespace("movie.details"),
            key: key,
            timeToLive: movieTTL
        ) {
            try await upstream.movie(for: movieID)
        }
    }

    private func namespace(_ value: String) -> String {
        "metadata.\(metadataSupplier.id).\(value)"
    }
}
