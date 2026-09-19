import SwiftUI

/// The exercise catalog (spec §6, design §4): a muscle-group chip row, a
/// search field and rows drawn on the muscle-group `Soft` tile — or the user's
/// own photo once there is one.
///
/// Pushed from the Programs toolbar, so it lives inside that tab's navigation
/// stack and can push ``ExerciseDetailView`` with a plain `NavigationLink`.
struct ExerciseListView: View {

    private let environment: AppEnvironment

    @State private var model: ExerciseListViewModel
    @Environment(\.dismiss) private var dismiss

    init(environment: AppEnvironment) {
        self.environment = environment
        _model = State(
            initialValue: ExerciseListViewModel(
                repository: environment.repository,
                imageStore: environment.imageStore))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                MuscleGroupChips(selection: model.muscleGroup) { group in
                    model.select(group)
                }
                list
            }
            .padding(.horizontal, Theme.Spacing.screenInset)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .background(Theme.Colors.canvas)
        .navigationTitle("Exercises")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .searchable(text: $model.search, prompt: "Search exercises")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CircleIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                CircleIconButton(systemImage: "plus", accessibilityLabel: "New exercise") {
                    model.isCreating = true
                }
            }
        }
        .toast($model.toast)
        .task(id: model.queryKey) {
            model.reload()
        }
        .sheet(isPresented: $model.isCreating) {
            ExerciseEditorView(
                repository: environment.repository,
                scheduler: environment.syncScheduler,
                onSaved: { _ in
                    model.reload()
                })
        }
    }

    @ViewBuilder
    private var list: some View {
        if model.rows.isEmpty {
            EmptyState(
                symbol: "magnifyingglass",
                title: "No exercises found",
                message: "Try another muscle group, clear the search, or add the movement yourself.",
                action: (title: "New exercise", handler: { model.isCreating = true }))
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.rowSpacing) {
                ForEach(model.rows) { row in
                    NavigationLink(value: ProgramsRoute.exercise(row.id)) {
                        exerciseRow(row)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func exerciseRow(_ row: ExerciseRow) -> some View {
        ThumbnailRow(
            thumbnail: { ExerciseArtView(art: row.art, size: 72, store: model.imageStore) },
            title: row.name,
            meta: [("dumbbell", row.meta)])
    }
}

// MARK: - Chips

/// The muscle-group filter row (design §3 "Chips"), "All" first.
///
/// Shared by the catalog and the picker sheet so the two cannot drift apart.
struct MuscleGroupChips: View {

    var selection: MuscleGroup?
    var onSelect: (MuscleGroup?) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.sm) {
                chip(label: "All", isSelected: selection == nil) {
                    onSelect(nil)
                }
                ForEach(MuscleGroup.allCases) { group in
                    chip(label: group.label, isSelected: selection == group) {
                        onSelect(group)
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
        .scrollIndicators(.hidden)
    }

    /// 36 pt capsule, `surface` fill with a hairline border, `secondary`
    /// label. Selected flips to the `ink` fill with the inverse label —
    /// `canvas` is the inverse of `ink` in both schemes.
    private func chip(
        label: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            Haptics.selection()
        } label: {
            Text(label)
                .font(Theme.Typography.secondary)
                .foregroundStyle(isSelected ? Theme.Colors.canvas : Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(minHeight: 36)
                .background(isSelected ? Theme.Colors.ink : Theme.Colors.surface, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Theme.Colors.hairline, lineWidth: isSelected ? 0 : 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
}

// MARK: - Previews

#Preview("Light") {
    NavigationStack {
        ExerciseListView(environment: AppEnvironment.preview())
    }
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack {
        ExerciseListView(environment: AppEnvironment.preview())
    }
    .preferredColorScheme(.dark)
}
