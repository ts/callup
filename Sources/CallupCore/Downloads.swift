import Foundation

public struct TelevisionDownloadDestination: Equatable, Sendable {
    public let categoryName: String
    public let relativeDirectory: String

    public init(
        series: TelevisionSeries,
        seasonNumber: Int,
        settings: TelevisionDownloadSettings
    ) {
        let seriesFolder = Self.folderComponent(series.title)
        let categoryIdentity = Self.categoryComponent(
            "\(series.id.provider)-\(series.id.value)"
        )
        if settings.seasonFolders {
            let seasonNumber = max(0, seasonNumber)
            let categorySeason = String(format: "%02d", seasonNumber)
            categoryName = "callup-\(categoryIdentity)-s\(categorySeason)"
            relativeDirectory = "\(seriesFolder)/Season \(seasonNumber)/*"
        } else {
            categoryName = "callup-\(categoryIdentity)"
            relativeDirectory = "\(seriesFolder)/*"
        }
    }

    private static func folderComponent(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.controlCharacters)
        let sanitized = value.unicodeScalars.map { scalar in
            forbidden.contains(scalar) ? "-" : String(scalar)
        }.joined()
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return trimmed.isEmpty ? "Untitled Show" : trimmed
    }

    private static func categoryComponent(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" {
                return String(scalar).lowercased()
            }
            return "_\(String(scalar.value, radix: 16))_"
        }.joined()
    }
}

public enum DownloadSubmissionState: String, Codable, Sendable {
    case sending
    case snatched
    case downloading
    case downloaded
    case blocked
}

public struct DownloadSubmission: Codable, Equatable, Sendable {
    public let candidateID: ProviderReference
    public let acquisitionContext: AcquisitionContext?
    public let title: String
    public let client: DownloadClientKind
    public let state: DownloadSubmissionState
    public let clientJobID: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        candidateID: ProviderReference,
        acquisitionContext: AcquisitionContext? = nil,
        title: String,
        client: DownloadClientKind,
        state: DownloadSubmissionState,
        clientJobID: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.candidateID = candidateID
        self.acquisitionContext = acquisitionContext
        self.title = title
        self.client = client
        self.state = state
        self.clientJobID = clientJobID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
