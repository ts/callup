import Foundation

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
