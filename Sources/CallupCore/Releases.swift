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
    public let source: String?

    public init(
        videoCodec: String? = nil,
        resolution: String? = nil,
        source: String? = nil
    ) {
        self.videoCodec = videoCodec
        self.resolution = resolution
        self.source = source
    }
}

public struct ReleaseCandidate: Codable, Equatable, Sendable {
    public let id: ProviderReference
    public let title: String
    public let sizeBytes: Int64?
    public let publishedAt: Date?
    public let coverage: [CandidateCoverage]
    public let reportedTraits: ReportedReleaseTraits
    public let reportedMediaIDs: [ProviderReference]

    public init(
        id: ProviderReference,
        title: String,
        sizeBytes: Int64?,
        publishedAt: Date?,
        coverage: [CandidateCoverage] = [],
        reportedTraits: ReportedReleaseTraits = .init(),
        reportedMediaIDs: [ProviderReference] = []
    ) {
        self.id = id
        self.title = title
        self.sizeBytes = sizeBytes
        self.publishedAt = publishedAt
        self.coverage = coverage
        self.reportedTraits = reportedTraits
        self.reportedMediaIDs = reportedMediaIDs
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

public protocol VideoPreferenceSettings: Sendable {
    var preferredResolution: VideoResolutionPreference { get }
    var preferredVideoCodec: VideoCodecPreference { get }
}

public enum ReleasePreferenceRanker {
    public static func sorted<Settings: VideoPreferenceSettings>(
        _ candidates: [ReleaseCandidate],
        settings: Settings
    ) -> [ReleaseCandidate] {
        candidates.enumerated().sorted { left, right in
            let leftScore = score(left.element, settings: settings)
            let rightScore = score(right.element, settings: settings)
            return leftScore == rightScore ? left.offset < right.offset : leftScore > rightScore
        }.map(\.element)
    }

    private static func score<Settings: VideoPreferenceSettings>(
        _ candidate: ReleaseCandidate,
        settings: Settings
    ) -> Int {
        var result = 0
        if settings.preferredResolution != .any,
           candidate.reportedTraits.resolution == settings.preferredResolution.rawValue {
            result += 1
        }
        if settings.preferredVideoCodec != .any,
           candidate.reportedTraits.videoCodec == settings.preferredVideoCodec.rawValue {
            result += 1
        }
        return result
    }
}

public enum ReleaseIdentityFilter {
    public static func matches(
        _ candidate: ReleaseCandidate,
        series: TelevisionSeries,
        requireReportedIdentity: Bool
    ) -> Bool {
        let expected = Dictionary(uniqueKeysWithValues: [
            series.id,
            series.theTVDBID.map { ProviderReference(provider: "thetvdb", value: $0) },
            series.imdbID.map { ProviderReference(provider: "imdb", value: $0) },
        ].compactMap { $0 }.map { ($0.provider.lowercased(), normalized($0)) })

        let reported = Dictionary(
            grouping: candidate.reportedMediaIDs,
            by: { $0.provider.lowercased() }
        )
        let comparable = reported.filter { expected[$0.key] != nil }
        guard !comparable.isEmpty else { return !requireReportedIdentity }

        return comparable.allSatisfy { provider, ids in
            guard let expectedID = expected[provider] else { return false }
            return ids.allSatisfy { normalized($0) == expectedID }
        }
    }

    public static func matches(
        _ candidate: ReleaseCandidate,
        movie: Movie,
        requireReportedIdentity: Bool
    ) -> Bool {
        let expected = Dictionary(uniqueKeysWithValues: [
            movie.id,
            movie.imdbID.map { ProviderReference(provider: "imdb", value: $0) },
        ].compactMap { $0 }.map { ($0.provider.lowercased(), normalized($0)) })

        let reported = Dictionary(
            grouping: candidate.reportedMediaIDs,
            by: { $0.provider.lowercased() }
        )
        let comparable = reported.filter { expected[$0.key] != nil }
        guard !comparable.isEmpty else { return !requireReportedIdentity }

        return comparable.allSatisfy { provider, ids in
            guard let expectedID = expected[provider] else { return false }
            return ids.allSatisfy { normalized($0) == expectedID }
        }
    }

    private static func normalized(_ reference: ProviderReference) -> String {
        let value = reference.value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if reference.provider.caseInsensitiveCompare("imdb") == .orderedSame {
            let numeric = value.hasPrefix("tt") ? value.dropFirst(2) : value[...]
            let unpadded = numeric.drop(while: { $0 == "0" })
            return unpadded.isEmpty ? "0" : String(unpadded)
        }
        return value
    }
}

public protocol TelevisionReleaseIndexer: Sendable {
    func searchTelevision(
        query: String,
        tvmazeID: String?,
        tvdbID: String?,
        imdbID: String?,
        season: Int?,
        episode: Int?
    ) async throws -> ReleaseSearchPage
}

public protocol MovieReleaseIndexer: Sendable {
    func searchMovies(
        query: String,
        imdbID: String?
    ) async throws -> ReleaseSearchPage
}
