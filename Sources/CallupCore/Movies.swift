import Foundation

public struct Movie: Codable, Equatable, Sendable {
    public let id: ProviderReference
    public let title: String
    public let releaseYear: Int?
    public let releaseDate: String?
    public let imageURL: String?
    public let imdbID: String?

    public init(
        id: ProviderReference,
        title: String,
        releaseYear: Int?,
        releaseDate: String? = nil,
        imageURL: String?,
        imdbID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.releaseYear = releaseYear
        self.releaseDate = releaseDate
        self.imageURL = imageURL
        self.imdbID = imdbID
    }
}

public protocol MovieMetadataProvider: Sendable {
    func searchMovies(query: String) async throws -> [Movie]
    func movie(for movieID: ProviderReference) async throws -> Movie
}

public protocol MovieMetadataSupplier: MovieMetadataProvider {
    var metadataSupplier: MetadataSupplier { get }
}

public struct MovieDownloadSettings: Codable, Equatable, VideoPreferenceSettings, Sendable {
    public var preferredResolution: VideoResolutionPreference
    public var preferredVideoCodec: VideoCodecPreference

    public init(
        preferredResolution: VideoResolutionPreference = .p1080,
        preferredVideoCodec: VideoCodecPreference = .hevc
    ) {
        self.preferredResolution = preferredResolution
        self.preferredVideoCodec = preferredVideoCodec
    }
}

public struct TrackedMovie: Codable, Equatable, Sendable {
    public let movie: Movie
    public let addedAt: Date
    public let downloadSettings: MovieDownloadSettings

    public init(
        movie: Movie,
        addedAt: Date,
        downloadSettings: MovieDownloadSettings = MovieDownloadSettings()
    ) {
        self.movie = movie
        self.addedAt = addedAt
        self.downloadSettings = downloadSettings
    }
}
