import Foundation
import Observation

/// One catalog row (spec §6, design §4).
nonisolated struct ExerciseRow: Identifiable, Equatable, Sendable {

    var id: String
    var name: String
    var muscleLabel: String
    var equipmentLabel: String
    /// The raw `muscle_group` column value, for `Theme.accent(for:)`.
    var muscleGroup: String
    var art: ExerciseArt

    /// "Barbell · Chest".
    var meta: String {
        "\(equipmentLabel) · \(muscleLabel)"
    }
}

/// Drives the exercise catalog: a muscle-group chip row over a search field.
///
/// Both filters go into one repository query, which already escapes the search
/// term and hides soft-deleted rows. The screen restarts the query through
/// `.task(id: model.queryKey)`, the same way ``ExercisePickerSheet`` does.
@Observable
@MainActor
final class ExerciseListViewModel {

    /// `nil` is the "All" chip.
    var muscleGroup: MuscleGroup?
    var search = ""

    private(set) var rows: [ExerciseRow] = []

    var toast: ToastItem?
    /// Drives the "+" editor sheet.
    var isCreating = false

    let imageStore: ImageStore?

    private let repository: GymRepository

    init(repository: GymRepository, imageStore: ImageStore? = nil) {
        self.repository = repository
        self.imageStore = imageStore
    }

    /// One `Equatable` value for `.task(id:)`: a new chip or a new search term
    /// restarts the query and nothing else does.
    var queryKey: String {
        "\(muscleGroup?.rawValue ?? "")|\(search)"
    }

    func reload() {
        do {
            var built: [ExerciseRow] = []
            for exercise in try repository.exercises(muscleGroup: muscleGroup, search: search) {
                built.append(
                    ExerciseRow(
                        id: exercise.id,
                        name: exercise.name,
                        muscleLabel: exercise.muscleGroup.label,
                        equipmentLabel: exercise.equipment.label,
                        muscleGroup: exercise.muscleGroup.rawValue,
                        art: ExerciseArt(exercise)))
            }
            rows = built
        } catch {
            toast = .error("Could not read the catalog.")
        }
    }

    /// Taps on a chip. Reloading here rather than in a `didSet` keeps the
    /// property a plain observable value.
    func select(_ group: MuscleGroup?) {
        muscleGroup = group
        reload()
    }
}
