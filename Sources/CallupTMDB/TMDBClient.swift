import CallupCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum TMDBError: Error, Equatable, Sendable {
    case emptyCredential
    case emptyQuery
    case unsupportedProvider(String)
    case invalidIdentifier(String)
    case invalidResponse
    case unauthorized
    case rateLimited
    case httpStatus(Int)
}

public struct TMDBAccessToken: CustomStringConvertible, Sendable {
    fileprivate let value: String

    public init(_ value: String) throws {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw TMDBError.emptyCredential }
        self.value = value
    }

    public var description: String {
        "<redacted>"
    }
}

public actor TMDBClient: MovieMetadataSupplier {
    public static let providerName = "tmdb"

    public nonisolated let metadataSupplier = MetadataSupplier(
        id: providerName,
        displayName: "TMDB",
        supportedMediaKinds: [.movie]
    )

    private let baseURL: URL
    private let token: TMDBAccessToken
    private let session: URLSession

    public init(
        token: TMDBAccessToken,
        baseURL: URL = URL(string: "https://api.themoviedb.org/3")!,
        session: URLSession = .shared
    ) {
        self.token = token
        self.baseURL = baseURL
        self.session = session
    }

    public func searchMovies(query: String) async throws -> [Movie] {
        let request = try TMDBRequestBuilder.searchMovies(
            baseURL: baseURL,
            token: token,
            query: query
        )
        return try TMDBDecoder.decodeSearch(try await fetch(request))
    }

    public func movie(for movieID: ProviderReference) async throws -> Movie {
        try validate(movieID)
        let request = TMDBRequestBuilder.movie(
            baseURL: baseURL,
            token: token,
            identifier: movieID.value
        )
        return try TMDBDecoder.decodeMovie(try await fetch(request))
    }

    private func validate(_ movieID: ProviderReference) throws {
        guard movieID.provider == Self.providerName else {
            throw TMDBError.unsupportedProvider(movieID.provider)
        }
        guard Int(movieID.value) != nil else {
            throw TMDBError.invalidIdentifier(movieID.value)
        }
    }

    private func fetch(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw TMDBError.invalidResponse
        }
        switch response.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw TMDBError.unauthorized
        case 429:
            throw TMDBError.rateLimited
        default:
            throw TMDBError.httpStatus(response.statusCode)
        }
    }
}

enum TMDBRequestBuilder {
    static func searchMovies(
        baseURL: URL,
        token: TMDBAccessToken,
        query: String
    ) throws -> URLRequest {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw TMDBError.emptyQuery }

        var components = URLComponents(
            url: baseURL.appending(path: "search/movie"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false"),
        ]
        return request(url: components.url!, token: token)
    }

    static func movie(
        baseURL: URL,
        token: TMDBAccessToken,
        identifier: String
    ) -> URLRequest {
        request(url: baseURL.appending(path: "movie/\(identifier)"), token: token)
    }

    private static func request(url: URL, token: TMDBAccessToken) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("Bearer \(token.value)", forHTTPHeaderField: "authorization")
        return request
    }
}

enum TMDBDecoder {
    static func decodeSearch(_ data: Data) throws -> [Movie] {
        try JSONDecoder().decode(SearchPage.self, from: data).results.map(movie(from:))
    }

    static func decodeMovie(_ data: Data) throws -> Movie {
        movie(from: try JSONDecoder().decode(MoviePayload.self, from: data))
    }

    private static func movie(from payload: MoviePayload) -> Movie {
        Movie(
            id: ProviderReference(provider: TMDBClient.providerName, value: String(payload.id)),
            title: payload.title,
            releaseYear: payload.releaseDate.flatMap { Int($0.prefix(4)) },
            releaseDate: payload.releaseDate,
            imageURL: payload.posterPath.map { "https://image.tmdb.org/t/p/w342\($0)" },
            imdbID: payload.imdbID
        )
    }

    private struct SearchPage: Decodable {
        let results: [MoviePayload]
    }

    private struct MoviePayload: Decodable {
        let id: Int
        let title: String
        let releaseDate: String?
        let posterPath: String?
        let imdbID: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case title
            case releaseDate = "release_date"
            case posterPath = "poster_path"
            case imdbID = "imdb_id"
        }
    }
}
