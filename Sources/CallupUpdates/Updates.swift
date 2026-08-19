import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CallupVersion: Comparable, CustomStringConvertible, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [Identifier]

    public enum Identifier: Comparable, Sendable {
        case number(Int)
        case text(String)

        public static func < (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.number(lhs), .number(rhs)): lhs < rhs
            case (.number, .text): true
            case (.text, .number): false
            case let (.text(lhs), .text(rhs)): lhs < rhs
            }
        }
    }

    public init?(_ value: String) {
        let unprefixed = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let version = unprefixed.split(separator: "+", maxSplits: 1)[0]
        let pieces = version.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = pieces[0].split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3,
              let major = Int(core[0]), let minor = Int(core[1]), let patch = Int(core[2]),
              major >= 0, minor >= 0, patch >= 0 else { return nil }

        let prerelease: [Identifier]
        if pieces.count == 2 {
            let identifiers = pieces[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty, identifiers.allSatisfy({ identifier in
                !identifier.isEmpty && identifier.allSatisfy { character in
                    character.isASCII && (character.isLetter || character.isNumber || character == "-")
                }
            }) else { return nil }
            prerelease = identifiers.map { identifier in
                Int(identifier).map(Identifier.number) ?? .text(String(identifier))
            }
        } else {
            prerelease = []
        }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        guard !prerelease.isEmpty else { return core }
        return core + "-" + prerelease.map {
            switch $0 {
            case let .number(value): String(value)
            case let .text(value): value
            }
        }.joined(separator: ".")
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty
        }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            return left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}

public struct CallupUpdateRelease: Codable, Equatable, Sendable {
    public let version: String
    public let name: String
    public let publishedAt: String?
    public let releaseURL: String

    public init(version: String, name: String, publishedAt: String?, releaseURL: String) {
        self.version = version
        self.name = name
        self.publishedAt = publishedAt
        self.releaseURL = releaseURL
    }
}

public struct CallupUpdateProgress: Codable, Equatable, Sendable {
    public enum State: String, Codable, Sendable {
        case requested
        case installing
        case succeeded
        case failed
        case rolledBack
    }

    public let state: State
    public let version: String
    public let message: String
    public let updatedAt: String

    public init(state: State, version: String, message: String, updatedAt: String) {
        self.state = state
        self.version = version
        self.message = message
        self.updatedAt = updatedAt
    }
}

public struct CallupUpdateStatus: Codable, Sendable {
    public let currentVersion: String?
    public let availableRelease: CallupUpdateRelease?
    public let progress: CallupUpdateProgress?
    public let updaterReady: Bool
    public let checkError: String?

    public init(
        currentVersion: String?,
        availableRelease: CallupUpdateRelease?,
        progress: CallupUpdateProgress?,
        updaterReady: Bool,
        checkError: String?
    ) {
        self.currentVersion = currentVersion
        self.availableRelease = availableRelease
        self.progress = progress
        self.updaterReady = updaterReady
        self.checkError = checkError
    }
}

public enum CallupUpdateError: Error, Equatable {
    case currentVersionUnknown
    case updaterUnavailable
    case releaseUnavailable
    case invalidVersion
    case updateInProgress
}

public protocol CallupUpdateReleaseProviding: Sendable {
    func newestRelease(after currentVersion: CallupVersion) async throws -> CallupUpdateRelease?
}

public struct GitHubCallupUpdateClient: CallupUpdateReleaseProviding, Sendable {
    private let repository: String
    private let assetPlatform: String
    private let session: URLSession

    public init(
        repository: String = "ts/callup",
        assetPlatform: String = "linux-amd64",
        session: URLSession = .shared
    ) {
        self.repository = repository
        self.assetPlatform = assetPlatform
        self.session = session
    }

    public func newestRelease(after currentVersion: CallupVersion) async throws -> CallupUpdateRelease? {
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=20")!
        )
        request.setValue("Callup update checker", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try GitHubReleaseDecoder.newestRelease(
            in: data,
            after: currentVersion,
            assetPlatform: assetPlatform
        )
    }
}

enum GitHubReleaseDecoder {
    static func newestRelease(
        in data: Data,
        after currentVersion: CallupVersion,
        assetPlatform: String = "linux-amd64"
    ) throws -> CallupUpdateRelease? {
        let releases = try JSONDecoder().decode([Release].self, from: data)
        let acceptsPrereleases = !currentVersion.prerelease.isEmpty
        return releases.compactMap { release -> (CallupVersion, CallupUpdateRelease)? in
            guard !release.draft,
                  let version = CallupVersion(release.tagName), version > currentVersion,
                  acceptsPrereleases || version.prerelease.isEmpty else { return nil }
            let archive = "callup-\(version)-\(assetPlatform).tar.gz"
            guard release.assets.contains(where: { $0.name == archive }),
                  release.assets.contains(where: { $0.name == "\(archive).sha256" }) else { return nil }
            return (version, CallupUpdateRelease(
                version: version.description,
                name: release.name ?? release.tagName,
                publishedAt: release.publishedAt,
                releaseURL: release.htmlURL
            ))
        }.max(by: { $0.0 < $1.0 })?.1
    }

