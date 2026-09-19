import Foundation
import Testing

@testable import Personal

/// A ``SyncRunning`` that answers with a fixed outcome, optionally after a
/// pause, and counts how often it was asked.
///
/// An `actor`, like the real engine, so the scheduler's `await` really does
/// leave the main actor and a second caller can arrive mid-run.
private actor StubSyncEngine: SyncRunning {

    private let outcome: SyncOutcome
    private let delay: Duration?
    private(set) var runs = 0

    init(outcome: SyncOutcome, delay: Duration? = nil) {
        self.outcome = outcome
        self.delay = delay
    }

    func sync() async -> SyncOutcome {
        runs += 1
        if let delay {
            try? await Task.sleep(for: delay)
        }
        return outcome
    }

    func lastSyncedAt() async throws -> Int64? {
        nil
    }
}

@MainActor
struct SyncSchedulerTests {

    @Test func aRunReportsWhatItEndedIn() async {
        let expected = SyncOutcome.success(pulled: 3, pushed: 1, skipped: 0)
        let engine = StubSyncEngine(outcome: expected)
        let status = SyncStatus()
        let scheduler = SyncScheduler(engine: engine, status: status)

        let outcome = await scheduler.syncNow()

        #expect(outcome == expected)
        #expect(status.state == SyncState.idle)
        #expect(status.lastSyncedAt != nil)
    }

    @Test func aFailedRunIsReportedAndLeavesTheStatusInError() async {
        let expected = SyncOutcome.failure(.unauthorized)
        let engine = StubSyncEngine(outcome: expected)
        let status = SyncStatus()
        let scheduler = SyncScheduler(engine: engine, status: status)

        let outcome = await scheduler.syncNow()

        let expectedState = SyncState.error(ApiError.unauthorized.message)
        #expect(outcome == expected)
        #expect(status.state == expectedState)
        #expect(status.lastSyncedAt == nil)
    }

    /// The point of item 2: a caller that arrives while a run is in flight used
    /// to be told nothing at all, which let "Test connection" report success
    /// for a round trip that had not come back yet.
    @Test func aCallMadeDuringARunWaitsForThatRunsOutcome() async {
        let expected = SyncOutcome.failure(.unauthorized)
        let engine = StubSyncEngine(outcome: expected, delay: .milliseconds(100))
        let status = SyncStatus()
        let scheduler = SyncScheduler(engine: engine, status: status)

        let first = Task { await scheduler.syncNow() }
        // Wait for the first call to reach the engine, so the second one
        // really does arrive mid-run. Bounded, so a regression fails the test
        // instead of hanging the suite.
        var spins = 0
        while spins < 10_000 {
            let started = await engine.runs
            if started > 0 {
                break
            }
            spins += 1
            await Task.yield()
        }

        let second = await scheduler.syncNow()
        let firstOutcome = await first.value

        #expect(firstOutcome == expected)
        #expect(second == expected)
        let expectedState = SyncState.error(ApiError.unauthorized.message)
        #expect(status.state == expectedState)
    }
}
