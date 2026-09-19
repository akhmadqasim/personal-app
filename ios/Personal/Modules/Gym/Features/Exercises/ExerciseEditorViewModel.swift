import Foundation
import Observation

/// Drives the exercise editor, new and existing alike (spec §6).
///
/// A built-in row is edited exactly like a user-created one: the sync engine
/// resolves the collision with last-write-wins, so the user's edit beats the
/// seed it came from.
@Observable
@MainActor
final class ExerciseEditorViewModel {

    /// `nil` for a new exercise.
    let exerciseId: String?

    var name = ""
    var muscleGroup: MuscleGroup = .other
    var equipment: Equipment = .other
    var notes = ""
    var toast: ToastItem?

    private let repository: GymRepository
    private let scheduler: SyncScheduler?

    init(
        exerciseId: String? = nil,
        repository: GymRepository,
        scheduler: SyncScheduler? = nil
    ) {
        self.exerciseId = exerciseId
        self.repository = repository
        self.scheduler = scheduler
    }

    var isNew: Bool {
        exerciseId == nil
    }

    var title: String {
        isNew ? "New exercise" : "Edit exercise"
    }

    /// Spec §8: names are trimmed non-empty, so the CTA is dead until there
    /// is one.
    var canSave: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// Fills the fields from the stored row. A no-op for a new exercise.
    func load() {
        guard let exerciseId else { return }
        guard let found = try? repository.exercise(id: exerciseId) else { return }
        name = found.name
        muscleGroup = found.muscleGroup
        equipment = found.equipment
        notes = found.notes ?? ""
    }

    /// Writes the row and answers its id, so the caller can push the detail or
    /// pick the exercise it just made. `nil` means nothing was written.
    ///
    /// Editing reads the stored row first rather than rebuilding it: that is
    /// what keeps `image_key` — which this screen does not show — from being
    /// wiped by a rename.
    @discardableResult
    func save() -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            var record: Exercise
            if let exerciseId, let existing = try repository.exercise(id: exerciseId) {
                record = existing
            } else {
                record = Exercise(
                    id: exerciseId ?? Self.newID(),
                    name: trimmed,
                    muscleGroup: muscleGroup,
                    equipment: equipment)
            }
            record.name = trimmed
            record.muscleGroup = muscleGroup
            record.equipment = equipment
            record.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            try repository.upsert(record)
            scheduler?.trigger(.afterWrite)
            return record.id
        } catch {
            toast = .error("Could not save the exercise.")
            return nil
        }
    }

    private static func newID() -> String {
        UUID().uuidString.lowercased()
    }
}
