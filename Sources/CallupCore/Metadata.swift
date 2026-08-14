public struct MetadataSupplier: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let supportedMediaKinds: Set<MediaKind>

    public init(
        id: String,
        displayName: String,
        supportedMediaKinds: Set<MediaKind>
    ) {
        self.id = id
        self.displayName = displayName
        self.supportedMediaKinds = supportedMediaKinds
    }
}

public enum MetadataCatalogError: Error, Equatable {
    case unsupportedReference(ProviderReference)
}

public enum MediaSearchResult: Codable, Equatable, Sendable {
    case televisionSeries(TelevisionSeries)
    case movie(Movie)

    public var kind: MediaKind {
        switch self {
        case .televisionSeries:
            .televisionSeries
        case .movie:
            .movie
        }
    }

    public static func interleaving(
        televisionSeries: [TelevisionSeries],
        movies: [Movie]
    ) -> [MediaSearchResult] {
        let count = max(televisionSeries.count, movies.count)
        return (0..<count).flatMap { index in
            var results: [MediaSearchResult] = []
            if televisionSeries.indices.contains(index) {
                results.append(.televisionSeries(televisionSeries[index]))
            }
            if movies.indices.contains(index) {
                results.append(.movie(movies[index]))
            }
            return results
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case media
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(MediaKind.self, forKey: .kind) {
        case .televisionSeries:
            self = .televisionSeries(
                try container.decode(TelevisionSeries.self, forKey: .media)
            )
        case .movie:
            self = .movie(try container.decode(Movie.self, forKey: .media))
        case let kind:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unsupported search result kind: \(kind.rawValue)"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case let .televisionSeries(series):
            try container.encode(series, forKey: .media)
        case let .movie(movie):
            try container.encode(movie, forKey: .media)
        }
    }
}
