import Foundation
import Observation
import UIKit

/// One set row of the Session screen.
///
/// `number` is the per-exercise rank the user sees ("#1", "#2"). It is *not*
/// `workout_set.position`, which counts across the whole session (spec §6).
nonisolated struct SessionSetRow: Identifiable, Equatable, Sendable {
    /// The `workout_set` id.
    var id: String
    var number: Int
    var weightKg: Double
    var reps: Int
    var rpe: Double?
    var completed: Bool

    /// "60 kg × 8".
    var valueText: String {
        "\(WeightFormat.plain(weightKg)) kg × \(reps)"
    }

    /// "RPE 8.5", or `nil` when the user did not record one.
    var rpeText: String? {
        guard let rpe else { return nil }
        return "RPE \(WeightFormat.plain(rpe))"
    }
}

/// One `GroupCard` of the Session screen: an exercise and its sets.
nonisolated struct SessionExerciseGroup: Identifiable, Equatable, Sendable {
    /// The `exercise` id.
    var id: String
    var name: String
    /// "Full body" — the muscle chip.
    var muscleLabel: String
    /// The raw `muscle_group` column value, for `Theme.accent(for:)`.
    var muscleGroup: String
    var art: ExerciseArt
    /// "Last time 57.5 × 8", or `nil` the first time this exercise is trained.
    var lastTime: String?
    var sets: [SessionSetRow]
}

/// Drives the Session screen (spec §6).
///
/// Observation strategy: the set list is watched with `ValueObservation`
/// (`observeSets(of:)`), consumed by ``observeSets()`` from the view's
/// `.task`, so a sync pull that lands mid-session redraws the rows. Every
/// write also reloads synchronously, because the observation is asynchronous
/// and a tap on a completion circle has to feel immediate.
///
/// The session row itself (title, `finished_at`) is read on appear and after
/// the writes that touch it — it cannot change from anywhere else.
@Observable
@MainActor
final class SessionViewModel {

    let sessionId: String
    let imageStore: ImageStore?

    private(set) var session: WorkoutSession?
    /// Rename, else the program day's name, else "Free session".
    private(set) var title: String = "Free session"
    private(set) var groups: [SessionExerciseGroup] = []
    /// Art of the first exercise — the ambient background and the screen's
    /// contextual accent.
    private(set) var art: ExerciseArt?
    /// The custom photo behind the content; `nil` for built-in art, which
    /// leaves the background as plain `canvas` (spec §7).
    private(set) var ambientImage: UIImage?
    /// Set once the session is finished or discarded: the screen pops.
    private(set) var isGone = false

    var toast: ToastItem?
    /// Non-nil while the set editor sheet is up.
    var editingSet: SessionSetRow?
    var isPickingExercise = false
    var isDiscarding = false
    var isRenaming = false
    var renameText: String = ""

    private let repository: GymRepository
    private let scheduler: SyncScheduler?

    private var sets: [WorkoutSet] = []
    private var dayName: String?
    private var exerciseCache: [String: Exercise] = [:]
    /// `[exerciseId: caption]`; the inner optional is the answer "there is no
    /// last time", which is worth caching too.
    private var lastTimeCache: [String: String?] = [:]

    init(
        sessionId: String,
        repository: GymRepository,
        scheduler: SyncScheduler? = nil,
        imageStore: ImageStore? = nil
    ) {
        self.sessionId = sessionId
        self.repository = repository
        self.scheduler = scheduler
        self.imageStore = imageStore
    }

    // MARK: - Reading

    /// Reads the session row and its sets. Safe to call repeatedly.
    func loadSession() {
        let row: WorkoutSession?
        do {
            row = try repository.session(id: sessionId)
        } catch {
            // The read itself failed. That says nothing about whether the
            // session still exists, so the screen stays put and says so —
            // popping here would throw away a session over a transient error.
            toast = .error("Could not read the local database.")
            return
        }
        guard let found = row else {
            // Deleted on another device, or discarded here: nothing to show.
            isGone = true
            return
        }
        session = found
        if let dayId = found.programDayId {
            dayName = programDayName(for: dayId)
        }
        title = Self.title(notes: found.notes, dayName: dayName)
        reloadSets()
    }

    /// Streams the session's sets until the caller's task is cancelled — the
    /// view drives it from `.task`, which cancels on disappear.
    func observeSets() async {
        let observation = repository.observeSets(of: sessionId)
        let writer = repository.dbWriter
        do {
            for try await rows in observation.values(in: writer) {
                apply(rows)
            }
        } catch {
            guard Task.isCancelled == false else { return }
            toast = .error("Could not read the local database.")
        }
    }

