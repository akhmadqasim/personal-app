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

    private let engine: SyncEngine
    private let debounce: Duration
    private var debounceTask: Task<Void, Never>?
    private var isRunning = false
    private var runAgain = false

    init(engine: SyncEngine, status: SyncStatus = SyncStatus(), debounce: Duration = .seconds(2)) {
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
                await self?.syncNow()
            }
        case .launch, .foreground, .manual:
            Task { [weak self] in
                await self?.syncNow()
            }
        }
    }

    /// Runs the engine now, unless a run is already in flight — in which case
    /// that run is asked to go around once more, so a write made mid-sync is
    /// never left behind.
    func syncNow() async {
        if isRunning {
            runAgain = true
            return
        }
        isRunning = true
        defer { isRunning = false }

        repeat {
            runAgain = false
            status.state = .syncing
            let outcome = await engine.sync()
            switch outcome {
            case .success:
                status.state = .idle
                status.lastSyncedAt = Date()
            case .failure(let error):
                status.state = .error(error.message)
            }
        } while runAgain
    }
}
