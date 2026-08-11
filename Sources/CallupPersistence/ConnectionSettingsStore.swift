import CallupCore
import Foundation

public actor ConnectionSettingsStore {
    private let fileURL: URL
    private var settings: ConnectionSettings

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            settings = try JSONDecoder().decode(
                ConnectionSettings.self,
                from: Data(contentsOf: fileURL)
            )
        } else {
            settings = ConnectionSettings()
        }
    }

    public func load() -> ConnectionSettings {
        settings
    }

    public func setIndexer(_ connection: IndexerConnection?) throws {
        settings.indexer = connection
        try persist()
    }

    public func setDownloadClient(_ connection: DownloadClientConnection?) throws {
        settings.downloadClient = connection
        try persist()
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(settings)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
