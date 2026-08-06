import Foundation

public struct CandidateCoverage: Codable, Equatable, Sendable {
    public enum Scope: String, Codable, Sendable {
        case televisionEpisode
        case televisionSeason
    }

    public let scope: Scope
    public let seasonNumber: Int
    public let episodeNumbers: [Int]

    public init(scope: Scope, seasonNumber: Int, episodeNumbers: [Int] = []) {
        self.scope = scope
        self.seasonNumber = seasonNumber
        self.episodeNumbers = episodeNumbers
    }
}

public struct ReportedReleaseTraits: Codable, Equatable, Sendable {
    public let videoCodec: String?
    public let resolution: String?

    public init(videoCodec: String? = nil, resolution: String? = nil) {
        self.videoCodec = videoCodec
        self.resolution = resolution
    }
}

public struct ReleaseCandidate: Codable, Equatable, Sendable {
    public let id: ProviderReference
    public let title: String
    public let sizeBytes: Int64?
    public let publishedAt: Date?
    public let coverage: [CandidateCoverage]
    public let reportedTraits: ReportedReleaseTraits

    public init(
        id: ProviderReference,
        title: String,
        sizeBytes: Int64?,
        publishedAt: Date?,
        coverage: [CandidateCoverage] = [],
        reportedTraits: ReportedReleaseTraits = .init()
    ) {
        self.id = id
        self.title = title
        self.sizeBytes = sizeBytes
        self.publishedAt = publishedAt
        self.coverage = coverage
        self.reportedTraits = reportedTraits
    }
}

public struct ReleaseSearchPage: Codable, Equatable, Sendable {
    public let offset: Int
    public let total: Int
    public let candidates: [ReleaseCandidate]

    public init(offset: Int, total: Int, candidates: [ReleaseCandidate]) {
        self.offset = offset
        self.total = total
        self.candidates = candidates
    }
}

public protocol TelevisionReleaseIndexer: Sendable {
    func searchTelevision(
        query: String,
        tvmazeID: String?,
        season: Int?,
        episode: Int?
    ) async throws -> ReleaseSearchPage
}
