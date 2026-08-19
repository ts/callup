import Foundation

public struct CallupBackup: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let exportedAt: Date
    public let television: [TelevisionBackupItem]
    public let movies: [TrackedMovie]
    public let downloads: [DownloadSubmission]
    public let qualityDefaults: QualityDefaults?
    public let qualityOverrides: [QualityOverride]?
    public let connections: ConnectionSettings?

    public init(
        formatVersion: Int = CallupBackup.currentFormatVersion,
        exportedAt: Date = Date(),
        television: [TelevisionBackupItem],
        movies: [TrackedMovie],
        downloads: [DownloadSubmission],
        qualityDefaults: QualityDefaults? = nil,
        qualityOverrides: [QualityOverride]? = nil,
        connections: ConnectionSettings? = nil
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.television = television
        self.movies = movies
        self.downloads = downloads
        self.qualityDefaults = qualityDefaults
        self.qualityOverrides = qualityOverrides
        self.connections = connections
    }
}

public struct TelevisionBackupItem: Codable, Equatable, Sendable {
    public let tracked: TrackedTelevisionSeries
    public let lineup: TelevisionLineup

    public init(tracked: TrackedTelevisionSeries, lineup: TelevisionLineup) {
        self.tracked = tracked
        self.lineup = lineup
    }
}

public struct BackupRestoreSummary: Codable, Equatable, Sendable {
    public let televisionCount: Int
    public let movieCount: Int
    public let downloadCount: Int
    public let restoredConnections: Bool

    public init(
        televisionCount: Int,
        movieCount: Int,
        downloadCount: Int,
        restoredConnections: Bool
    ) {
        self.televisionCount = televisionCount
        self.movieCount = movieCount
        self.downloadCount = downloadCount
        self.restoredConnections = restoredConnections
    }
}
