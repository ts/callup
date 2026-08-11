import CallupCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TVMazeError: Error, Equatable, Sendable {
    case emptyQuery
    case unsupportedProvider(String)
    case invalidIdentifier(String)
    case invalidResponse
    case rateLimited
    case httpStatus(Int)
}

public actor TVMazeClient: TelevisionMetadataSupplier {
    public static let providerName = "tvmaze"

    public nonisolated let metadataSupplier = MetadataSupplier(
        id: providerName,
        displayName: "TVmaze",
        supportedMediaKinds: [.televisionSeries, .televisionEpisode]
    )

    private let baseURL: URL
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: "https://api.tvmaze.com")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    public func searchSeries(query: String) async throws -> [TelevisionSeries] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw TVMazeError.emptyQuery
        }

        var components = URLComponents(
            url: baseURL.appending(path: "search/shows"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "q", value: query)]

        return try TVMazeDecoder.decodeSearch(try await fetch(components.url!))
    }

    public func series(for seriesID: ProviderReference) async throws -> TelevisionSeries {
        try validate(seriesID)
        return try TVMazeDecoder.decodeSeries(
            try await fetch(baseURL.appending(path: "shows/\(seriesID.value)"))
        )
    }

    public func episodes(for seriesID: ProviderReference) async throws -> [TelevisionEpisode] {
        try validate(seriesID)

        let url = baseURL.appending(path: "shows/\(seriesID.value)/episodes")
        return try TVMazeDecoder.decodeEpisodes(try await fetch(url), seriesID: seriesID)
    }

    private func validate(_ seriesID: ProviderReference) throws {
        guard seriesID.provider == Self.providerName else {
            throw TVMazeError.unsupportedProvider(seriesID.provider)
        }
        guard Int(seriesID.value) != nil else {
            throw TVMazeError.invalidIdentifier(seriesID.value)
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let response = response as? HTTPURLResponse else {
            throw TVMazeError.invalidResponse
        }
        if response.statusCode == 429 {
            throw TVMazeError.rateLimited
        }
        guard (200..<300).contains(response.statusCode) else {
            throw TVMazeError.httpStatus(response.statusCode)
        }
        return data
    }
}

enum TVMazeDecoder {
    static func decodeSearch(_ data: Data) throws -> [TelevisionSeries] {
        try JSONDecoder().decode([SearchResult].self, from: data).map { series(from: $0.show) }
    }

    static func decodeSeries(_ data: Data) throws -> TelevisionSeries {
        series(from: try JSONDecoder().decode(Show.self, from: data))
    }

    private static func series(from show: Show) -> TelevisionSeries {
        TelevisionSeries(
            id: ProviderReference(
                provider: TVMazeClient.providerName,
                value: String(show.id)
            ),
            title: show.name,
            premieredYear: show.premiered.flatMap { Int($0.prefix(4)) },
            status: show.status,
            network: show.network?.name ?? show.webChannel?.name,
            imageURL: show.image?.medium,
            theTVDBID: show.externals?.thetvdb.map(String.init),
            imdbID: show.externals?.imdb
        )
    }

    static func decodeEpisodes(
        _ data: Data,
        seriesID: ProviderReference
    ) throws -> [TelevisionEpisode] {
        try JSONDecoder().decode([Episode].self, from: data).map { episode in
            TelevisionEpisode(
                id: ProviderReference(
                    provider: TVMazeClient.providerName,
                    value: String(episode.id)
                ),
                seriesID: seriesID,
                seasonNumber: episode.season,
                episodeNumber: episode.number,
                title: episode.name,
                airDate: episode.airdate,
                runtimeMinutes: episode.runtime
            )
        }
    }

    private struct SearchResult: Decodable {
        let show: Show
    }

    private struct Show: Decodable {
        let id: Int
        let name: String
        let premiered: String?
        let status: String?
        let network: Channel?
        let webChannel: Channel?
        let image: Image?
        let externals: Externals?
    }

    private struct Episode: Decodable {
        let id: Int
        let name: String
        let season: Int
        let number: Int?
        let airdate: String?
        let runtime: Int?
    }

    private struct Channel: Decodable {
        let name: String
    }

    private struct Image: Decodable {
        let medium: String?
    }

    private struct Externals: Decodable {
        let thetvdb: Int?
        let imdb: String?
    }
}
