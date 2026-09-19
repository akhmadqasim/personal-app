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
    /// The session the point came from — the identity, rather than the date:
    /// two sessions started in the same millisecond would collide, and the id
    /// is what the row is keyed on everywhere else.
    var id: String
    var date: Date
    var weightKg: Double
}

/// One bar of the volume chart: a week and what was lifted in it. Weeks with
/// no training are present with a `volumeKg` of zero — a layoff is a fact the
/// chart has to show, not a gap it may hide.
nonisolated struct ProgressWeek: Equatable, Sendable, Identifiable {
    /// Monday 00:00 UTC of that week.
    var weekStart: Date
    /// Short axis label of that week, "8 Sep", formatted in UTC.
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

    /// The same, for the volume bars. The total is grouped ("12,480 kg"):
    /// VoiceOver reads a bare five-digit number digit by digit.
    var volumeAccessibilityValue: String {
        guard weeklyVolume.isEmpty == false else { return "No volume yet" }
        var total: Double = 0
        for week in weeklyVolume {
            total += week.volumeKg
        }
        let noun = weeklyVolume.count == 1 ? "week" : "weeks"
        return "\(weeklyVolume.count) \(noun), \(total.formatted()) kg in total"
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

            // `top` is not empty, so `resolveSelection` always answers.
            let chosen = try resolveSelection(in: top)
            selected = chosen
            try loadSeries(for: chosen)
        } catch {
            // Keep whatever is on screen: a failed read says nothing about
            // whether the user has trained, and blanking a filled tab into
            // "Nothing logged yet" would be a lie about their history.
            //
            // The one exception is the very first read: leaving `.loading` in
            // place would spin forever behind a toast the user has already
            // dismissed, so the empty state takes over and `.task` retries on
            // the next appearance.
            toast = .error("Could not read the local database.")
            if state == .loading {
                state = .empty
            }
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
    /// exercise otherwise. `top` is never empty at the one call site.
    private func resolveSelection(in top: [Exercise]) throws -> Exercise {
        if let selectedId {
            if let match = top.first(where: { $0.id == selectedId }) {
                return match
            }
            if let stored = try repository.exercise(id: selectedId) {
                return stored
            }
        }
        return top[0]
    }

    private func loadSeries(for exercise: Exercise) throws {
        let bestSets = try repository.bestSetPerSession(
            exerciseId: exercise.id,
            weeks: Self.windowWeeks)
        points = bestSets.map { set in
            ProgressPoint(
                id: set.sessionId,
                date: Self.date(set.sessionStartedAt),
                weightKg: set.weightKg)
        }

        weeklyVolume = try loadWeeklyVolume(for: exercise)

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

    /// Exactly ``windowWeeks`` bars: the week that is running now and the
    /// eleven before it, each carrying whatever was lifted in it or zero.
    ///
    /// The repository only returns weeks that have training in them, so a
    /// three-week layoff would otherwise collapse into two adjacent bars and
    /// read as "trained twice in a row". Zero-filling also makes the chart's
    /// "over the last 12 weeks" label true, and pins the x domain so two
    /// exercises are drawn on the same axis.
    ///
    /// The window starts on a Monday by construction, so the leftmost bar is a
    /// whole week rather than the stump `now − 12 weeks` would cut. A session
    /// that falls in the part-week between the repository's cutoff and that
    /// Monday is outside the twelve bars and is dropped here.
    private func loadWeeklyVolume(for exercise: Exercise) throws -> [ProgressWeek] {
        let logged = try repository.weeklyVolume(
            exerciseId: exercise.id,
            weeks: Self.windowWeeks)
        var byWeekStart: [Int64: Double] = [:]
        for week in logged {
            byWeekStart[week.weekStartMs] = week.volumeKg
        }

        let lastStart = repository.currentWeekStartMs()
        let firstStart = lastStart - Int64(Self.windowWeeks - 1) * GymRepository.weekMs
        var result: [ProgressWeek] = []
        var start = firstStart
        while start <= lastStart {
            result.append(
                ProgressWeek(
                    weekStart: Self.date(start),
                    label: DateFormat.weekStartShort(start),
                    volumeKg: byWeekStart[start] ?? 0))
            start += GymRepository.weekMs
        }
        return result
    }

    private static func date(_ ms: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000)
    }
}