    /// Loads the custom photo behind the content. Built-in art resolves to
    /// `nil` bytes, which leaves the background plain (spec §7).
    func loadAmbientImage() async {
        // Cleared first: the art can change under us when the session's first
        // exercise does, and stale blur behind a new movement is worse than
        // plain `canvas`.
        ambientImage = nil
        guard let key = art?.imageKey else { return }
        guard let store = imageStore else { return }
        guard let data = await store.imageData(for: key) else { return }
        ambientImage = UIImage(data: data)
    }

    /// "Push A · Tue 19 Sep · 00:42:10 elapsed" (spec §6) — the caption under
    /// the title, refreshed every second by the screen's `TimelineView`.
    ///
    /// The absolute date, not `dayHeader`'s relative "Today": next to a
    /// running timer, "Today" reads as part of the duration.
    func caption(at date: Date) -> String {
        guard let session else { return "" }
        let end = session.finishedAt ?? Int64((date.timeIntervalSince1970 * 1000).rounded())
        var parts: [String] = []
        if let dayName {
            parts.append(dayName)
        }
        parts.append(DateFormat.shortDate(session.startedAt))
        parts.append("\(DateFormat.elapsed(from: session.startedAt, to: end)) elapsed")
        return parts.joined(separator: " · ")
    }

    var isFinished: Bool {
        session?.isFinished ?? false
    }

    /// The exercise the ambient art comes from; the screen watches it so that
    /// adding the first movement to an empty session reloads the background.
    var firstExerciseId: String? {
        groups.first?.id
    }

    // MARK: - Writing

    /// Ticks a set off, or un-ticks it. The caller plays the haptic and the
    /// animation; this only moves the column.
    ///
    /// The "Last time" cache is deliberately left alone: the caption is about
    /// what happened *before* this session, so nothing the user does in here
    /// can change it.
    func toggleCompleted(_ setId: String) {
        guard var stored = storedSet(setId) else { return }
        stored.completed.toggle()
        save(stored)
    }

    /// Saves the set editor. The UI already constrains the inputs (spec §8);
    /// the clamps here are the last line of defence.
    func updateSet(_ setId: String, weightKg: Double, reps: Int, rpe: Double?) {
        guard var stored = storedSet(setId) else { return }
        stored.weightKg = max(0, weightKg)
        stored.reps = max(1, reps)
        stored.rpe = rpe.map { min(10, max(1, $0)) }
        save(stored)
    }

    /// Soft delete, so the tombstone reaches the server (spec §5).
    func deleteSet(_ setId: String) {
        do {
            try repository.softDelete(.workoutSet, id: setId)
            scheduler?.trigger(.afterWrite)
            reloadSets()
        } catch {
            toast = .error("Could not delete the set.")
        }
    }

    /// "+ Add set": copies the last set of that exercise — weight, reps and
    /// the RPE the user was working at — else the last one they ever
    /// completed, else an empty set.
    func addSet(to exerciseId: String) {
        var weightKg: Double = 0
        var reps = 8
        var rpe: Double?

        let existing = sets.last(where: { $0.exerciseId == exerciseId })
        if let existing {
            weightKg = existing.weightKg
            reps = existing.reps
            rpe = existing.rpe
        } else if let last = try? repository.lastCompletedSet(exerciseId: exerciseId) {
            weightKg = last.weightKg
            reps = last.reps
            rpe = last.rpe
        }

        // `position` runs across the whole session, so a new set appends.
        var nextPosition = 0
        for set in sets {
            nextPosition = max(nextPosition, set.position + 1)
        }

        save(
            WorkoutSet(
                id: Self.newID(),
                sessionId: sessionId,
                exerciseId: exerciseId,
                position: nextPosition,
                weightKg: weightKg,
                reps: reps,
                rpe: rpe))
    }

    /// The exercise picker's result: one prefilled set for a movement that was
    /// not planned.
    func addExercise(_ exercise: Exercise) {
        exerciseCache[exercise.id] = exercise
        addSet(to: exercise.id)
    }

