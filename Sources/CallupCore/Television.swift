import Foundation

public struct ProviderReference: Codable, Hashable, Sendable {
    public let provider: String
    public let value: String

    public init(provider: String, value: String) {
        self.provider = provider
        self.value = value
    }
}

public struct TelevisionSeries: Codable, Equatable, Sendable {
    public let id: ProviderReference
    public let title: String
    public let premieredYear: Int?
    public let status: String?
    public let network: String?
    public let imageURL: String?
    public let theTVDBID: String?
    public let imdbID: String?

    public init(
        id: ProviderReference,
        title: String,
        premieredYear: Int?,
        status: String?,
        network: String?,
        imageURL: String?,
        theTVDBID: String? = nil,
        imdbID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.premieredYear = premieredYear
        self.status = status
        self.network = network
        self.imageURL = imageURL
        self.theTVDBID = theTVDBID
        self.imdbID = imdbID
    }
}

public struct TrackedTelevisionSeries: Codable, Equatable, Sendable {
    public let series: TelevisionSeries
    public let addedAt: Date
    public let downloadSettings: TelevisionDownloadSettings

    public init(
        series: TelevisionSeries,
        addedAt: Date,
        downloadSettings: TelevisionDownloadSettings = TelevisionDownloadSettings()
    ) {
        self.series = series
        self.addedAt = addedAt
        self.downloadSettings = downloadSettings
    }
}

public struct TelevisionDownloadSettings: Codable, Equatable, VideoPreferenceSettings, Sendable {
    public var seasonFolders: Bool
    public var preferredResolution: TelevisionResolutionPreference
    public var preferredVideoCodec: TelevisionVideoCodecPreference

    public init(
        seasonFolders: Bool = true,
        preferredResolution: TelevisionResolutionPreference = .p1080,
        preferredVideoCodec: TelevisionVideoCodecPreference = .hevc
    ) {
        self.seasonFolders = seasonFolders
        self.preferredResolution = preferredResolution
        self.preferredVideoCodec = preferredVideoCodec
    }
}

public enum VideoResolutionPreference: String, Codable, CaseIterable, Sendable {
    case any
    case p2160 = "2160p"
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"
}

public enum VideoCodecPreference: String, Codable, CaseIterable, Sendable {
    case any
    case hevc = "HEVC"
    case avc = "AVC"
    case av1 = "AV1"
    case mpeg2 = "MPEG-2"
}

public typealias TelevisionResolutionPreference = VideoResolutionPreference
public typealias TelevisionVideoCodecPreference = VideoCodecPreference

public enum TelevisionEpisodeMonitoring: String, Codable, CaseIterable, Sendable {
    case future
    case all
    case none
}

public struct TelevisionLineup: Codable, Equatable, Sendable {
    public var monitoring: TelevisionEpisodeMonitoring
    public var futureCutoffDate: String?
    public var excludedSeasons: Set<Int>
    public var excludedEpisodes: Set<ProviderReference>
    public var includedEpisodes: Set<ProviderReference>

    public init(
        monitoring: TelevisionEpisodeMonitoring = .all,
        futureCutoffDate: String? = nil,
        excludedSeasons: Set<Int> = [],
        excludedEpisodes: Set<ProviderReference> = [],
        includedEpisodes: Set<ProviderReference> = []
    ) {
        self.monitoring = monitoring
        self.futureCutoffDate = futureCutoffDate
        self.excludedSeasons = excludedSeasons
        self.excludedEpisodes = excludedEpisodes
        self.includedEpisodes = includedEpisodes
    }

    public func includes(_ episode: TelevisionEpisode) -> Bool {
        if includedEpisodes.contains(episode.id) { return true }
        if excludedSeasons.contains(episode.seasonNumber)
            || excludedEpisodes.contains(episode.id) { return false }

        return switch monitoring {
        case .all:
            true
        case .none:
            false
        case .future:
            if let airDate = episode.airDate, let futureCutoffDate {
                airDate >= futureCutoffDate
            } else {
                false
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case monitoring
        case futureCutoffDate
        case excludedSeasons
        case excludedEpisodes
        case includedEpisodes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        monitoring = try container.decodeIfPresent(
            TelevisionEpisodeMonitoring.self,
            forKey: .monitoring
        ) ?? .all
        futureCutoffDate = try container.decodeIfPresent(String.self, forKey: .futureCutoffDate)
        excludedSeasons = try container.decodeIfPresent(
            Set<Int>.self,
            forKey: .excludedSeasons
        ) ?? []
        excludedEpisodes = try container.decodeIfPresent(
            Set<ProviderReference>.self,
            forKey: .excludedEpisodes
        ) ?? []
        includedEpisodes = try container.decodeIfPresent(
            Set<ProviderReference>.self,
            forKey: .includedEpisodes
        ) ?? []
    }
}

public struct TelevisionEpisode: Codable, Equatable, Sendable {
    public let id: ProviderReference
    public let seriesID: ProviderReference
    public let seasonNumber: Int
    public let episodeNumber: Int?
    public let title: String
    public let airDate: String?
    public let runtimeMinutes: Int?

    public init(
        id: ProviderReference,
        seriesID: ProviderReference,
        seasonNumber: Int,
        episodeNumber: Int?,
        title: String,
        airDate: String?,
        runtimeMinutes: Int?
    ) {
        self.id = id
        self.seriesID = seriesID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.title = title
        self.airDate = airDate
        self.runtimeMinutes = runtimeMinutes
    }
}

public struct TelevisionSeason: Codable, Equatable, Sendable {
    public let number: Int
    public let episodes: [TelevisionEpisode]

    public init(number: Int, episodes: [TelevisionEpisode]) {
        self.number = number
        self.episodes = episodes
    }
}

public protocol TelevisionMetadataProvider: Sendable {
    func searchSeries(query: String) async throws -> [TelevisionSeries]
    func series(for seriesID: ProviderReference) async throws -> TelevisionSeries
    func episodes(for seriesID: ProviderReference) async throws -> [TelevisionEpisode]
}

public protocol TelevisionMetadataSupplier: TelevisionMetadataProvider {
    var metadataSupplier: MetadataSupplier { get }
}

public enum TelevisionCatalog {
    public static func seasons(from episodes: [TelevisionEpisode]) -> [TelevisionSeason] {
        Dictionary(grouping: episodes, by: \TelevisionEpisode.seasonNumber)
            .map { number, episodes in
                TelevisionSeason(
                    number: number,
                    episodes: episodes.sorted { left, right in
                        switch (left.episodeNumber, right.episodeNumber) {
                        case let (leftNumber?, rightNumber?):
                            if leftNumber == rightNumber {
                                return left.id.value < right.id.value
                            }
                            return leftNumber < rightNumber
                        case (.some, .none):
                            return true
                        case (.none, .some):
                            return false
                        case (.none, .none):
                            return left.id.value < right.id.value
                        }
                    }
                )
            }
            .sorted { $0.number < $1.number }
    }

    public static func nextAirDate(
        from episodes: [TelevisionEpisode],
        onOrAfter date: String
    ) -> String? {
        episodes
            .compactMap(\.airDate)
            .filter { $0 >= date }
            .min()
    }
}
