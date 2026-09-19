import SwiftUI

/// Picks an exercise to add to the running session (spec §6): a chips row for
/// the muscle group and a search field over the catalog.
///
/// Reads go through ``GymRepository/exercises(muscleGroup:search:)``, which
/// already escapes the search term and filters out soft-deleted rows.
struct ExercisePickerSheet: View {

    var repository: GymRepository
    var imageStore: ImageStore?
    var onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var search = ""
    @State private var muscleGroup: MuscleGroup?
    @State private var results: [Exercise] = []

    init(
        repository: GymRepository,
        imageStore: ImageStore?,
        onPick: @escaping (Exercise) -> Void
    ) {
        self.repository = repository
        self.imageStore = imageStore
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    chips
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
                    CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close") {
                        dismiss()
                    }
                }
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

    private var chips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.sm) {
                chip(label: "All", isSelected: muscleGroup == nil) {
                    muscleGroup = nil
                }
                ForEach(MuscleGroup.allCases) { group in
                    chip(label: group.label, isSelected: muscleGroup == group) {
                        muscleGroup = group
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
        .scrollIndicators(.hidden)
    }

    /// Design §3 "Chips": 36 pt capsule, `surface` fill with a hairline
    /// border, `secondary` label. Selected flips to the `ink` fill with the
    /// inverse label — `canvas` is the inverse of `ink` in both schemes.
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
