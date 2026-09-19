import Foundation
import Observation

/// One planned exercise inside a day (spec §6).
nonisolated struct DayExerciseRow: Identifiable, Equatable, Sendable {

    /// The `program_exercise` id — the row the target editor writes back to.
    var id: String
    var exerciseId: String
    var name: String
    var art: ExerciseArt
    var targetSets: Int
    var targetReps: Int
    var targetWeightKg: Double?
    var restSeconds: Int?

    /// "3 × 10 · 60 kg · 90 s". Weight and rest are dropped when the plan does
    /// not set them — a session then prefills from the last completed set and
    /// the app-wide default rest.
    var detail: String {
        var parts: [String] = ["\(targetSets) × \(targetReps)"]
        if let targetWeightKg {
            parts.append("\(WeightFormat.plain(targetWeightKg)) kg")
        }
        if let restSeconds {
            parts.append("\(restSeconds) s")
        }
        return parts.joined(separator: " · ")
    }
}

/// Drives the day editor: the planned exercises, their order and their
/// targets (spec §6).
///
/// It never touches `workout_set`. The picker it shares with the Session
/// screen only hands back an ``Exercise``; what that means — a plan row here,
/// a set there — is the caller's decision.
@Observable
@MainActor
final class DayEditorViewModel {

    /// What a freshly added exercise plans, before the user opens the target
    /// editor: three sets of ten (spec §6) at the app-wide default rest.
    static let defaultTargetSets = 3
    static let defaultTargetReps = 10
    static let defaultRestSeconds = 90

    /// Ceilings the target editor enforces; repeated here as the last line of
    /// defence (spec §8).
    static let maxTargetSets = 10
    static let maxTargetReps = 50
    static let maxRestSeconds = 300

    let dayId: String
    let imageStore: ImageStore?

    private(set) var name = ""
    private(set) var rows: [DayExerciseRow] = []
    /// Set when the day is gone; the screen pops.
    private(set) var isGone = false

    var toast: ToastItem?
    var isPickingExercise = false
    /// Non-nil while the target editor sheet is up.
    var editingRow: DayExerciseRow?
    var isRenaming = false
    var renameText = ""

    private let repository: GymRepository
    private let scheduler: SyncScheduler?

    /// The records behind ``rows``, in the same order and the same length.
    private var records: [ProgramExercise] = []

    init(
        dayId: String,
        repository: GymRepository,
        scheduler: SyncScheduler? = nil,
        imageStore: ImageStore? = nil
    ) {
        self.dayId = dayId
        self.repository = repository
        self.scheduler = scheduler
        self.imageStore = imageStore
    }

    // MARK: - Reading

    func reload() {
        do {
            guard let day = try repository.day(id: dayId) else {
                isGone = true
                return
            }
            name = day.name

            // A plan row whose exercise was deleted is dropped from both
            // arrays together, so the indices `.onMove` and `.onDelete` hand
            // back keep pointing at the right record.
            var keptRecords: [ProgramExercise] = []
            var built: [DayExerciseRow] = []
            for planned in try repository.programExercises(of: dayId) {
                guard let exercise = try repository.exercise(id: planned.exerciseId) else {
                    continue
                }
                keptRecords.append(planned)
                built.append(
                    DayExerciseRow(
                        id: planned.id,
                        exerciseId: planned.exerciseId,
                        name: exercise.name,
                        art: ExerciseArt(exercise),
                        targetSets: planned.targetSets,
                        targetReps: planned.targetReps,
                        targetWeightKg: planned.targetWeightKg,
                        restSeconds: planned.restSeconds))
            }
            records = keptRecords
            rows = built
        } catch {
            toast = .error("Could not read the local database.")
        }
    }

    // MARK: - Writing

    /// The picker's result: one planned exercise at the end of the day.
    @discardableResult
    func addExercise(_ exercise: Exercise) -> String? {
        let planned = ProgramExercise(
            id: Self.newID(),
            programDayId: dayId,
            exerciseId: exercise.id,
            position: records.count,
            targetSets: Self.defaultTargetSets,
            targetReps: Self.defaultTargetReps,
            targetWeightKg: nil,
            restSeconds: Self.defaultRestSeconds)
        do {
            try repository.upsert(planned)
            scheduler?.trigger(.afterWrite)
            reload()
            return planned.id
        } catch {
            toast = .error("Could not add the exercise.")
            return nil
        }
    }

    /// Saves the target editor. The sheet already constrains its inputs; the
    /// clamps here are what keep an invalid row out of the database (spec §8).
    func updateTargets(
        _ rowId: String,
        sets: Int,
        reps: Int,
        weightKg: Double?,
        restSeconds: Int?
    ) {
        guard var planned = records.first(where: { $0.id == rowId }) else { return }
        planned.targetSets = min(Self.maxTargetSets, max(1, sets))
        planned.targetReps = min(Self.maxTargetReps, max(1, reps))
        planned.targetWeightKg = weightKg.map { max(0, $0) }
        planned.restSeconds = restSeconds.map { min(Self.maxRestSeconds, max(0, $0)) }
        do {
            try repository.upsert(planned)
            scheduler?.trigger(.afterWrite)
            reload()
        } catch {
            toast = .error("Could not save the targets.")
        }
    }

    /// The `List`'s `.onMove`, same rule as the days: renumber from zero,
    /// write back only what moved.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = records
        reordered.move(fromOffsets: source, toOffset: destination)
        do {
            for index in reordered.indices {
                var planned = reordered[index]
                guard planned.position != index else { continue }
                planned.position = index
                try repository.upsert(planned)
            }
            scheduler?.trigger(.afterWrite)
            reload()
        } catch {
            toast = .error("Could not reorder the exercises.")
        }
    }

    /// The swipe: soft delete, so the tombstone reaches the server.
    func delete(at offsets: IndexSet) {
        do {
            for index in offsets {
                guard index >= 0, index < records.count else { continue }
                try repository.softDelete(.programExercise, id: records[index].id)
            }
            scheduler?.trigger(.afterWrite)
            reload()
        } catch {
            toast = .error("Could not remove the exercise.")
        }
    }

    func beginRename() {
        renameText = name
        isRenaming = true
    }

    func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        do {
            guard var day = try repository.day(id: dayId) else {
                isGone = true
                return
            }
            day.name = trimmed
            try repository.upsert(day)
            scheduler?.trigger(.afterWrite)
            reload()
        } catch {
            toast = .error("Could not rename the day.")
        }
    }

    private static func newID() -> String {
        UUID().uuidString.lowercased()
    }
}
