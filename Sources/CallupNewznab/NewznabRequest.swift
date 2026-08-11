import Foundation

public struct NewznabAPIKey: Sendable, CustomStringConvertible {
    fileprivate let value: String

    public init(_ value: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NewznabRequestError.emptyAPIKey
        }
        self.value = value
    }

    public var description: String { "<redacted>" }
}

public struct NewznabTVSearch: Equatable, Sendable {
    public let query: String
    public let tvmazeID: String?
    public let tvdbID: String?
    public let imdbID: String?
    public let season: Int?
    public let episode: Int?
    public let categories: [Int]
    public let limit: Int
    public let offset: Int

    public init(
        query: String,
        tvmazeID: String? = nil,
        tvdbID: String? = nil,
        imdbID: String? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        categories: [Int] = [],
        limit: Int = 100,
        offset: Int = 0
    ) {
        self.query = query
        self.tvmazeID = tvmazeID
        self.tvdbID = tvdbID
        self.imdbID = imdbID
        self.season = season
        self.episode = episode
        self.categories = categories
        self.limit = limit
        self.offset = offset
    }
}

public enum NewznabRequestError: Error, Equatable {
    case emptyAPIKey
    case invalidEndpoint
    case invalidIdentifier
    case emptyQuery
    case invalidLimit
    case invalidOffset
}

public enum NewznabRequestBuilder {
    public static func downloadURL(
        endpoint: URL,
        apiKey: NewznabAPIKey,
        identifier: String
    ) throws -> URL {
        guard !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NewznabRequestError.invalidIdentifier
        }
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.scheme != nil,
              components.host != nil else {
            throw NewznabRequestError.invalidEndpoint
        }
        components.queryItems = [
            URLQueryItem(name: "t", value: "get"),
            URLQueryItem(name: "id", value: identifier),
            URLQueryItem(name: "apikey", value: apiKey.value),
        ]
        guard let url = components.url else { throw NewznabRequestError.invalidEndpoint }
        return url
    }

    public static func tvSearchURL(
        endpoint: URL,
        apiKey: NewznabAPIKey,
        search: NewznabTVSearch
    ) throws -> URL {
        guard !search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NewznabRequestError.emptyQuery
        }
        guard (1...100).contains(search.limit) else {
            throw NewznabRequestError.invalidLimit
        }
        guard search.offset >= 0 else {
            throw NewznabRequestError.invalidOffset
        }
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false),
              components.scheme != nil,
              components.host != nil else {
            throw NewznabRequestError.invalidEndpoint
        }

        var items = [
            URLQueryItem(name: "t", value: "tvsearch"),
            URLQueryItem(name: "apikey", value: apiKey.value),
            URLQueryItem(name: "q", value: search.query),
            URLQueryItem(name: "extended", value: "1"),
            URLQueryItem(name: "o", value: "xml"),
            URLQueryItem(name: "limit", value: String(search.limit)),
            URLQueryItem(name: "offset", value: String(search.offset)),
        ]

        if let tvmazeID = search.tvmazeID {
            items.append(URLQueryItem(name: "tvmazeid", value: tvmazeID))
        }
        if let tvdbID = search.tvdbID {
            items.append(URLQueryItem(name: "tvdbid", value: tvdbID))
        }
        if let imdbID = search.imdbID {
            items.append(URLQueryItem(name: "imdbid", value: imdbID))
        }
        if let season = search.season {
            items.append(URLQueryItem(name: "season", value: String(season)))
        }
        if let episode = search.episode {
            items.append(URLQueryItem(name: "ep", value: String(episode)))
        }
        if !search.categories.isEmpty {
            items.append(URLQueryItem(name: "cat", value: search.categories.map(String.init).joined(separator: ",")))
        }

        components.queryItems = items
        guard let url = components.url else {
            throw NewznabRequestError.invalidEndpoint
        }
        return url
    }

    public static func redactedDescription(of url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return "<invalid Newznab request>"
        }
        components.queryItems = components.queryItems?.map { item in
            item.name.lowercased() == "apikey"
                ? URLQueryItem(name: item.name, value: "<redacted>")
                : item
        }
        return components.string ?? "<invalid Newznab request>"
    }
}