    private struct Release: Decodable {
        let tagName: String
        let name: String?
        let htmlURL: String
        let publishedAt: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case htmlURL = "html_url"
            case publishedAt = "published_at"
            case draft
            case prerelease
            case assets
        }
    }

    private struct Asset: Decodable { let name: String }
}

public actor CallupUpdateService {
    private let currentVersion: CallupVersion?
    private let provider: any CallupUpdateReleaseProviding
    private let directory: URL
    private var cachedRelease: CallupUpdateRelease?
    private var cacheDate: Date?

    public init(
        revision: String,
        provider: any CallupUpdateReleaseProviding = GitHubCallupUpdateClient(),
        directory: URL = URL(fileURLWithPath: "/var/lib/callup/updates", isDirectory: true)
    ) {
        let version = revision.split(separator: "@", maxSplits: 1).first.map(String.init) ?? revision
        self.currentVersion = CallupVersion(version)
        self.provider = provider
        self.directory = directory
    }

    public func status(forceRefresh: Bool = false) async -> CallupUpdateStatus {
        let progress = readProgress()
        let requestPending = FileManager.default.fileExists(atPath: requestURL.path)
            || FileManager.default.fileExists(atPath: processingURL.path)
        let visibleProgress = requestPending && progress?.state != .installing
            ? CallupUpdateProgress(
                state: .requested,
                version: readRequestedVersion() ?? progress?.version ?? "unknown",
                message: "Waiting for the system updater.",
                updatedAt: progress?.updatedAt ?? ""
            )
            : progress
        guard let currentVersion else {
            return CallupUpdateStatus(
                currentVersion: nil,
                availableRelease: nil,
                progress: visibleProgress,
                updaterReady: updaterReady,
                checkError: "The running build does not report a packaged release version."
            )
        }
        do {
            let release: CallupUpdateRelease?
            if !forceRefresh, let cacheDate, Date().timeIntervalSince(cacheDate) < 900 {
                release = cachedRelease
            } else {
                release = try await provider.newestRelease(after: currentVersion)
                cachedRelease = release
                cacheDate = Date()
            }
            return CallupUpdateStatus(
                currentVersion: currentVersion.description,
                availableRelease: release,
                progress: visibleProgress,
                updaterReady: updaterReady,
                checkError: nil
            )
        } catch {
            return CallupUpdateStatus(
                currentVersion: currentVersion.description,
                availableRelease: cachedRelease,
                progress: visibleProgress,
                updaterReady: updaterReady,
                checkError: "Callup could not check for updates."
            )
        }
    }

    public func request(version requestedVersion: String) async throws -> CallupUpdateStatus {
        guard let currentVersion else { throw CallupUpdateError.currentVersionUnknown }
        guard updaterReady else { throw CallupUpdateError.updaterUnavailable }
        guard !FileManager.default.fileExists(atPath: requestURL.path),
              !FileManager.default.fileExists(atPath: processingURL.path),
              readProgress()?.state != .installing else {
            throw CallupUpdateError.updateInProgress
        }
        guard let requested = CallupVersion(requestedVersion) else { throw CallupUpdateError.invalidVersion }
        let release = try await provider.newestRelease(after: currentVersion)
        guard release?.version == requested.description else { throw CallupUpdateError.releaseUnavailable }
        try Data("\(requested)\n".utf8).write(to: requestURL, options: .atomic)
        cachedRelease = release
        cacheDate = Date()
        return await status()
    }

    private var requestURL: URL { directory.appending(path: "request") }
    private var processingURL: URL { directory.appending(path: "request.processing") }
    private var statusURL: URL { directory.appending(path: "status.json") }
    private var readyURL: URL { directory.appending(path: "ready") }
    private var updaterReady: Bool {
        FileManager.default.fileExists(atPath: readyURL.path)
            && FileManager.default.isWritableFile(atPath: directory.path)
    }

    private func readProgress() -> CallupUpdateProgress? {
        guard let data = try? Data(contentsOf: statusURL) else { return nil }
        return try? JSONDecoder().decode(CallupUpdateProgress.self, from: data)
    }

    private func readRequestedVersion() -> String? {
        let source = FileManager.default.fileExists(atPath: requestURL.path) ? requestURL : processingURL
        guard let value = try? String(contentsOf: source, encoding: .utf8) else { return nil }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
