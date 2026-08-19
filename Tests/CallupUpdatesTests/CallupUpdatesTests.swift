@testable import CallupUpdates
import Foundation
import Testing

@Test func versionsFollowSemanticOrdering() {
    #expect(CallupVersion("v0.1.0-dev.23")! < CallupVersion("0.1.0-dev.24")!)
    #expect(CallupVersion("0.1.0-dev.24")! < CallupVersion("0.1.0")!)
    #expect(CallupVersion("0.1.0")! < CallupVersion("0.2.0-dev.1")!)
    #expect(CallupVersion("not-a-version") == nil)
    #expect(CallupVersion("0.1.0-dev/24") == nil)
}

@Test func coordinatorRejectsASecondRequestWhileOneIsPending() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: directory.appending(path: "ready").path, contents: Data())
    defer { try? FileManager.default.removeItem(at: directory) }
    let release = CallupUpdateRelease(
        version: "0.1.0-dev.24",
        name: "v0.1.0-dev.24",
        publishedAt: nil,
        releaseURL: "https://example.com/24"
    )
    let service = CallupUpdateService(
        revision: "v0.1.0-dev.23@abc123",
        provider: StubProvider(release: release),
        directory: directory
    )
    _ = try await service.request(version: release.version)

    await #expect(throws: CallupUpdateError.updateInProgress) {
        try await service.request(version: release.version)
    }
}

@Test func coordinatorRequiresAnInstalledSystemUpdaterMarker() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let release = CallupUpdateRelease(
        version: "0.1.0-dev.24",
        name: "v0.1.0-dev.24",
        publishedAt: nil,
        releaseURL: "https://example.com/24"
    )
    let service = CallupUpdateService(
        revision: "v0.1.0-dev.23@abc123",
        provider: StubProvider(release: release),
        directory: directory
    )

    let status = await service.status()
    #expect(!status.updaterReady)
    await #expect(throws: CallupUpdateError.updaterUnavailable) {
        try await service.request(version: release.version)
    }
}

@Test func releaseDiscoveryRequiresCompletePlatformAssets() throws {
    let data = Data(#"""
    [
      {
        "tag_name": "v0.1.0-dev.25",
        "name": "Newest but incomplete",
        "html_url": "https://example.com/25",
        "published_at": "2026-08-20T00:00:00Z",
        "draft": false,
        "prerelease": false,
        "assets": [{"name": "callup-0.1.0-dev.25-linux-amd64.tar.gz"}]
      },
      {
        "tag_name": "v0.1.0-dev.24",
        "name": "Ready",
        "html_url": "https://example.com/24",
        "published_at": "2026-08-19T00:00:00Z",
        "draft": false,
        "prerelease": false,
        "assets": [
          {"name": "callup-0.1.0-dev.24-linux-amd64.tar.gz"},
          {"name": "callup-0.1.0-dev.24-linux-amd64.tar.gz.sha256"}
        ]
      }
    ]
    """#.utf8)

    let release = try GitHubReleaseDecoder.newestRelease(
        in: data,
        after: CallupVersion("0.1.0-dev.23")!
    )

    #expect(release?.version == "0.1.0-dev.24")
}

@Test func stableInstallationsDoNotReceivePrereleases() throws {
    let data = Data(#"""
    [{
      "tag_name": "v0.2.0-dev.1",
      "name": "Development",
      "html_url": "https://example.com/dev",
      "published_at": null,
      "draft": false,
      "prerelease": false,
      "assets": [
        {"name": "callup-0.2.0-dev.1-linux-amd64.tar.gz"},
        {"name": "callup-0.2.0-dev.1-linux-amd64.tar.gz.sha256"}
      ]
    }]
    """#.utf8)

    let release = try GitHubReleaseDecoder.newestRelease(
        in: data,
        after: CallupVersion("0.1.0")!
    )

    #expect(release == nil)
}

@Test func updateRequestsAreWrittenThroughTheCoordinator() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: directory.appending(path: "ready").path, contents: Data())
    defer { try? FileManager.default.removeItem(at: directory) }
    let release = CallupUpdateRelease(
        version: "0.1.0-dev.24",
        name: "v0.1.0-dev.24",
        publishedAt: nil,
        releaseURL: "https://example.com/24"
    )
    let service = CallupUpdateService(
        revision: "v0.1.0-dev.23@abc123",
        provider: StubProvider(release: release),
        directory: directory
    )

    let status = try await service.request(version: release.version)
    let request = try String(contentsOf: directory.appending(path: "request"), encoding: .utf8)

    #expect(request == "0.1.0-dev.24\n")
    #expect(status.progress?.state == .requested)
    #expect(status.updaterReady)
}

private struct StubProvider: CallupUpdateReleaseProviding {
    let release: CallupUpdateRelease?

    func newestRelease(after currentVersion: CallupVersion) async throws -> CallupUpdateRelease? {
        release
    }
}
