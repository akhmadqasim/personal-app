import SwiftUI

/// One program day (spec §6): the planned exercises with their targets,
/// reorderable, swipe-deletable, plus "+ Add exercise".
///
/// The picker it opens is the one the Session screen uses. It only hands back
/// an ``Exercise``; here that becomes a `program_exercise` row, never a
/// `workout_set`.
struct DayEditorView: View {

    private let environment: AppEnvironment

    @State private var model: DayEditorViewModel
    @State private var editMode: EditMode = .inactive
    @Environment(\.dismiss) private var dismiss

    init(environment: AppEnvironment, dayId: String) {
        self.environment = environment
        _model = State(
            initialValue: DayEditorViewModel(
                dayId: dayId,
                repository: environment.repository,
                scheduler: environment.syncScheduler,
                imageStore: environment.imageStore))
    }

    var body: some View {
        List {
            headerSection
            exercisesSection
            addExerciseSection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.canvas)
        .environment(\.editMode, $editMode)
        .navigationTitle(model.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CircleIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                CircleIconButton(
                    systemImage: editMode.isEditing ? "checkmark" : "arrow.up.arrow.down",
                    accessibilityLabel: editMode.isEditing
                        ? "Done reordering"
                        : "Reorder exercises"
                ) {
                    withAnimation(.snappy(duration: 0.25)) {
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                }
                .disabled(model.rows.isEmpty)
            }
        }
        .toast($model.toast)
        .task {
            model.reload()
        }
        // Same reason as ``ProgramDetailView``: the tab's stack owns the path,
        // so a dismissed sheet or a pop back lands here as `onAppear`.
        .onAppear {
            model.reload()
        }
        .onChange(of: model.isGone) { _, isGone in
            if isGone {
                dismiss()
            }
        }
        .sheet(isPresented: $model.isPickingExercise) {
            ExercisePickerSheet(
                repository: environment.repository,
                imageStore: model.imageStore,
                scheduler: environment.syncScheduler,
                onPick: { exercise in
                    model.addExercise(exercise)
                })
        }
        .sheet(item: $model.editingRow) { row in
            TargetEditorSheet(
                row: row,
                onSave: { sets, reps, weightKg, restSeconds in
                    model.updateTargets(
                        row.id,
                        sets: sets,
                        reps: reps,
                        weightKg: weightKg,
                        restSeconds: restSeconds)
                })
        }
        .alert("Rename day", isPresented: $model.isRenaming) {
            TextField("Name", text: $model.renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                model.commitRename()
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            GroupCard {
                Text(model.name)
                    .font(Theme.Typography.section)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                Text(summary)
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
                PillButton(style: .secondary, title: "Rename day", systemImage: "pencil") {
                    model.beginRename()
                }
            }
            .plainListRow()
        }
    }

    private var summary: String {
        let count = model.rows.count
        if count == 0 {
            return "No exercises yet"
        }
        let noun = count == 1 ? "exercise" : "exercises"
        return "\(count) \(noun) · tap one to change its targets"
    }

    @ViewBuilder
    private var exercisesSection: some View {
        if model.rows.isEmpty {
            Section {
                EmptyState(
                    symbol: "dumbbell",
                    title: "No exercises yet",
                    message: "Add the movements you train on this day and set their targets.",
                    action: (title: "Add exercise", handler: { model.isPickingExercise = true }))
                    .plainListRow()
            }
        } else {
            Section {
                ForEach(model.rows) { row in
                    Button {
                        model.editingRow = row
                    } label: {
                        exerciseRow(row)
                    }
                    .buttonStyle(.plain)
                    .plainListRow()
                }
                .onMove { source, destination in
                    model.move(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    model.delete(at: offsets)
                }
            } header: {
                sectionLabel("Exercises")
            }
        }
    }

    private var addExerciseSection: some View {
        Section {
            PillButton(style: .secondary, title: "Add exercise", systemImage: "plus") {
                model.isPickingExercise = true
            }
            .plainListRow()
        }
    }

    // MARK: - Pieces

    private func exerciseRow(_ row: DayExerciseRow) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            ExerciseArtView(art: row.art, size: 44, store: model.imageStore)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(row.name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(row.detail)
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.sm)
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(minHeight: Theme.Spacing.rowMinHeight)
        .contentShape(Rectangle())
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textTertiary)
            .textCase(nil)
            .padding(.horizontal, Theme.Spacing.screenInset)
            .padding(.top, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        DayEditorView(environment: AppEnvironment.preview(), dayId: "preview")
    }
}
