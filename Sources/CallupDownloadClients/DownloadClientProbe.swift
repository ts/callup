import CallupCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum DownloadClientProbeError: Error, Equatable {
    case invalidEndpoint
    case requestFailed
    case httpStatus(Int)
    case rejected(String)
    case invalidResponse
}

public struct DownloadClientProbeResult: Equatable, Sendable {
    public let version: String?

    public init(version: String?) {
        self.version = version
    }
}

public actor DownloadClientProbe {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func test(_ connection: DownloadClientConnection) async throws -> DownloadClientProbeResult {
        switch connection.kind {
        case .sabnzbd:
            try await testSABnzbd(connection)
        case .nzbget:
            try await testNZBGet(connection)
        }
    }

    public static func sabnzbdRequest(for connection: DownloadClientConnection) throws -> URLRequest {
        guard connection.kind == .sabnzbd,
              var components = URLComponents(url: apiURL(connection.endpoint, component: "api"), resolvingAgainstBaseURL: false),
              !connection.secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DownloadClientProbeError.invalidEndpoint
        }
        components.queryItems = [
            URLQueryItem(name: "mode", value: "queue"),
            URLQueryItem(name: "start", value: "0"),
            URLQueryItem(name: "limit", value: "0"),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "apikey", value: connection.secret),
        ]
        guard let url = components.url else { throw DownloadClientProbeError.invalidEndpoint }
        return URLRequest(url: url)
    }

    public static func nzbgetRequest(for connection: DownloadClientConnection) throws -> URLRequest {
        guard connection.kind == .nzbget,
              let username = connection.username?.trimmingCharacters(in: .whitespacesAndNewlines),
              !username.isEmpty,
              !connection.secret.isEmpty else {
            throw DownloadClientProbeError.invalidEndpoint
        }
        var request = URLRequest(url: apiURL(connection.endpoint, component: "jsonrpc"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let credentials = Data("\(username):\(connection.secret)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "authorization")
        request.httpBody = Data(#"{"method":"version","params":[],"id":1}"#.utf8)
        return request
    }

    private func testSABnzbd(_ connection: DownloadClientConnection) async throws -> DownloadClientProbeResult {
        let request = try Self.sabnzbdRequest(for: connection)
        let data = try await perform(request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DownloadClientProbeError.invalidResponse
        }
        if let error = object["error"] as? String, !error.isEmpty {
            throw DownloadClientProbeError.rejected(error)
        }
        guard object["queue"] != nil else { throw DownloadClientProbeError.invalidResponse }
        let queue = object["queue"] as? [String: Any]
        return DownloadClientProbeResult(version: queue?["version"] as? String)
    }

    private func testNZBGet(_ connection: DownloadClientConnection) async throws -> DownloadClientProbeResult {
        let request = try Self.nzbgetRequest(for: connection)
        let data = try await perform(request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DownloadClientProbeError.invalidResponse
        }
        if let error = object["error"], !(error is NSNull) {
            throw DownloadClientProbeError.rejected("NZBGet rejected the connection.")
        }
        guard let version = object["result"] as? String, !version.isEmpty else {
            throw DownloadClientProbeError.invalidResponse
        }
        return DownloadClientProbeResult(version: version)
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DownloadClientProbeError.requestFailed
        }
        guard let http = response as? HTTPURLResponse else {
            throw DownloadClientProbeError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DownloadClientProbeError.httpStatus(http.statusCode)
        }
        return data
    }

    private static func apiURL(_ endpoint: URL, component: String) -> URL {
        if endpoint.lastPathComponent.lowercased() == component.lowercased() {
            return endpoint
        }
        return endpoint.appending(path: component)
    }
}
