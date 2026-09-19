import Foundation

/// Why a sync was asked for (spec §5).
nonisolated enum SyncReason: Sendable {
    /// The app started.
    case launch
    /// The scene became active again.
    case foreground
    /// A repository write happened; debounced, because a set edit is followed
    /// by five more.
    case afterWrite
    /// The user tapped "Sync now".
    case manual
}

/// Decides *when* ``SyncEngine`` runs and publishes the result through
/// ``SyncStatus``.
///
/// `@MainActor`: it owns UI-facing state and the debounce timer. The engine it
/// drives is an actor, so the work itself never touches this thread.
@MainActor
final class SyncScheduler {

    typealias Reason = SyncReason

    /// The state the UI observes.
    let status: SyncStatus

    private let engine: any SyncRunning
    private let debounce: Duration
    private var debounceTask: Task<Void, Never>?
    /// The run currently in flight. Held as the `Task` itself, not as a flag,
    /// so a second caller can await the outcome of the run it joined.
    private var inFlight: Task<SyncOutcome, Never>?
    private var runAgain = false

    init(
        engine: any SyncRunning,
        status: SyncStatus = SyncStatus(),
        debounce: Duration = .seconds(2)
    ) {
        self.engine = engine
        self.status = status
        self.debounce = debounce
        Task { [weak self] in
            await self?.restoreLastSyncedAt()
        }
    }

    /// Shows the stored sync time right after a relaunch, before the first run
    /// of this session has had a chance to finish.
    func restoreLastSyncedAt() async {
        guard status.lastSyncedAt == nil else { return }
        guard let milliseconds = try? await engine.lastSyncedAt() else { return }
        guard status.lastSyncedAt == nil else { return }
        status.lastSyncedAt = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    /// Asks for a sync. `.afterWrite` waits out the debounce window and is
    /// replaced by any later write; every other reason starts at once.
    func trigger(_ reason: Reason) {
        debounceTask?.cancel()
        debounceTask = nil

        switch reason {
        case .afterWrite:
            let delay = debounce
            debounceTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
                _ = await self?.syncNow()
            }
        case .launch, .foreground, .manual:
            Task { [weak self] in
                _ = await self?.syncNow()
            }
        }
    }

    /// Runs the engine and answers for the run that actually happened.
    ///
    /// When a run is already in flight it is asked to go around once more — a
    /// write made mid-sync is never left behind — and this call *waits* for
    /// that run instead of returning at once. "Test connection" reports what
    /// it is told, so being told nothing would let it say the connection works
    /// while no request ever left the device.
    ///
    /// `nil` means the run produced no outcome at all, which only happens when
    /// the scheduler was torn down mid-run.
    @discardableResult
    func syncNow() async -> SyncOutcome? {
        if let inFlight {
            runAgain = true
            return await inFlight.value
        }

        let task: Task<SyncOutcome, Never> = Task { [self] in
            var last: SyncOutcome
            repeat {
                runAgain = false
                status.state = .syncing
                last = await engine.sync()
                switch last {
                case .success:
                    status.state = .idle
                    status.lastSyncedAt = Date()
                case .failure(let error):
                    status.state = .error(error.message)
                }
            } while runAgain
            return last
        }
        inFlight = task
        let outcome = await task.value
        inFlight = nil
        return outcome
    }
}
