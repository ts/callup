import CallupCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum NewznabClientError: Error, Equatable {
    case requestFailed
    case httpStatus(Int)
    case invalidDownload
}

public actor NewznabClient: TelevisionReleaseIndexer, MovieReleaseIndexer {
    private let provider: String
    private let endpoint: URL
    private let apiKey: NewznabAPIKey
    private let session: URLSession

    public init(
        provider: String,
        endpoint: URL,
        apiKey: NewznabAPIKey,
        session: URLSession = .shared
    ) {
        self.provider = provider
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = session
    }

    public func searchTelevision(
        query: String,
        tvmazeID: String?,
        tvdbID: String?,
        imdbID: String?,
        season: Int?,
        episode: Int?
    ) async throws -> ReleaseSearchPage {
        let url = try NewznabRequestBuilder.tvSearchURL(
            endpoint: endpoint,
            apiKey: apiKey,
            search: NewznabTVSearch(
                query: query,
                tvmazeID: tvmazeID,
                tvdbID: tvdbID,
                imdbID: imdbID,
                season: season,
                episode: episode
            )
        )

        return try await search(url)
    }

    public func searchMovies(
        query: String,
        imdbID: String?
    ) async throws -> ReleaseSearchPage {
        let url = try NewznabRequestBuilder.movieSearchURL(
            endpoint: endpoint,
            apiKey: apiKey,
            search: NewznabMovieSearch(query: query, imdbID: imdbID)
        )
        return try await search(url)
    }

    public func download(identifier: String) async throws -> Data {
        let url = try NewznabRequestBuilder.downloadURL(
            endpoint: endpoint,
            apiKey: apiKey,
            identifier: identifier
        )
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            // The underlying error can include the credential-bearing request URL.
            throw NewznabClientError.requestFailed
        }
        guard let http = response as? HTTPURLResponse else {
            throw NewznabClientError.requestFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NewznabClientError.httpStatus(http.statusCode)
        }
        guard !data.isEmpty, data.count <= 50 * 1_024 * 1_024 else {
            throw NewznabClientError.invalidDownload
        }
        return data
    }

    private func search(_ url: URL) async throws -> ReleaseSearchPage {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw NewznabClientError.requestFailed
        }
        guard let http = response as? HTTPURLResponse else {
            throw NewznabClientError.requestFailed
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NewznabClientError.httpStatus(http.statusCode)
        }
        return try NewznabResponseDecoder.decode(data, provider: provider)
    }
}
