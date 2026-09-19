import SwiftUI

/// Picks an exercise out of the catalog (spec §6): a chips row for the muscle
/// group and a search field over the catalog.
///
/// Reads go through ``GymRepository/exercises(muscleGroup:search:)``, which
/// already escapes the search term and filters out soft-deleted rows.
///
/// Two screens use it, and the defaults are the Session screen's: it adds a
/// movement to the running session, so the sheet is "Add exercise", offers "+"
/// to create one on the spot and marks each row with a plus. The Progress tab
/// only chooses the subject of a chart, so it overrides all three.
struct ExercisePickerSheet: View {

    var repository: GymRepository
    var imageStore: ImageStore?
    /// Optional: a movement created from inside the sheet should reach the
    /// server without waiting for the next unrelated write.
    var scheduler: SyncScheduler?
    /// Sheet title — what picking is *for*.
    var title: String
    /// Whether the header offers "+" to create a movement on the spot. A
    /// chart can only be drawn for a movement that already has sets, so
    /// Progress turns it off.
    var allowsCreating: Bool
    /// Trailing glyph of a row, hinting what the tap does.
    var rowSymbol: String
    var onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var muscleGroup: MuscleGroup?
    @State private var results: [Exercise] = []
    @State private var isCreating = false
    @State private var toast: ToastItem?

    init(
        repository: GymRepository,
        imageStore: ImageStore?,
        scheduler: SyncScheduler? = nil,
        title: String = "Add exercise",
        allowsCreating: Bool = true,
        rowSymbol: String = "plus.circle",
        onPick: @escaping (Exercise) -> Void
    ) {
        self.repository = repository
        self.imageStore = imageStore
        self.scheduler = scheduler
        self.title = title
        self.allowsCreating = allowsCreating
        self.rowSymbol = rowSymbol
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
                        emptyView
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
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // Inside the stack, not on it: `searchable` binds to the nearest
            // enclosing navigation container.
            .searchable(text: $search, prompt: "Search exercises")
            .toast($toast)
            .toolbar {
                if allowsCreating {
                    ToolbarItem(placement: .topBarTrailing) {
                        CircleIconButton(systemImage: "plus", accessibilityLabel: "New exercise") {
                            isCreating = true
                        }
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

    /// The same split the catalog makes: an unfiltered empty list means the
    /// catalog has not arrived yet, which no change of filter will fix.
    @ViewBuilder
    private var emptyView: some View {
        if search.isEmpty && muscleGroup == nil {
            EmptyState(
                symbol: "arrow.triangle.2.circlepath",
                title: "No exercises yet",
                message: "The catalog arrives with your first sync. Add your API token in Settings, then sync.",
                action: (title: "Sync now", handler: { scheduler?.trigger(.manual) }))
        } else {
            EmptyState(
                symbol: "magnifyingglass",
                title: "No exercises found",
                message: "Try another muscle group or clear the search.")
        }
    }

    /// One `Equatable` value for `.task(id:)`, so a new filter or search term
    /// restarts the query and nothing else does.
    private var queryKey: String {
        "\(muscleGroup?.rawValue ?? "")|\(search)"
    }

    private func reload() {
        do {
            results = try repository.exercises(muscleGroup: muscleGroup, search: search)
        } catch {
            // Keep the rows that are already on screen: swallowing the error
            // into an empty list reads as "no exercises found", which sends
            // the user looking for a movement that is right there.
            toast = .error("Could not read the exercise catalog.")
        }
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
                Image(systemName: rowSymbol)
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
