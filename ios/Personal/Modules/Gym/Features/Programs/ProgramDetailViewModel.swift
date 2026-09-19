import Foundation
import Observation

/// One day card on the program detail screen.
nonisolated struct ProgramDayRow: Identifiable, Equatable, Sendable {

    var id: String
    var name: String
    var exerciseCount: Int

    /// "5 exercises".
    var meta: String {
        let noun = exerciseCount == 1 ? "exercise" : "exercises"
        return "\(exerciseCount) \(noun)"
    }
}

/// Drives one program's detail screen: its days, their order and the "Make
/// active" switch (spec §6).
@Observable
@MainActor
final class ProgramDetailViewModel {

    let programId: String

    private(set) var name = ""
    private(set) var isActive = false
    private(set) var days: [ProgramDayRow] = []
    /// Set when the program is gone — deleted here or on another device; the
    /// screen pops.
    private(set) var isGone = false

    var toast: ToastItem?
    var isAddingDay = false
    var newDayName = ""
    var isRenaming = false
    var renameText = ""

    private let repository: GymRepository
    private let scheduler: SyncScheduler?

    /// The records behind ``days``, in the same order — reordering and
    /// deleting work on indices the `List` hands back.
    private var records: [ProgramDay] = []

    init(
        programId: String,
        repository: GymRepository,
        scheduler: SyncScheduler? = nil
    ) {
        self.programId = programId
        self.repository = repository
        self.scheduler = scheduler
    }

    // MARK: - Reading

    func reload() {
        do {
            guard let program = try repository.program(id: programId) else {
                isGone = true
                return
            }
            name = program.name
            isActive = program.isActive
            records = try repository.days(of: programId)
            var built: [ProgramDayRow] = []
            for day in records {
                let planned = try repository.programExercises(of: day.id)
                built.append(
                    ProgramDayRow(id: day.id, name: day.name, exerciseCount: planned.count))
            }
            days = built
        } catch {
            toast = .error("Could not read the local database.")
        }
    }

    // MARK: - Writing

    /// Appends a day at the end of the program.
    @discardableResult
    func addDay(name dayName: String) -> String? {
        let trimmed = dayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let day = ProgramDay(
            id: Self.newID(),
            programId: programId,
            name: trimmed,
            position: records.count)
        do {
            try repository.upsert(day)
            scheduler?.trigger(.afterWrite)
            newDayName = ""
            isAddingDay = false
            reload()
            return day.id
        } catch {
            toast = .error("Could not add the day.")
            return nil
        }
    }

    /// The `List`'s `.onMove`: renumbers `position` from zero and writes back
    /// only the days that actually moved, so a no-op drag does not dirty every
    /// row for the sync engine.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = records
        reordered.move(fromOffsets: source, toOffset: destination)
        do {
            for index in reordered.indices {
                var day = reordered[index]
                guard day.position != index else { continue }
                day.position = index
                try repository.upsert(day)
            }
            scheduler?.trigger(.afterWrite)
            reload()
        } catch {
            toast = .error("Could not reorder the days.")
        }
    }

    /// The `List`'s `.onDelete`, i.e. the swipe. Soft delete (spec §5).
    func delete(at offsets: IndexSet) {
        do {
            for index in offsets {
                guard index >= 0, index < records.count else { continue }
                try repository.softDelete(.programDay, id: records[index].id)
            }
            scheduler?.trigger(.afterWrite)
            reload()
        } catch {
            toast = .error("Could not delete the day.")
        }
    }

    func makeActive() {
        do {
            try repository.setActiveProgram(id: programId)
            scheduler?.trigger(.afterWrite)
            Haptics.selection()
            reload()
        } catch {
            toast = .error("Could not change the active program.")
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
            guard var program = try repository.program(id: programId) else {
                isGone = true
                return
            }
            program.name = trimmed
            try repository.upsert(program)
            scheduler?.trigger(.afterWrite)
            reload()
        } catch {
            toast = .error("Could not rename the program.")
        }
    }

    private static func newID() -> String {
        UUID().uuidString.lowercased()
    }
}
