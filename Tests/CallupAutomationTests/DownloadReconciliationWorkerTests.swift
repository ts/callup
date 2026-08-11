import CallupAutomation
import CallupCore
import Foundation
import Testing

@Test func reconciliationUpdatesOnlyActiveSABnzbdDownloads() async throws {
    let activeID = ProviderReference(provider: "fixture", value: "active")
    let completedID = ProviderReference(provider: "fixture", value: "completed")
    let store = SubmissionStoreStub(submissions: [
        submission(id: activeID, state: .snatched, jobID: "job-active"),
        submission(id: completedID, state: .downloaded, jobID: "job-completed"),
    ])
    let statuses = StatusStub(states: ["job-active": .downloaded])
    let worker = DownloadReconciliationWorker(
        store: store,
        connections: ConnectionStub(kind: .sabnzbd),
        statuses: statuses
    )

    let result = try await worker.reconcile()

    #expect(result == DownloadReconciliationResult(examined: 1, updated: 1, failures: 0))
    #expect(await store.state(for: activeID) == .downloaded)
    #expect(await store.state(for: completedID) == .downloaded)
    #expect(await statuses.requestedJobIDs == ["job-active"])
}

@Test func reconciliationIsDisabledWithoutSABnzbd() async throws {
    let store = SubmissionStoreStub(submissions: [
        submission(
            id: ProviderReference(provider: "fixture", value: "active"),
            state: .snatched,
            jobID: "job-active"
        ),
    ])
    let statuses = StatusStub(states: ["job-active": .downloaded])
    let worker = DownloadReconciliationWorker(
        store: store,
        connections: ConnectionStub(kind: .nzbget),
        statuses: statuses
    )

    #expect(try await worker.reconcile() == DownloadReconciliationResult(
        examined: 0,
        updated: 0,
        failures: 0
    ))
    #expect(await statuses.requestedJobIDs.isEmpty)
}

@Test func oneStatusFailureDoesNotPreventOtherDownloadsFromProgressing() async throws {
    let failingID = ProviderReference(provider: "fixture", value: "failing")
    let progressingID = ProviderReference(provider: "fixture", value: "progressing")
    let store = SubmissionStoreStub(submissions: [
        submission(id: failingID, state: .snatched, jobID: "job-failing"),
        submission(id: progressingID, state: .downloading, jobID: "job-progressing"),
    ])
    let statuses = StatusStub(
        states: ["job-progressing": .downloaded],
        failingJobIDs: ["job-failing"]
    )
    let worker = DownloadReconciliationWorker(
        store: store,
        connections: ConnectionStub(kind: .sabnzbd),
        statuses: statuses
    )

    let result = try await worker.reconcile()

    #expect(result == DownloadReconciliationResult(examined: 2, updated: 1, failures: 1))
    #expect(await store.state(for: progressingID) == .downloaded)
}

@Test func workerRunsImmediatelyAndStopsCleanly() async throws {
    let store = SubmissionStoreStub(submissions: [
        submission(
            id: ProviderReference(provider: "fixture", value: "active"),
            state: .snatched,
            jobID: "job-active"
        ),
    ])
    let statuses = StatusStub(states: [:])
    let worker = DownloadReconciliationWorker(
        store: store,
        connections: ConnectionStub(kind: .sabnzbd),
        statuses: statuses,
        interval: .milliseconds(10)
    )

    await worker.start()
    for _ in 0..<100 where await statuses.requestedJobIDs.isEmpty {
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(await statuses.requestedJobIDs == ["job-active"])

    await worker.stop()
    let requestCountAfterStop = await statuses.requestedJobIDs.count
    try await Task.sleep(for: .milliseconds(25))
    #expect(await statuses.requestedJobIDs.count == requestCountAfterStop)
}

private actor SubmissionStoreStub: DownloadSubmissionStoring {
    private var submissions: [DownloadSubmission]

    init(submissions: [DownloadSubmission]) {
        self.submissions = submissions
    }

    func downloadSubmissions() -> [DownloadSubmission] {
        submissions
    }

    func updateDownloadSubmissionState(
        candidateID: ProviderReference,
        state: DownloadSubmissionState,
        at date: Date
    ) throws -> DownloadSubmission {
        guard let index = submissions.firstIndex(where: { $0.candidateID == candidateID }) else {
            throw FixtureError.missingSubmission
        }
        let existing = submissions[index]
        let updated = DownloadSubmission(
            candidateID: existing.candidateID,
            acquisitionContext: existing.acquisitionContext,
            title: existing.title,
            client: existing.client,
            state: state,
            clientJobID: existing.clientJobID,
            createdAt: existing.createdAt,
            updatedAt: date
        )
        submissions[index] = updated
        return updated
    }

    func state(for candidateID: ProviderReference) -> DownloadSubmissionState? {
        submissions.first(where: { $0.candidateID == candidateID })?.state
    }
}

private actor ConnectionStub: DownloadConnectionProviding {
    let connection: DownloadClientConnection?

    init(kind: DownloadClientKind?) {
        connection = kind.map {
            DownloadClientConnection(
                kind: $0,
                endpoint: URL(string: "http://download.example")!,
                username: $0 == .nzbget ? "fixture" : nil,
                secret: "fixture-secret"
            )
        }
    }

    func downloadClientConnection() -> DownloadClientConnection? {
        connection
    }
}

private actor StatusStub: DownloadStatusProviding {
    private let states: [String: DownloadSubmissionState]
    private let failingJobIDs: Set<String>
    private(set) var requestedJobIDs: [String] = []

    init(
        states: [String: DownloadSubmissionState],
        failingJobIDs: Set<String> = []
    ) {
        self.states = states
        self.failingJobIDs = failingJobIDs
    }

    func status(
        jobID: String,
        connection: DownloadClientConnection
    ) throws -> DownloadSubmissionState? {
        requestedJobIDs.append(jobID)
        if failingJobIDs.contains(jobID) { throw FixtureError.statusUnavailable }
        return states[jobID]
    }
}

private enum FixtureError: Error {
    case missingSubmission
    case statusUnavailable
}

private func submission(
    id: ProviderReference,
    state: DownloadSubmissionState,
    jobID: String
) -> DownloadSubmission {
    DownloadSubmission(
        candidateID: id,
        title: id.value,
        client: .sabnzbd,
        state: state,
        clientJobID: jobID,
        createdAt: .distantPast,
        updatedAt: .distantPast
    )
}
