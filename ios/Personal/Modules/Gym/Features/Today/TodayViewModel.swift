import Foundation
import Observation

/// What Today has to show above the history (spec §6).
nonisolated enum TodayState: Equatable, Sendable {
    /// Before the first read; the screen shows a spinner, not an empty state.
    case loading
    /// No active program yet — the "No program yet" empty state with its CTA.
    case noProgram
    /// There is an active program; ``TodayViewModel/nextUp`` carries the card,
    /// or is `nil` when that program has no days yet.
    case ready
}

/// The "Next up" card: the day the rotation suggests plus its summary.
nonisolated struct TodayNextUp: Equatable, Sendable, Identifiable {

    var day: ProgramDay
    var exerciseCount: Int
    var estimatedMinutes: Int
    /// Art of the first planned exercise; `nil` when the day plans nothing.
    var art: ExerciseArt?

    var id: String { day.id }

    /// "6 exercises · ~50 min" (spec §6).
    var meta: String {
        let noun = exerciseCount == 1 ? "exercise" : "exercises"
        return "\(exerciseCount) \(noun) · ~\(estimatedMinutes) min"
    }
}

/// One session in the history list.
nonisolated struct TodayHistoryItem: Identifiable, Sendable {
    /// The session id — also what the navigation path pushes.
    var id: String
    /// Day name, the user's own rename, or "Free session".
    var title: String
    /// Clock time the session started.
    var time: String
    /// "4/6 sets".
    var setsText: String
    /// `HH:mm:ss` for a finished session, `nil` while it runs.
    var durationText: String?
    var isFinished: Bool
    var art: ExerciseArt?
}

/// One day header plus the sessions logged under it.
nonisolated struct TodayHistoryGroup: Identifiable, Sendable {
    /// Start of that calendar day, in seconds — a stable, sortable key.
    var id: String
    /// "Today", "Yesterday", "8 July".
    var primary: String
    /// The weekday.
    var secondary: String
    var items: [TodayHistoryItem]
}

/// Drives the Today tab.
///
/// Observation strategy: Today reloads on `.task`, after its own writes and
/// whenever the Session screen pops. The screen is a summary of five different
/// tables — program, days, planned exercises, sessions, sets — and a
/// `ValueObservation` wide enough to cover all five would refire on every set
/// the user ticks off in a session, for a card that cannot change while they
/// are in there. The live view belongs to ``SessionViewModel``, which does use
/// `ValueObservation`.
///
/// The reads are synchronous and run on the main actor. They are a handful of
/// indexed SQLite queries over a personal-sized database; the day they are
/// not, the whole `reload` body moves behind `dbWriter.read` in one place.
@Observable
@MainActor
final class TodayViewModel {

    /// Rest between sets when the plan does not say (spec §6).
    static let defaultRestSeconds = 90
    /// Seconds of actual work assumed per set, on top of the rest.
    static let workSecondsPerSet = 40
    /// How far back the history list goes.
    static let historyLimit = 30

    private(set) var state: TodayState = .loading
    private(set) var nextUp: TodayNextUp?
    private(set) var history: [TodayHistoryGroup] = []
    var toast: ToastItem?

    let imageStore: ImageStore?

    private let repository: GymRepository
    private let scheduler: SyncScheduler?

    init(
        repository: GymRepository,
        scheduler: SyncScheduler? = nil,
        imageStore: ImageStore? = nil
    ) {
        self.repository = repository
        self.scheduler = scheduler
        self.imageStore = imageStore
    }

    // MARK: - Reading

    /// Rebuilds everything the screen shows. Cheap enough to call on every
    /// appearance and after every write.
    func reload() {
        do {
            let program = try repository.activeProgram()
            if program == nil {
                state = .noProgram
                nextUp = nil
            } else {
                nextUp = try loadNextUp()
                state = .ready
            }
            history = try loadHistory()
        } catch {
            state = .noProgram
            nextUp = nil
            history = []
            toast = .error("Could not read the local database.")
        }
    }

