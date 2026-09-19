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

/// Why the catalog has nothing to show.
///
/// The two cases read very differently to a new user: an unfiltered empty list
/// means the catalog has never arrived, and telling that user to "try another
/// muscle group" sends them looking for movements that are not on the device
/// at all.
nonisolated enum ExerciseListEmptyState: Equatable, Sendable {
    /// No rows, no chip, no search term: the first sync has not landed yet.
    case needsSync
    /// A chip or a search term hid everything the catalog does hold.
    case noMatches
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
    /// Optional: the "Sync now" button of the first-run empty state. Previews
    /// and most tests build the model without one.
    private let scheduler: SyncScheduler?

    init(
        repository: GymRepository,
        imageStore: ImageStore? = nil,
        scheduler: SyncScheduler? = nil
    ) {
        self.repository = repository
        self.imageStore = imageStore
        self.scheduler = scheduler
    }

    /// `nil` when there are rows to show.
    var emptyState: ExerciseListEmptyState? {
        guard rows.isEmpty else { return nil }
        if search.isEmpty && muscleGroup == nil {
            return .needsSync
        }
        return .noMatches
    }

    /// The empty state's call to action: ask for a sync right now.
    func syncNow() {
        scheduler?.trigger(.manual)
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
