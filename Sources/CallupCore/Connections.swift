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

public struct MetadataProviderConnection: Codable, Equatable, Sendable {
    public let provider: String
    public let secret: String

    public init(provider: String, secret: String) {
        self.provider = provider
        self.secret = secret
    }
}

public struct ConnectionSettings: Codable, Equatable, Sendable {
    public var indexer: IndexerConnection?
    public var downloadClient: DownloadClientConnection?
    public var metadataProviders: [MetadataProviderConnection]

    public init(
        indexer: IndexerConnection? = nil,
        downloadClient: DownloadClientConnection? = nil,
        metadataProviders: [MetadataProviderConnection] = []
    ) {
        self.indexer = indexer
        self.downloadClient = downloadClient
        self.metadataProviders = metadataProviders
    }

    private enum CodingKeys: String, CodingKey {
        case indexer
        case downloadClient
        case metadataProviders
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        indexer = try container.decodeIfPresent(IndexerConnection.self, forKey: .indexer)
        downloadClient = try container.decodeIfPresent(
            DownloadClientConnection.self,
            forKey: .downloadClient
        )
        metadataProviders = try container.decodeIfPresent(
            [MetadataProviderConnection].self,
            forKey: .metadataProviders
        ) ?? []
    }
}
