import CallupCore
import CallupDownloadClients
import CallupPersistence
import Foundation

public protocol DownloadSubmissionStoring: Sendable {
    func downloadSubmissions() async throws -> [DownloadSubmission]

    func updateDownloadSubmissionState(
        candidateID: ProviderReference,
        state: DownloadSubmissionState,
        at date: Date
    ) async throws -> DownloadSubmission
}

public protocol DownloadConnectionProviding: Sendable {
    func downloadClientConnection() async -> DownloadClientConnection?
}

public protocol DownloadStatusProviding: Sendable {
    func status(
        jobID: String,
        connection: DownloadClientConnection
    ) async throws -> DownloadSubmissionState?
}

extension ApplicationStore: DownloadSubmissionStoring {}

extension ConnectionSettingsStore: DownloadConnectionProviding {
    public func downloadClientConnection() -> DownloadClientConnection? {
        load().downloadClient
    }
}

extension SABnzbdClient: DownloadStatusProviding {}

public struct DownloadReconciliationResult: Equatable, Sendable {
    public let examined: Int
    public let updated: Int
    public let failures: Int

    public init(examined: Int, updated: Int, failures: Int) {
        self.examined = examined
        self.updated = updated
        self.failures = failures
    }
}

public enum DownloadReconciliationEvent: Sendable {
    case completed(DownloadReconciliationResult)
    case failed(String)
}

public actor DownloadReconciliationWorker {
    public typealias EventHandler = @Sendable (DownloadReconciliationEvent) -> Void

    private let store: any DownloadSubmissionStoring
    private let connections: any DownloadConnectionProviding
    private let statuses: any DownloadStatusProviding
    private let interval: Duration
    private let onEvent: EventHandler
    private var task: Task<Void, Never>?

    public init(
        store: any DownloadSubmissionStoring,
        connections: any DownloadConnectionProviding,
        statuses: any DownloadStatusProviding,
        interval: Duration = .seconds(60),
        onEvent: @escaping EventHandler = { _ in }
    ) {
        self.store = store
        self.connections = connections
        self.statuses = statuses
        self.interval = interval
        self.onEvent = onEvent
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.run()
        }
    }

    public func stop() async {
        let runningTask = task
        task = nil
        runningTask?.cancel()
        await runningTask?.value
    }

    @discardableResult
    public func reconcile() async throws -> DownloadReconciliationResult {
        guard let connection = await connections.downloadClientConnection(),
              connection.kind == .sabnzbd else {
            return DownloadReconciliationResult(examined: 0, updated: 0, failures: 0)
        }

        let submissions = try await store.downloadSubmissions()
        var examined = 0
        var updated = 0
        var failures = 0

        for submission in submissions {
            guard [.snatched, .downloading].contains(submission.state),
                  let jobID = submission.clientJobID else { continue }
            examined += 1

            do {
                guard let state = try await statuses.status(
                    jobID: jobID,
                    connection: connection
                ), state != submission.state else { continue }
                _ = try await store.updateDownloadSubmissionState(
                    candidateID: submission.candidateID,
                    state: state,
                    at: Date()
                )
                updated += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures += 1
            }
        }

        return DownloadReconciliationResult(
            examined: examined,
            updated: updated,
            failures: failures
        )
    }

    private func run() async {
        while !Task.isCancelled {
            do {
                onEvent(.completed(try await reconcile()))
            } catch is CancellationError {
                return
            } catch {
                onEvent(.failed(String(describing: error)))
            }

            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
        }
    }
}
