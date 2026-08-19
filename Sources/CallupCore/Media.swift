import Foundation

public enum MediaKind: String, Codable, CaseIterable, Hashable, Sendable {
    case televisionSeries
    case televisionSeason
    case televisionEpisode
    case movieCollection
    case movie
}

public struct MediaReference: Codable, Equatable, Hashable, Sendable {
    public let kind: MediaKind
    public let id: ProviderReference
    /// A provider's season is identified by its series plus this ordinal.
    /// Other media kinds do not use an ordinal.
    public let ordinal: Int?

    public init(kind: MediaKind, id: ProviderReference, ordinal: Int? = nil) {
        self.kind = kind
        self.id = id
        self.ordinal = ordinal
    }

    public static func televisionSeason(
        seriesID: ProviderReference,
        number: Int
    ) -> MediaReference {
        MediaReference(kind: .televisionSeason, id: seriesID, ordinal: number)
    }
}

public struct AcquisitionTarget: Codable, Equatable, Hashable, Sendable {
    public let media: MediaReference
    public let ancestors: [MediaReference]

    public init(media: MediaReference, ancestors: [MediaReference] = []) {
        self.media = media
        self.ancestors = ancestors
    }
}

public struct AcquisitionContext: Codable, Equatable, Sendable {
    public let targets: [AcquisitionTarget]

    public init(targets: [AcquisitionTarget]) {
        self.targets = targets
    }

    public static func television(
        seriesID: ProviderReference,
        episodeIDs: [ProviderReference]
    ) -> AcquisitionContext {
        let series = MediaReference(kind: .televisionSeries, id: seriesID)
        return AcquisitionContext(targets: episodeIDs.map {
            AcquisitionTarget(
                media: MediaReference(kind: .televisionEpisode, id: $0),
                ancestors: [series]
            )
        })
    }

    public static func television(
        seriesID: ProviderReference,
        episodes: [TelevisionEpisode]
    ) -> AcquisitionContext {
        let series = MediaReference(kind: .televisionSeries, id: seriesID)
        return AcquisitionContext(targets: episodes.map { episode in
            AcquisitionTarget(
                media: MediaReference(kind: .televisionEpisode, id: episode.id),
                ancestors: [
                    MediaReference.televisionSeason(
                        seriesID: seriesID,
                        number: episode.seasonNumber
                    ),
                    series,
                ]
            )
        })
    }

    public static func movie(
        _ movieID: ProviderReference,
        collectionIDs: [ProviderReference] = []
    ) -> AcquisitionContext {
        AcquisitionContext(targets: [
            AcquisitionTarget(
                media: MediaReference(kind: .movie, id: movieID),
                ancestors: collectionIDs.map { MediaReference(kind: .movieCollection, id: $0) }
            )
        ])
    }

    public var televisionSeriesID: ProviderReference? {
        let series = targets.compactMap { target in
            target.ancestors.first { $0.kind == .televisionSeries }?.id
        }
        guard let first = series.first, series.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    public var televisionEpisodeIDs: [ProviderReference] {
        targets.compactMap { target in
            target.media.kind == .televisionEpisode ? target.media.id : nil
        }
    }

    public var televisionSeasonNumber: Int? {
        let seasons = targets.compactMap { target in
            target.ancestors.first { $0.kind == .televisionSeason }?.ordinal
        }
        guard let first = seasons.first, seasons.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
}
