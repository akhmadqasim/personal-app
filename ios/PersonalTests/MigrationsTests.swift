import Testing

@testable import Personal

/// The local schema is the API schema plus a few local columns (spec §4).
/// These tests pin that contract: the sync engine reads `seq` and `dirty` on
/// every synced table, and the pull cursor lives in `sync_state`.
struct MigrationsTests {

    @Test func everySyncedTableCarriesTheSyncColumns() throws {
        let database = try AppDatabase.inMemory()
        for table in SyncedTable.allCases {
            let columns = try Migrations.columnNames(of: table.rawValue, in: database)
            for expected in ["id", "updated_at", "deleted_at", "seq", "dirty"] {
                #expect(columns.contains(expected), "\(table.rawValue) is missing \(expected)")
            }
        }
    }

    @Test func exerciseCarriesItsDomainColumns() throws {
        let database = try AppDatabase.inMemory()
        let columns = try Migrations.columnNames(of: "exercise", in: database)
        for expected in ["name", "muscle_group", "equipment", "image_key", "notes"] {
            #expect(columns.contains(expected))
        }
    }

    @Test func programCarriesItsDomainColumns() throws {
        let database = try AppDatabase.inMemory()
        let columns = try Migrations.columnNames(of: "program", in: database)
        for expected in ["name", "is_active"] {
            #expect(columns.contains(expected))
        }
    }

    @Test func programDayCarriesItsDomainColumns() throws {
        let database = try AppDatabase.inMemory()
        let columns = try Migrations.columnNames(of: "program_day", in: database)
        for expected in ["program_id", "name", "position"] {
            #expect(columns.contains(expected))
        }
    }

    @Test func programExerciseCarriesItsDomainColumns() throws {
        let database = try AppDatabase.inMemory()
        let columns = try Migrations.columnNames(of: "program_exercise", in: database)
        for expected in [
            "program_day_id", "exercise_id", "position",
            "target_sets", "target_reps", "target_weight_kg", "rest_seconds",
        ] {
            #expect(columns.contains(expected))
        }
    }

    @Test func workoutSessionCarriesItsDomainColumns() throws {
        let database = try AppDatabase.inMemory()
        let columns = try Migrations.columnNames(of: "workout_session", in: database)
        for expected in ["started_at", "finished_at", "program_day_id", "notes"] {
            #expect(columns.contains(expected))
        }
    }

    @Test func workoutSetCarriesItsDomainColumns() throws {
        let database = try AppDatabase.inMemory()
        let columns = try Migrations.columnNames(of: "workout_set", in: database)
        for expected in [
            "session_id", "exercise_id", "position", "weight_kg", "reps", "rpe", "completed",
        ] {
            #expect(columns.contains(expected))
        }
    }

    @Test func syncStateIsSeeded() throws {
        let database = try AppDatabase.inMemory()
        let state = try Migrations.syncState(in: database)
        #expect(state["since_seq"] == 0)
        #expect(state["last_synced_at"] == 0)
        #expect(state.count == 2)
    }

    @Test func seqIsNullableSoOfflineRowsCanExist() throws {
        // The API declares `seq INTEGER NOT NULL UNIQUE`; locally the server
        // owns that counter, so a row created offline has no `seq` until the
        // first push. This checks the column really accepts NULL, and that two
        // rows can sit there with `seq` unset at the same time.
        let database = try AppDatabase.inMemory()
        for table in SyncedTable.allCases {
            let nullable = try Migrations.nullableColumns(of: table.rawValue, in: database)
            #expect(nullable.contains("seq"), "\(table.rawValue).seq must accept NULL")
            #expect(nullable.contains("deleted_at"), "\(table.rawValue).deleted_at must accept NULL")
        }

        let clock = FixedClock(1_000)
        let repository = GymRepository(dbWriter: database, clock: clock)

        try repository.upsert(
            Exercise(id: "a", name: "A", muscleGroup: .chest, equipment: .barbell))
        try repository.upsert(
            Exercise(id: "b", name: "B", muscleGroup: .back, equipment: .cable))

        let stored = try repository.exercises()
        #expect(stored.count == 2)
        #expect(stored.allSatisfy({ $0.seq == nil }))
    }
}
