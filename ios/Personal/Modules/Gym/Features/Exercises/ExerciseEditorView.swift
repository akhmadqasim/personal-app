import SwiftUI

/// The exercise editor sheet (spec §6): name, muscle group, equipment, notes.
///
/// The photo does not live here but on the detail page, next to the art it
/// replaces — and because uploading needs the network, which a form field
/// should not silently depend on.
struct ExerciseEditorView: View {

    @State private var model: ExerciseEditorViewModel

    /// The id of the row that was written; the caller reloads or picks it.
    var onSaved: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool

    init(
        repository: GymRepository,
        scheduler: SyncScheduler? = nil,
        exerciseId: String? = nil,
        onSaved: @escaping (String) -> Void = { _ in }
    ) {
        _model = State(
            initialValue: ExerciseEditorViewModel(
                exerciseId: exerciseId,
                repository: repository,
                scheduler: scheduler))
        self.onSaved = onSaved
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                SheetHeader(
                    symbol: "square.and.pencil",
                    title: model.title,
                    subtitle: "Built-in movements can be edited too — your version wins.",
                    onClose: { dismiss() })

                GroupCard {
                    nameField
                }

                GroupCard {
                    musclePicker
                    Divider().overlay(Theme.Colors.hairline)
                    equipmentPicker
                }

                GroupCard {
                    notesField
                }

                PillButton(style: .primary, title: "Save", systemImage: "checkmark") {
                    save()
                }
                .disabled(model.canSave == false)

                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.cardPadding)
        }
        .background(Theme.Colors.canvas)
        .presentationDetents([.large])
        .presentationCornerRadius(Theme.Radius.sheet)
        .toast($model.toast)
        .task {
            model.load()
            if model.isNew {
                isNameFocused = true
            }
        }
    }

    // MARK: - Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            fieldLabel("Name")
            TextField("Barbell Bench Press", text: $model.name)
                .font(Theme.Typography.body)
                .textInputAutocapitalization(.words)
                .focused($isNameFocused)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(minHeight: Theme.Spacing.rowMinHeight)
                .background(
                    Theme.Colors.surfaceSecondary,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
        }
    }

    private var musclePicker: some View {
        Picker(selection: $model.muscleGroup) {
            ForEach(MuscleGroup.allCases) { group in
                Text(group.label).tag(group)
            }
        } label: {
            Text("Muscle group")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .pickerStyle(.menu)
        .tint(Theme.Colors.textSecondary)
        .frame(minHeight: Theme.Spacing.rowMinHeight)
    }

    private var equipmentPicker: some View {
        Picker(selection: $model.equipment) {
            ForEach(Equipment.allCases) { item in
                Text(item.label).tag(item)
            }
        } label: {
            Text("Equipment")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .pickerStyle(.menu)
        .tint(Theme.Colors.textSecondary)
        .frame(minHeight: Theme.Spacing.rowMinHeight)
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            fieldLabel("Notes")
            TextField("Cues, setup, anything worth remembering", text: $model.notes, axis: .vertical)
                .font(Theme.Typography.body)
                .lineLimit(3 ... 6)
                .padding(Theme.Spacing.md)
                .frame(minHeight: Theme.Spacing.rowMinHeight, alignment: .topLeading)
                .background(
                    Theme.Colors.surfaceSecondary,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textTertiary)
    }

    private func save() {
        guard let savedId = model.save() else { return }
        Haptics.success()
        dismiss()
        onSaved(savedId)
    }
}

// MARK: - Previews

#Preview("Light") {
    ExerciseEditorView(repository: AppEnvironment.preview().repository)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ExerciseEditorView(repository: AppEnvironment.preview().repository)
        .preferredColorScheme(.dark)
}
