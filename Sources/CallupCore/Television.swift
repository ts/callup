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

    public init(
        id: ProviderReference,
        title: String,
        premieredYear: Int?,
        status: String?,
        network: String?,
        imageURL: String?
    ) {
        self.id = id
        self.title = title
        self.premieredYear = premieredYear
        self.status = status
        self.network = network
        self.imageURL = imageURL
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
    func episodes(for seriesID: ProviderReference) async throws -> [TelevisionEpisode]
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
}