    /// Finish (spec §6): stamp `finished_at`, success haptic, toast, then pop.
    /// The pop waits for the toast to be seen — it is shown on this screen,
    /// and Today reloads when the stack comes back.
    func finish() {
        do {
            try repository.finishSession(id: sessionId)
            scheduler?.trigger(.afterWrite)
            Haptics.success()
            toast = .success("Session saved")
            loadSession()
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                self?.isGone = true
            }
        } catch {
            Haptics.error()
            toast = .error("Could not save the session.")
        }
    }

    /// Discard: soft-deletes the session and all of its sets, then pops.
    func discard() {
        do {
            try repository.discardSession(id: sessionId)
            scheduler?.trigger(.afterWrite)
            isDiscarding = false
            isGone = true
        } catch {
            toast = .error("Could not discard the session.")
        }
    }

    func beginRename() {
        renameText = session?.notes ?? ""
        isRenaming = true
    }

    /// A session has no name column of its own, so the rename lives in
    /// `notes` — the one free-text field the schema gives it, and one the sync
    /// engine already carries.
    func commitRename() {
        guard var current = session else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        current.notes = trimmed.isEmpty ? nil : trimmed
        do {
            try repository.upsert(current)
            scheduler?.trigger(.afterWrite)
            session = current
            title = Self.title(notes: current.notes, dayName: dayName)
        } catch {
            toast = .error("Could not rename the session.")
        }
    }

    // MARK: - Plumbing

    private func save(_ set: WorkoutSet) {
        do {
            try repository.upsert(set)
            scheduler?.trigger(.afterWrite)
            reloadSets()
        } catch {
            toast = .error("Could not save the set.")
        }
    }

    private func storedSet(_ setId: String) -> WorkoutSet? {
        sets.first(where: { $0.id == setId })
    }

    /// The synchronous half of the observation: the screen's own writes show
    /// up without waiting for the next observation tick.
    private func reloadSets() {
        guard let rows = try? repository.sets(of: sessionId) else { return }
        apply(rows)
    }

    private func apply(_ rows: [WorkoutSet]) {
        sets = rows
        rebuildGroups()
    }

    /// Groups the sets by exercise, keeping the `position` order the day
    /// planned, and renumbers each group from 1 (spec §6).
    private func rebuildGroups() {
        var order: [String] = []
        var byExercise: [String: [WorkoutSet]] = [:]
        for set in sets {
            if byExercise[set.exerciseId] == nil {
                order.append(set.exerciseId)
                byExercise[set.exerciseId] = []
            }
            byExercise[set.exerciseId]?.append(set)
        }

        var built: [SessionExerciseGroup] = []
        for exerciseId in order {
            // Named `found`, not `exercise`: the local would otherwise shadow
            // the `exercise(_:)` lookup it is initialised from.
            guard let found = exercise(exerciseId) else { continue }
            var rows: [SessionSetRow] = []
            var number = 1
            for set in byExercise[exerciseId] ?? [] {
                rows.append(
                    SessionSetRow(
                        id: set.id,
                        number: number,
                        weightKg: set.weightKg,
                        reps: set.reps,
                        rpe: set.rpe,
                        completed: set.completed))
                number += 1
            }
            built.append(
                SessionExerciseGroup(
                    id: exerciseId,
                    name: found.name,
                    muscleLabel: found.muscleGroup.label,
                    muscleGroup: found.muscleGroup.rawValue,
                    art: ExerciseArt(found),
                    lastTime: lastTime(exerciseId),
                    sets: rows))
        }

        groups = built
        art = built.first?.art
    }

    private func exercise(_ exerciseId: String) -> Exercise? {
        if let cached = exerciseCache[exerciseId] {
            return cached
        }
        guard let found = try? repository.exercise(id: exerciseId) else { return nil }
        exerciseCache[exerciseId] = found
        return found
    }

    /// "Last time 57.5 × 8" — the heaviest reference point the user has, taken
    /// from any session but this one.
    ///
    /// The exclusion is done in SQL rather than by filtering the answer: once
    /// the first set of this session is ticked off it becomes *the* last
    /// completed set, and a post-hoc check would leave the caption blank
    /// instead of showing last week's numbers.
    ///
    /// Cached per exercise and never invalidated for the life of the screen:
    /// the value is about sessions that are already over, so only an exercise
    /// added mid-session needs a fresh lookup.
    private func lastTime(_ exerciseId: String) -> String? {
        if let cached = lastTimeCache[exerciseId] {
            return cached
        }
        var text: String?
        let last = try? repository.lastCompletedSet(
            exerciseId: exerciseId,
            excludingSessionId: sessionId)
        if let last {
            text = "Last time \(WeightFormat.plain(last.weightKg)) × \(last.reps)"
        }
        // `updateValue` rather than the subscript: assigning a `String?` into
        // a `[String: String?]` through the subscript is one promotion away
        // from meaning "remove the key".
        lastTimeCache.updateValue(text, forKey: exerciseId)
        return text
    }

    private func programDayName(for dayId: String) -> String? {
        guard let day = try? repository.day(id: dayId) else { return nil }
        return day.name
    }

    private static func title(notes: String?, dayName: String?) -> String {
        if let notes, notes.isEmpty == false {
            return notes
        }
        if let dayName, dayName.isEmpty == false {
            return dayName
        }
        return "Free session"
    }

    private static func newID() -> String {
        UUID().uuidString.lowercased()
    }
}
