import Foundation
import Observation

/// One program in the Programs list (spec §6).
nonisolated struct ProgramRow: Identifiable, Equatable, Sendable {

    var id: String
    var name: String
    /// The one program Today reads from; at most one row carries it.
    var isActive: Bool
    var dayCount: Int
    var exerciseCount: Int
    /// Art of the first exercise of the first day; `nil` for an empty program.
    var art: ExerciseArt?

    /// "3 days · 18 exercises".
    var meta: String {
        let dayNoun = dayCount == 1 ? "day" : "days"
        let exerciseNoun = exerciseCount == 1 ? "exercise" : "exercises"
        return "\(dayCount) \(dayNoun) · \(exerciseCount) \(exerciseNoun)"
    }
}

/// Drives the Programs tab root.
///
/// Observation strategy, as on Today: a synchronous reload on `.task`, after
/// every write and whenever the navigation stack pops. The screen summarises
/// three tables at once and a `ValueObservation` wide enough to cover them
/// would refire on every set logged in a session.
@Observable
@MainActor
final class ProgramsViewModel {

    private(set) var programs: [ProgramRow] = []

    var toast: ToastItem?
    /// Drives the "new program" sheet.
    var isCreating = false
    var newName = ""
    /// The row whose slide-to-confirm deletion sheet is up.
    var pendingDeletion: ProgramRow?

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

    func reload() {
        do {
            programs = try loadRows()
        } catch {
            toast = .error("Could not read the local database.")
        }
    }

    private func loadRows() throws -> [ProgramRow] {
        var rows: [ProgramRow] = []
        for program in try repository.programs() {
            let days = try repository.days(of: program.id)
            var exerciseCount = 0
            var art: ExerciseArt?
            for day in days {
                let planned = try repository.programExercises(of: day.id)
                exerciseCount += planned.count
                if art == nil, let first = planned.first {
                    if let exercise = try repository.exercise(id: first.exerciseId) {
                        art = ExerciseArt(exercise)
                    }
                }
            }
            rows.append(
                ProgramRow(
                    id: program.id,
                    name: program.name,
                    isActive: program.isActive,
                    dayCount: days.count,
                    exerciseCount: exerciseCount,
                    art: art))
        }
        return rows
    }

    // MARK: - Writing

    /// Creates a program and answers its id, so the screen can push straight
    /// into its detail. The very first program becomes active by itself —
    /// that rule lives in ``GymRepository/createProgram(name:)``.
    ///
    /// An empty or blank name is refused here rather than saved and shown as
    /// an unnamed row (spec §8: names trimmed non-empty).
    @discardableResult
    func createProgram(name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        do {
            let program = try repository.createProgram(name: trimmed)
            scheduler?.trigger(.afterWrite)
            newName = ""
            isCreating = false
            reload()
            return program.id
        } catch {
            toast = .error("Could not create the program.")
            return nil
        }
    }

    func makeActive(_ programId: String) {
        do {
            try repository.setActiveProgram(id: programId)
            scheduler?.trigger(.afterWrite)
            Haptics.selection()
            reload()
        } catch {
            toast = .error("Could not change the active program.")
        }
    }

    /// Soft delete, so the tombstone reaches the server (spec §5). The days
    /// underneath keep their rows: nothing reads a day whose program is gone,
    /// and cascading tombstones is the server's job, not a screen's.
    ///
    /// Deleting the *active* program hands the flag on rather than leaving the
    /// app with none: Today would otherwise fall back to "No program yet" and
    /// invite the user to build a second one they already have.
    func delete(_ programId: String) {
        do {
            let wasActive = try repository.program(id: programId)?.isActive ?? false
            try repository.softDelete(.program, id: programId)
            if wasActive {
                if let successor = try mostRecentlyUpdatedProgram() {
                    try repository.setActiveProgram(id: successor.id)
                }
            }
            scheduler?.trigger(.afterWrite)
            pendingDeletion = nil
            reload()
            toast = .success("Program deleted")
        } catch {
            toast = .error("Could not delete the program.")
        }
    }

    /// The live program the user touched last — the best guess at the one they
    /// meant to keep training. `nil` when the deleted program was the only one,
    /// which correctly leaves the app with no active program at all.
    private func mostRecentlyUpdatedProgram() throws -> Program? {
        var newest: Program?
        for candidate in try repository.programs() {
            guard let current = newest else {
                newest = candidate
                continue
            }
            if candidate.updatedAt > current.updatedAt {
                newest = candidate
            }
        }
        return newest
    }
}
