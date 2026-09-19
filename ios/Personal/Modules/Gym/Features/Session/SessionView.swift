import SwiftUI

/// The running session (spec §6, design §4): ambient background, the elapsed
/// caption, the action row, then one card per exercise.
struct SessionView: View {

    private let environment: AppEnvironment

    @State private var model: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    init(environment: AppEnvironment, sessionId: String) {
        self.environment = environment
        _model = State(
            initialValue: SessionViewModel(
                sessionId: sessionId,
                repository: environment.repository,
                scheduler: environment.syncScheduler,
                imageStore: environment.imageStore))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                heading
                actionRow
                cards
            }
            .padding(.horizontal, Theme.Spacing.screenInset)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .background {
            AmbientBackground(image: model.ambientImage)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toast($model.toast)
        .task {
            model.loadSession()
            await model.loadAmbientImage()
        }
        .task {
            // Live set list: a sync pull that lands mid-session redraws the
            // rows. Cancelled with the view.
            await model.observeSets()
        }
        .onChange(of: model.isGone) { _, isGone in
            if isGone {
                dismiss()
            }
        }
        .sheet(item: $model.editingSet) { row in
            SetEditorSheet(
                row: row,
                onSave: { weight, reps, rpe in
                    model.updateSet(row.id, weightKg: weight, reps: reps, rpe: rpe)
                },
                onDelete: {
                    model.deleteSet(row.id)
                })
        }
        .sheet(isPresented: $model.isPickingExercise) {
            ExercisePickerSheet(
                repository: environment.repository,
                imageStore: model.imageStore,
                onPick: { exercise in
                    model.addExercise(exercise)
                })
        }
        .sheet(isPresented: $model.isDiscarding) {
            DiscardSessionSheet {
                model.discard()
            }
        }
        .alert("Rename session", isPresented: $model.isRenaming) {
            TextField("Name", text: $model.renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                model.commitRename()
            }
        } message: {
            Text("Leave it empty to go back to the program day's name.")
        }
    }

    // MARK: - Heading

    private var heading: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(model.caption(at: context.date))
                    .font(Theme.Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Text(model.title)
                    .font(Theme.Typography.largeTitle)
                    .tracking(Theme.Typography.largeTitleTracking)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                if model.isFinished {
                    StatusPill(.completed)
                }
            }
            .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private var actionRow: some View {
        VStack(spacing: Theme.Spacing.sm) {
            PillButton(style: .primary, title: "Finish", systemImage: "checkmark") {
                model.finish()
            }
            .disabled(model.isFinished)

            HStack(spacing: Theme.Spacing.sm) {
                PillButton(style: .secondary, title: "Add exercise", systemImage: "plus") {
                    model.isPickingExercise = true
                }
                moreMenu
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            Button {
                model.beginRename()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button(role: .destructive) {
                model.isDiscarding = true
            } label: {
                Label("Discard", systemImage: "trash")
            }
        } label: {
            Label("More", systemImage: "ellipsis")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.xl)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Theme.Colors.surfaceSecondary, in: Capsule())
                .contentShape(Capsule())
        }
        .accessibilityLabel("More session actions")
    }

    // MARK: - Cards

    @ViewBuilder
    private var cards: some View {
        if model.groups.isEmpty {
            EmptyState(
                symbol: "dumbbell",
                title: "No exercises yet",
                message: "Add one and its sets will show up here.",
                action: (title: "Add exercise", handler: { model.isPickingExercise = true }))
        } else {
            ForEach(model.groups) { group in
                ExerciseCard(
                    group: group,
                    imageStore: model.imageStore,
                    onToggle: { row in model.toggleCompleted(row.id) },
                    onEdit: { row in model.editingSet = row },
                    onDelete: { row in model.deleteSet(row.id) },
                    onAddSet: { model.addSet(to: group.id) })
            }
        }
    }
}

// MARK: - Discard

/// The discard confirmation (spec §6): a ``SheetHeader`` and a capsule the
/// user drags to the end. A destructive action that deletes a whole session
/// deserves more than a tap that can be made by accident.
struct DiscardSessionSheet: View {

    var onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// 0 at rest, 1 at the far end; ≥ 0.9 on release confirms.
    @State private var progress: CGFloat = 0

    private static let knobSize: CGFloat = 52
    private static let trackHeight: CGFloat = 60
    private static let confirmAt: CGFloat = 0.9

    init(onConfirm: @escaping () -> Void) {
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SheetHeader(
                symbol: "trash",
                title: "Discard session",
                subtitle: "The session and all of its sets are removed, here and on every synced device.",
                onClose: { dismiss() })

            GeometryReader { proxy in
                slider(width: proxy.size.width)
            }
            .frame(height: Self.trackHeight)

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.canvas)
        .presentationDetents([.height(300)])
        .presentationCornerRadius(Theme.Radius.sheet)
    }

    private func slider(width: CGFloat) -> some View {
        let travel = max(1, width - Self.knobSize - Theme.Spacing.sm)
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(Theme.Colors.surfaceSecondary)
            Text("Slide to discard")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
                .opacity(1 - Double(progress))
                .allowsHitTesting(false)
            knob
                .offset(x: Theme.Spacing.xs + progress * travel)
                .gesture(drag(travel: travel))
        }
        .frame(height: Self.trackHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Discard session")
        .accessibilityHint("Slide to the end to confirm")
        .accessibilityAddTraits(.isButton)
        // VoiceOver cannot drag; a double tap has to do it.
        .accessibilityAction {
            confirm()
        }
    }

    private var knob: some View {
        Circle()
            .fill(Theme.Colors.danger)
            .frame(width: Self.knobSize, height: Self.knobSize)
            .overlay {
                Image(systemName: "trash")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
    }

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                progress = min(1, max(0, value.translation.width / travel))
            }
            .onEnded { _ in
                if progress >= Self.confirmAt {
                    progress = 1
                    confirm()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        progress = 0
                    }
                }
            }
    }

    private func confirm() {
        Haptics.success()
        onConfirm()
        dismiss()
    }
}

// MARK: - Previews

#Preview("Discard") {
    DiscardSessionSheet(onConfirm: {})
}
