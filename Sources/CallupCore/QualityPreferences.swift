import Foundation

public struct VideoQualityPreference: Codable, Equatable, Sendable, VideoPreferenceSettings {
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

public struct QualityDefaults: Codable, Equatable, Sendable {
    public var television: VideoQualityPreference
    public var movies: VideoQualityPreference

    public init(
        television: VideoQualityPreference = .init(),
        movies: VideoQualityPreference = .init()
    ) {
        self.television = television
        self.movies = movies
    }

    public func preference(for kind: MediaKind) -> VideoQualityPreference? {
        switch kind {
        case .televisionSeries, .televisionSeason, .televisionEpisode: television
        case .movie: movies
        case .movieCollection: nil
        }
    }
}

public struct AcquisitionPreferenceSnapshot: Codable, Equatable, Sendable {
    public let target: MediaReference
    public let preference: VideoQualityPreference
    public let source: MediaReference?

    public init(target: MediaReference, preference: VideoQualityPreference, source: MediaReference?) {
        self.target = target
        self.preference = preference
        self.source = source
    }
}

public struct QualityOverride: Codable, Equatable, Sendable {
    public let media: MediaReference
    public let preference: VideoQualityPreference

    public init(media: MediaReference, preference: VideoQualityPreference) {
        self.media = media
        self.preference = preference
    }
}
