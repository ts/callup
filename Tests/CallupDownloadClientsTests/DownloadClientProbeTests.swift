import CallupCore
import Foundation
import Testing
@testable import CallupDownloadClients

@Test func sabnzbdProbeBuildsQueueRequestWithoutLeakingThroughDescription() throws {
    let connection = DownloadClientConnection(
        kind: .sabnzbd,
        endpoint: try #require(URL(string: "http://sab.example:8080")),
        secret: "fixture-secret"
    )

    let request = try DownloadClientProbe.sabnzbdRequest(for: connection)
    let requestURL = try #require(request.url)
    let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
    let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

    #expect(components.path == "/api")
    #expect(query["mode"] == "queue")
    #expect(query["apikey"] == "fixture-secret")
}

@Test func nzbgetProbeUsesJSONRPCAndBasicAuthentication() throws {
    let connection = DownloadClientConnection(
        kind: .nzbget,
        endpoint: try #require(URL(string: "https://nzbget.example:6789")),
        username: "callup",
        secret: "fixture-password"
    )

    let request = try DownloadClientProbe.nzbgetRequest(for: connection)

    #expect(request.url?.path == "/jsonrpc")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "authorization") == "Basic Y2FsbHVwOmZpeHR1cmUtcGFzc3dvcmQ=")
    #expect(String(data: try #require(request.httpBody), encoding: .utf8)?.contains("\"version\"") == true)
}

