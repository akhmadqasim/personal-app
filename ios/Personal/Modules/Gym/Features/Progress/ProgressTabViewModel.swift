import Foundation
import Observation

/// What the Progress tab has to show (spec §6).
nonisolated enum ProgressState: Equatable, Sendable {
    /// Before the first read; the screen shows a spinner, not an empty state.
    case loading
    /// No exercise has a single completed set — the whole-tab empty state.
    case empty
    /// The selected exercise has fewer than two sessions, so a line between
    /// them would be a line between nothing.
    case notEnoughData
    /// Charts, best-set tile and volume bars are all filled.
    case ready
}

/// One point of the line chart: the heaviest set of one session.
nonisolated struct ProgressPoint: Equatable, Sendable, Identifiable {
    var date: Date
    var weightKg: Double

    /// Sessions cannot share a millisecond, so the date is the identity.
    var id: Date { date }
}

/// One bar of the volume chart: a week and what was lifted in it.
nonisolated struct ProgressWeek: Equatable, Sendable, Identifiable {
    var weekStart: Date
    /// Short axis label of that week, "8 Sep".
    var label: String
    var volumeKg: Double

    var id: Date { weekStart }
}

/// The "Best set" tile, already formatted: view models do the number
/// formatting so the views stay declarative and the strings are testable.
nonisolated struct ProgressBest: Equatable, Sendable {
    /// "65 kg × 8".
    var valueText: String
    /// "Mon 4 Sep".
    var dateText: String
}

/// Drives the Progress tab: pick an exercise, then read three series for it.
///
/// Observation strategy follows Today (task 5): a plain `reload()` on `.task`
/// and after every selection change. Progress is a read-only summary of
/// finished work — nothing on this screen can change while the user is
/// looking at it, so a `ValueObservation` would only cost a redraw per set
/// ticked off in a session the user is not currently in.
///
/// The reads are synchronous on the main actor, like ``TodayViewModel``'s:
/// four indexed queries over a personal-sized database.
@Observable
@MainActor
final class ProgressTabViewModel {

    /// How far back every chart looks (spec §6).
    static let windowWeeks = 12
    /// How many chips the row offers before the search sheet takes over.
    static let topExerciseCount = 6
    /// Two sessions is the smallest thing a trend can be drawn through.
    static let minimumSessions = 2

    private(set) var state: ProgressState = .loading
    /// The top six by recent volume, heaviest first.
    private(set) var topExercises: [Exercise] = []
    private(set) var selected: Exercise?
    private(set) var points: [ProgressPoint] = []
    private(set) var weeklyVolume: [ProgressWeek] = []
    private(set) var best: ProgressBest?
    var toast: ToastItem?

    private let repository: GymRepository
    /// Survives a reload, so the exercise the user picked stays picked even
    /// when a new session reshuffles the top six.
    private var selectedId: String?

    init(repository: GymRepository) {
        self.repository = repository
    }

    // MARK: - Derived

    /// The chips row: the top six, plus whatever the user picked in the search
    /// sheet when it is not one of them — a chip the user chose must stay
    /// visible, otherwise the screen shows a chart nothing points at.
    var chipExercises: [Exercise] {
        guard let selected else { return topExercises }
        if topExercises.contains(where: { $0.id == selected.id }) {
            return topExercises
        }
        var list = topExercises
        list.insert(selected, at: 0)
        return list
    }

    /// The `muscle_group` slug the charts colour themselves with
    /// (``Theme/accent(for:)`` and ``Theme/soft(for:)``).
    var accentGroup: String {
        selected?.muscleGroup.rawValue ?? MuscleGroup.other.rawValue
    }

    var exerciseName: String {
        selected?.name ?? ""
    }

    /// What VoiceOver reads instead of walking the line chart's marks.
    var chartAccessibilityValue: String {
        guard let first = points.first, let last = points.last else {
            return "No sessions yet"
        }
        let noun = points.count == 1 ? "session" : "sessions"
        return "\(points.count) \(noun), from \(WeightFormat.plain(first.weightKg)) kg"
            + " to \(WeightFormat.plain(last.weightKg)) kg"
    }

    /// The same, for the volume bars.
    var volumeAccessibilityValue: String {
        guard weeklyVolume.isEmpty == false else { return "No volume yet" }
        var total: Double = 0
        for week in weeklyVolume {
            total += week.volumeKg
        }
        let noun = weeklyVolume.count == 1 ? "week" : "weeks"
        return "\(weeklyVolume.count) \(noun), \(WeightFormat.plain(total)) kg in total"
    }

    // MARK: - Reading

    /// Rebuilds the chips and the three series of the selected exercise.
    func reload() {
        do {
            let top = try repository.topExercisesByVolume(
                limit: Self.topExerciseCount,
                weeks: Self.windowWeeks)
            topExercises = top

            guard top.isEmpty == false else {
                // Nothing anywhere has been completed: this is the whole-tab
                // empty state, whatever the user picked earlier.
                selected = nil
                points = []
                weeklyVolume = []
                best = nil
                state = .empty
                return
            }

            let chosen = try resolveSelection(in: top)
            selected = chosen
            guard let chosen else {
                state = .empty
                return
            }
            try loadSeries(for: chosen)
        } catch {
            // Keep whatever is on screen: a failed read says nothing about
            // whether the user has trained, and blanking the tab into
            // "Nothing logged yet" would be a lie about their history.
            toast = .error("Could not read the local database.")
        }
    }

    /// Switches the charts to another exercise — a chip tap or the search
    /// sheet's callback.
    func select(_ exercise: Exercise) {
        selectedId = exercise.id
        reload()
    }

    // MARK: - Plumbing

    /// The user's pick when it still exists — it may have been chosen in the
    /// search sheet and sit outside the top six — and the heaviest-trained
    /// exercise otherwise.
    private func resolveSelection(in top: [Exercise]) throws -> Exercise? {
        if let selectedId {
            if let match = top.first(where: { $0.id == selectedId }) {
                return match
            }
            if let stored = try repository.exercise(id: selectedId) {
                return stored
            }
        }
        return top.first
    }

    private func loadSeries(for exercise: Exercise) throws {
        let bestSets = try repository.bestSetPerSession(
            exerciseId: exercise.id,
            weeks: Self.windowWeeks)
        points = bestSets.map { set in
            ProgressPoint(date: Self.date(set.sessionStartedAt), weightKg: set.weightKg)
        }

        let volume = try repository.weeklyVolume(
            exerciseId: exercise.id,
            weeks: Self.windowWeeks)
        weeklyVolume = volume.map { week in
            ProgressWeek(
                weekStart: Self.date(week.weekStartMs),
                label: DateFormat.dayMonthShort(week.weekStartMs),
                volumeKg: week.volumeKg)
        }

        let record = try repository.personalBest(
            exerciseId: exercise.id,
            weeks: Self.windowWeeks)
        best = record.map { heaviest in
            ProgressBest(
                valueText: "\(WeightFormat.plain(heaviest.weightKg)) kg × \(heaviest.reps)",
                dateText: DateFormat.shortDate(heaviest.sessionStartedAt))
        }

        state = points.count >= Self.minimumSessions ? .ready : .notEnoughData
    }

    private static func date(_ ms: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000)
    }
}
