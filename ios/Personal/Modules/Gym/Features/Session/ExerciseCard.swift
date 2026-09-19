import SwiftUI

/// One exercise of the session (design §4): a 40 pt art tile, the name, the
/// muscle chip and the "Last time" caption, then the set rows and "+ Add set".
struct ExerciseCard: View {

    var group: SessionExerciseGroup
    var imageStore: ImageStore?
    var onToggle: (SessionSetRow) -> Void
    var onEdit: (SessionSetRow) -> Void
    var onDelete: (SessionSetRow) -> Void
    var onAddSet: () -> Void

    init(
        group: SessionExerciseGroup,
        imageStore: ImageStore?,
        onToggle: @escaping (SessionSetRow) -> Void,
        onEdit: @escaping (SessionSetRow) -> Void,
        onDelete: @escaping (SessionSetRow) -> Void,
        onAddSet: @escaping () -> Void
    ) {
        self.group = group
        self.imageStore = imageStore
        self.onToggle = onToggle
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onAddSet = onAddSet
    }

    var body: some View {
        GroupCard {
            header
            ForEach(group.sets) { row in
                SetRow(
                    row: row,
                    onToggle: { onToggle(row) },
                    onEdit: { onEdit(row) },
                    onDelete: { onDelete(row) })
            }
            addSetButton
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                ExerciseArtView(art: group.art, size: 40, store: imageStore)
                Text(group.name)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                Spacer(minLength: Theme.Spacing.sm)
                muscleChip
            }
            if let lastTime = group.lastTime {
                Text(lastTime)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var muscleChip: some View {
        Text(group.muscleLabel)
            .font(Theme.Typography.pill)
            .foregroundStyle(Theme.accent(for: group.muscleGroup))
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.soft(for: group.muscleGroup), in: Capsule())
    }

    private var addSetButton: some View {
        Button(action: onAddSet) {
            Label("Add set", systemImage: "plus")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Colors.link)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.sm)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

private struct ExerciseCardGallery: View {
    private let group = SessionExerciseGroup(
        id: "e1",
        name: "Barbell Bench Press",
        muscleLabel: "Chest",
        muscleGroup: "chest",
        art: ExerciseArt(imageKey: nil, muscleGroup: "chest", equipment: .barbell),
        lastTime: "Last time 57.5 × 8",
        sets: [
            SessionSetRow(id: "1", number: 1, weightKg: 60, reps: 8, rpe: nil, completed: true),
            SessionSetRow(id: "2", number: 2, weightKg: 60, reps: 8, rpe: 8, completed: false),
        ])

    var body: some View {
        ExerciseCard(
            group: group,
            imageStore: nil,
            onToggle: { _ in },
            onEdit: { _ in },
            onDelete: { _ in },
            onAddSet: {})
            .padding(Theme.Spacing.screenInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.Colors.canvas)
    }
}

#Preview("Light") {
    ExerciseCardGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ExerciseCardGallery()
        .preferredColorScheme(.dark)
}
