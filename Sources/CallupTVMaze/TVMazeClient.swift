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

public actor TVMazeClient: TelevisionMetadataProvider {
    public static let providerName = "tvmaze"

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

    public func episodes(for seriesID: ProviderReference) async throws -> [TelevisionEpisode] {
        guard seriesID.provider == Self.providerName else {
            throw TVMazeError.unsupportedProvider(seriesID.provider)
        }
        guard Int(seriesID.value) != nil else {
            throw TVMazeError.invalidIdentifier(seriesID.value)
        }

        let url = baseURL.appending(path: "shows/\(seriesID.value)/episodes")
        return try TVMazeDecoder.decodeEpisodes(try await fetch(url), seriesID: seriesID)
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
        try JSONDecoder().decode([SearchResult].self, from: data).map { result in
            let show = result.show
            return TelevisionSeries(
                id: ProviderReference(
                    provider: TVMazeClient.providerName,
                    value: String(show.id)
                ),
                title: show.name,
                premieredYear: show.premiered.flatMap { Int($0.prefix(4)) },
                status: show.status,
                network: show.network?.name ?? show.webChannel?.name,
                imageURL: show.image?.medium
            )
        }
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
}
