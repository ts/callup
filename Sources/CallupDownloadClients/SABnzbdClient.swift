import CallupCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum SABnzbdClientError: Error, Equatable {
    case wrongClient
    case invalidEndpoint
    case emptyNZB
    case requestFailed(URLError.Code?)
    case httpStatus(Int)
    case rejected
    case invalidResponse
}

public struct DownloadClientSubmissionResult: Equatable, Sendable {
    public let jobID: String

    public init(jobID: String) {
        self.jobID = jobID
    }
}

public actor SABnzbdClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func submit(
        nzb: Data,
        title: String,
        category: String,
        connection: DownloadClientConnection
    ) async throws -> DownloadClientSubmissionResult {
        let request = try Self.submissionRequest(
            nzb: nzb,
            title: title,
            category: category,
            connection: connection
        )
        let (data, response) = try await performSubmissionRequest(request)
        guard let http = response as? HTTPURLResponse else {
            throw SABnzbdClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SABnzbdClientError.httpStatus(http.statusCode)
        }
        return try Self.decodeSubmissionResponse(data)
    }

    public func status(
        jobID: String,
        connection: DownloadClientConnection
    ) async throws -> DownloadSubmissionState? {
        let queueData = try await performStatusRequest(
            Self.statusRequest(mode: "queue", jobID: jobID, connection: connection)
        )
        if let state = Self.decodeStatusResponse(queueData, container: "queue", jobID: jobID) {
            return state
        }
        let historyData = try await performStatusRequest(
            Self.statusRequest(mode: "history", jobID: jobID, connection: connection)
        )
        return Self.decodeStatusResponse(historyData, container: "history", jobID: jobID)
    }

    public static func submissionRequest(
        nzb: Data,
        title: String,
        category: String,
        connection: DownloadClientConnection,
        boundary: String = "CallupBoundary-\(UUID().uuidString)"
    ) throws -> URLRequest {
        guard connection.kind == .sabnzbd else { throw SABnzbdClientError.wrongClient }
        guard !connection.secret.isEmpty else { throw SABnzbdClientError.invalidEndpoint }
        guard !nzb.isEmpty else { throw SABnzbdClientError.emptyNZB }

        let endpoint = connection.endpoint.lastPathComponent.lowercased() == "api"
            ? connection.endpoint
            : connection.endpoint.appending(path: "api")
        guard endpoint.scheme != nil, endpoint.host != nil else {
            throw SABnzbdClientError.invalidEndpoint
        }

        var body = Data()
        appendField(name: "mode", value: "addfile", boundary: boundary, to: &body)
        appendField(name: "apikey", value: connection.secret, boundary: boundary, to: &body)
        appendField(name: "output", value: "json", boundary: boundary, to: &body)
        appendField(name: "nzbname", value: title, boundary: boundary, to: &body)
        appendField(name: "cat", value: category, boundary: boundary, to: &body)
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"nzbfile\"; filename=\"callup.nzb\"\r\n".utf8))
        body.append(Data("Content-Type: application/x-nzb\r\n\r\n".utf8))
        body.append(nzb)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")
        request.httpBody = body
        return request
    }

    public static func decodeSubmissionResponse(_ data: Data) throws -> DownloadClientSubmissionResult {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SABnzbdClientError.invalidResponse
        }
        guard object["status"] as? Bool == true else {
            throw SABnzbdClientError.rejected
        }
        guard let jobID = (object["nzo_ids"] as? [String])?.first, !jobID.isEmpty else {
            throw SABnzbdClientError.invalidResponse
        }
        return DownloadClientSubmissionResult(jobID: jobID)
    }

    static func canSafelyRetrySubmission(after code: URLError.Code) -> Bool {
        switch code {
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .notConnectedToInternet:
            true
        default:
            false
        }
    }

    public static func statusRequest(
        mode: String,
        jobID: String,
        connection: DownloadClientConnection
    ) throws -> URLRequest {
        guard connection.kind == .sabnzbd, !connection.secret.isEmpty else {
            throw SABnzbdClientError.wrongClient
        }
        let endpoint = connection.endpoint.lastPathComponent.lowercased() == "api"
            ? connection.endpoint
            : connection.endpoint.appending(path: "api")
        guard endpoint.scheme != nil, endpoint.host != nil else {
            throw SABnzbdClientError.invalidEndpoint
        }
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "mode", value: mode),
            URLQueryItem(name: "nzo_ids", value: jobID),
            URLQueryItem(name: "start", value: "0"),
            URLQueryItem(name: "limit", value: "1"),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "apikey", value: connection.secret),
        ]
        guard let body = components.percentEncodedQuery?.data(using: .utf8) else {
            throw SABnzbdClientError.invalidEndpoint
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "content-type")
        request.httpBody = body
        return request
    }

    public static func decodeStatusResponse(
        _ data: Data,
        container: String,
        jobID: String
    ) -> DownloadSubmissionState? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let section = object[container] as? [String: Any],
            let slots = section["slots"] as? [[String: Any]],
            let slot = slots.first(where: { $0["nzo_id"] as? String == jobID }),
            let status = (slot["status"] as? String)?.lowercased()
        else { return nil }

        switch status {
        case "completed": return .downloaded
        case "failed", "paused": return .blocked
        case "downloading", "fetching", "propagating", "extracting", "verifying", "repairing":
            return .downloading
        default: return .snatched
        }
    }

    private static func appendField(
        name: String,
        value: String,
        boundary: String,
        to body: inout Data
    ) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        body.append(Data(value.utf8))
        body.append(Data("\r\n".utf8))
    }

    private func performStatusRequest(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            guard let code = (error as? URLError)?.code,
                  Self.canSafelyRetrySubmission(after: code) else {
                throw SABnzbdClientError.requestFailed((error as? URLError)?.code)
            }
            try? await Task.sleep(for: .milliseconds(200))
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw SABnzbdClientError.requestFailed((error as? URLError)?.code)
            }
        }
        guard let http = response as? HTTPURLResponse else {
            throw SABnzbdClientError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw SABnzbdClientError.httpStatus(http.statusCode)
        }
        return data
    }

    private func performSubmissionRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            guard let code = (error as? URLError)?.code,
                  Self.canSafelyRetrySubmission(after: code) else {
                throw SABnzbdClientError.requestFailed((error as? URLError)?.code)
            }

            try? await Task.sleep(for: .milliseconds(200))
            do {
                return try await session.data(for: request)
            } catch {
                throw SABnzbdClientError.requestFailed((error as? URLError)?.code)
            }
        }
    }
}