    private func loadNextUp() throws -> TodayNextUp? {
        guard let day = try repository.nextUpDay() else { return nil }
        let planned = try repository.programExercises(of: day.id)

        // M = Σ target_sets × (rest + 40 s), in whole minutes (spec §6). The
        // division truncates on purpose: "~8 min" is a hint, not a promise.
        var seconds = 0
        for item in planned {
            let rest = item.restSeconds ?? Self.defaultRestSeconds
            seconds += max(0, item.targetSets) * (rest + Self.workSecondsPerSet)
        }

        var art: ExerciseArt?
        if let first = planned.first {
            if let exercise = try repository.exercise(id: first.exerciseId) {
                art = ExerciseArt(exercise)
            }
        }

        return TodayNextUp(
            day: day,
            exerciseCount: planned.count,
            estimatedMinutes: seconds / 60,
            art: art)
    }

    private func loadHistory() throws -> [TodayHistoryGroup] {
        let sessions = try repository.sessions(limit: Self.historyLimit)
        guard sessions.isEmpty == false else { return [] }

        // Day names of every program, not just the active one: a session
        // logged under an older program still deserves its title.
        var dayNames: [String: String] = [:]
        for program in try repository.programs() {
            for day in try repository.days(of: program.id) {
                dayNames[day.id] = day.name
            }
        }

        let calendar = Calendar.current
        var groups: [TodayHistoryGroup] = []
        var positions: [String: Int] = [:]

        for session in sessions {
            let item = try makeHistoryItem(session, dayNames: dayNames)
            let date = Date(timeIntervalSince1970: Double(session.startedAt) / 1000)
            let key = String(Int64(calendar.startOfDay(for: date).timeIntervalSince1970))
            if let position = positions[key] {
                groups[position].items.append(item)
            } else {
                let header = DateFormat.dayHeader(session.startedAt)
                groups.append(
                    TodayHistoryGroup(
                        id: key,
                        primary: header.primary,
                        secondary: header.secondary,
                        items: [item]))
                positions[key] = groups.count - 1
            }
        }
        return groups
    }

    private func makeHistoryItem(
        _ session: WorkoutSession,
        dayNames: [String: String]
    ) throws -> TodayHistoryItem {
        let sets = try repository.sets(of: session.id)

        var art: ExerciseArt?
        if let first = sets.first {
            if let exercise = try repository.exercise(id: first.exerciseId) {
                art = ExerciseArt(exercise)
            }
        }

        var completed = 0
        for set in sets where set.completed {
            completed += 1
        }

        var duration: String?
        if let finishedAt = session.finishedAt {
            duration = DateFormat.elapsed(from: session.startedAt, to: finishedAt)
        }

        return TodayHistoryItem(
            id: session.id,
            title: Self.title(of: session, dayNames: dayNames),
            time: DateFormat.time(session.startedAt),
            setsText: "\(completed)/\(sets.count) sets",
            durationText: duration,
            isFinished: session.isFinished,
            art: art)
    }

    /// The user's rename wins over the day name, which wins over the fallback.
    /// A session has no name column of its own, so a rename is stored in
    /// `notes` (see ``SessionViewModel/commitRename()``).
    private static func title(
        of session: WorkoutSession,
        dayNames: [String: String]
    ) -> String {
        if let notes = session.notes, notes.isEmpty == false {
            return notes
        }
        if let dayId = session.programDayId, let name = dayNames[dayId] {
            return name
        }
        return "Free session"
    }

    // MARK: - Writing

    /// Opens a session on the suggested day (spec §6) and answers its id, so
    /// the screen can push straight into it. `nil` means the write failed and
    /// a toast is already on screen.
    @discardableResult
    func startSession() -> String? {
        do {
            let session = try repository.startSession(from: nextUp?.day)
            scheduler?.trigger(.afterWrite)
            reload()
            return session.id
        } catch {
            toast = .error("Could not start the session.")
            return nil
        }
    }
}
