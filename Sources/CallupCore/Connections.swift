import Foundation

public struct IndexerConnection: Codable, Equatable, Sendable {
    public let name: String
    public let endpoint: URL
    public let apiKey: String

    public init(name: String, endpoint: URL, apiKey: String) {
        self.name = name
        self.endpoint = endpoint
        self.apiKey = apiKey
    }
}

public enum DownloadClientKind: String, Codable, CaseIterable, Sendable {
    case sabnzbd
    case nzbget

    public var displayName: String {
        switch self {
        case .sabnzbd: "SABnzbd"
        case .nzbget: "NZBGet"
        }
    }
}

public struct DownloadClientConnection: Codable, Equatable, Sendable {
    public let kind: DownloadClientKind
    public let endpoint: URL
    public let username: String?
    public let secret: String

    public init(
        kind: DownloadClientKind,
        endpoint: URL,
        username: String? = nil,
        secret: String
    ) {
        self.kind = kind
        self.endpoint = endpoint
        self.username = username
        self.secret = secret
    }
}

public struct ConnectionSettings: Codable, Equatable, Sendable {
    public var indexer: IndexerConnection?
    public var downloadClient: DownloadClientConnection?

    public init(
        indexer: IndexerConnection? = nil,
        downloadClient: DownloadClientConnection? = nil
    ) {
        self.indexer = indexer
        self.downloadClient = downloadClient
    }
}