@Test func sabnzbdSubmissionUploadsTheNZBWithoutPuttingSecretsInTheURL() throws {
    let connection = DownloadClientConnection(
        kind: .sabnzbd,
        endpoint: try #require(URL(string: "http://sab.example:8080")),
        secret: "fixture-secret"
    )
    let request = try SABnzbdClient.submissionRequest(
        nzb: Data("<nzb>fixture</nzb>".utf8),
        title: "A Great Show S01E01",
        category: "tv",
        connection: connection,
        boundary: "fixture-boundary"
    )
    let body = String(decoding: try #require(request.httpBody), as: UTF8.self)

    #expect(request.url?.absoluteString == "http://sab.example:8080/api")
    #expect(!request.url!.absoluteString.contains("fixture-secret"))
    #expect(body.contains("name=\"mode\"\r\n\r\naddfile"))
    #expect(body.contains("name=\"cat\"\r\n\r\ntv"))
    #expect(body.contains("name=\"nzbfile\"; filename=\"callup.nzb\""))
    #expect(body.contains("<nzb>fixture</nzb>"))
}

@Test func sabnzbdSubmissionRequiresAConfirmedJobIdentifier() throws {
    let result = try SABnzbdClient.decodeSubmissionResponse(
        Data(#"{"status":true,"nzo_ids":["SABnzbd_nzo_fixture"]}"#.utf8)
    )
    #expect(result.jobID == "SABnzbd_nzo_fixture")
    #expect(throws: SABnzbdClientError.invalidResponse) {
        try SABnzbdClient.decodeSubmissionResponse(Data(#"{"status":true}"#.utf8))
    }
}

@Test func sabnzbdCategoryRequestKeepsCredentialOutOfURLAndSetsRelativeDirectory() throws {
    let connection = DownloadClientConnection(
        kind: .sabnzbd,
        endpoint: try #require(URL(string: "http://sab.example:8080")),
        secret: "fixture-secret"
    )
    let request = try SABnzbdClient.categoryRequest(
        SABnzbdCategory(
            name: "callup-tvmaze-42-s01",
            directory: "Some Show/Season 1/*"
        ),
        connection: connection
    )
    let body = String(decoding: try #require(request.httpBody), as: UTF8.self)

    #expect(request.url?.absoluteString == "http://sab.example:8080/api")
    #expect(!request.url!.absoluteString.contains("fixture-secret"))
    #expect(body.contains("mode=set_config"))
    #expect(body.contains("section=categories"))
    #expect(body.contains("name=callup-tvmaze-42-s01"))
    #expect(body.contains("dir=Some%20Show/Season%201/*"))
    #expect(body.contains("apikey=fixture-secret"))
}

@Test func sabnzbdCategoryResponseUsesTheReturnedConfigObject() {
    let accepted = Data(#"{"config":{"name":"callup-tvmaze-42-s02","dir":"Some Show/Season 2/*"}}"#.utf8)
    let rejected = Data(#"{"status":false,"error":"Configuration locked"}"#.utf8)

    #expect(SABnzbdClient.decodeCategoryResponse(accepted))
    #expect(!SABnzbdClient.decodeCategoryResponse(rejected))
}

@Test func sabnzbdDerivedCategoryStaysUnderTheExistingTelevisionDirectory() throws {
    let connection = DownloadClientConnection(
        kind: .sabnzbd,
        endpoint: try #require(URL(string: "http://sab.example:8080")),
        secret: "fixture-secret"
    )
    let request = try SABnzbdClient.categoryConfigurationRequest(
        named: "tv",
        connection: connection
    )
    let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
    #expect(body.contains("mode=get_config"))
    #expect(body.contains("section=categories"))
    #expect(body.contains("keyword=tv"))
    #expect(!request.url!.absoluteString.contains("fixture-secret"))

    let response = Data(
        #"{"config":{"categories":[{"name":"tv","order":2,"pp":"","script":"Default","dir":"Television","newzbin":"","priority":-100}]}}"#.utf8
    )
    let television = try #require(
        SABnzbdClient.decodeCategoryConfiguration(response, name: "tv")
    )
    let show = television.appending(
        name: "callup-tvmaze-567-s02",
        relativeDirectory: "Gossip Girl/Season 2/*"
    )

    #expect(show.directory == "Television/Gossip Girl/Season 2/*")
    #expect(show.processing == "")
    #expect(show.script == "Default")
    #expect(show.priority == "-100")
}

@Test func sabnzbdOnlyRetriesSubmissionWhenNoConnectionWasEstablished() {
    #expect(SABnzbdClient.canSafelyRetrySubmission(after: .cannotConnectToHost))
    #expect(SABnzbdClient.canSafelyRetrySubmission(after: .cannotFindHost))
    #expect(!SABnzbdClient.canSafelyRetrySubmission(after: .timedOut))
    #expect(!SABnzbdClient.canSafelyRetrySubmission(after: .networkConnectionLost))
}

@Test func sabnzbdStatusMapsQueueAndHistoryToCallupStates() throws {
    let queue = Data(#"{"queue":{"slots":[{"nzo_id":"job-one","status":"Downloading"}]}}"#.utf8)
    let history = Data(#"{"history":{"slots":[{"nzo_id":"job-one","status":"Completed"}]}}"#.utf8)
    let failed = Data(#"{"history":{"slots":[{"nzo_id":"job-one","status":"Failed"}]}}"#.utf8)

    #expect(SABnzbdClient.decodeStatusResponse(queue, container: "queue", jobID: "job-one") == .downloading)
    #expect(SABnzbdClient.decodeStatusResponse(history, container: "history", jobID: "job-one") == .downloaded)
    #expect(SABnzbdClient.decodeStatusResponse(failed, container: "history", jobID: "job-one") == .blocked)
}

@Test func sabnzbdStatusRequestKeepsTheCredentialOutOfTheURL() throws {
    let connection = DownloadClientConnection(
        kind: .sabnzbd,
        endpoint: try #require(URL(string: "http://sab.example:8080")),
        secret: "fixture-secret"
    )
    let request = try SABnzbdClient.statusRequest(
        mode: "queue",
        jobID: "SABnzbd_nzo_fixture",
        connection: connection
    )
    let body = String(decoding: try #require(request.httpBody), as: UTF8.self)

    #expect(!request.url!.absoluteString.contains("fixture-secret"))
    #expect(body.contains("apikey=fixture-secret"))
    #expect(body.contains("nzo_ids=SABnzbd_nzo_fixture"))
}
