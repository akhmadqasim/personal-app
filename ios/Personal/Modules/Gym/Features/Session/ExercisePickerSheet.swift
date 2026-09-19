import SwiftUI

/// Picks an exercise to add to the running session (spec §6): a chips row for
/// the muscle group and a search field over the catalog.
///
/// Reads go through ``GymRepository/exercises(muscleGroup:search:)``, which
/// already escapes the search term and filters out soft-deleted rows.
struct ExercisePickerSheet: View {

    var repository: GymRepository
    var imageStore: ImageStore?
    /// Optional: a movement created from inside the sheet should reach the
    /// server without waiting for the next unrelated write.
    var scheduler: SyncScheduler?
    var onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var muscleGroup: MuscleGroup?
    @State private var results: [Exercise] = []
    @State private var isCreating = false

    init(
        repository: GymRepository,
        imageStore: ImageStore?,
        scheduler: SyncScheduler? = nil,
        onPick: @escaping (Exercise) -> Void
    ) {
        self.repository = repository
        self.imageStore = imageStore
        self.scheduler = scheduler
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    MuscleGroupChips(selection: muscleGroup) { group in
                        muscleGroup = group
                    }
                    if results.isEmpty {
                        EmptyState(
                            symbol: "magnifyingglass",
                            title: "No exercises found",
                            message: "Try another muscle group or clear the search.")
                    } else {
                        ForEach(results) { exercise in
                            row(exercise)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.screenInset)
                .padding(.bottom, Theme.Spacing.xxxl)
            }
            .background(Theme.Colors.canvas)
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            // Inside the stack, not on it: `searchable` binds to the nearest
            // enclosing navigation container.
            .searchable(text: $search, prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CircleIconButton(systemImage: "plus", accessibilityLabel: "New exercise") {
                        isCreating = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close") {
                        dismiss()
                    }
                }
            }
            // A movement that is not in the catalog yet: add it here and it
            // appears in the list below, ready to be picked.
            .sheet(isPresented: $isCreating) {
                ExerciseEditorView(
                    repository: repository,
                    scheduler: scheduler,
                    onSaved: { _ in
                        reload()
                    })
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(Theme.Radius.sheet)
        .task(id: queryKey) {
            reload()
        }
    }

    /// One `Equatable` value for `.task(id:)`, so a new filter or search term
    /// restarts the query and nothing else does.
    private var queryKey: String {
        "\(muscleGroup?.rawValue ?? "")|\(search)"
    }

    private func reload() {
        results = (try? repository.exercises(muscleGroup: muscleGroup, search: search)) ?? []
    }

    // MARK: - Pieces

    private func row(_ exercise: Exercise) -> some View {
        Button {
            onPick(exercise)
            dismiss()
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                ExerciseArtView(art: ExerciseArt(exercise), size: 44, store: imageStore)
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(exercise.name)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(exercise.equipment.label) · \(exercise.muscleGroup.label)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer(minLength: Theme.Spacing.sm)
                Image(systemName: "plus.circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .frame(minHeight: Theme.Spacing.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview {
    ExercisePickerSheet(
        repository: AppEnvironment.preview().repository,
        imageStore: nil,
        onPick: { _ in })
}
