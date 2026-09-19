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
        // Design §3: pushed pages carry a 40 pt circular glass back button,
        // not the system chevron. Hiding the system one also disables the
        // interactive swipe-back; the ruling accepts that trade.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CircleIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") {
                    dismiss()
                }
            }
        }
        .toast($model.toast)
        .task {
            model.loadSession()
        }
        // Re-runs when the session's first exercise changes — adding a
        // movement to an empty session changes what the ambient art is of.
        .task(id: model.firstExerciseId) {
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
                scheduler: environment.syncScheduler,
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

    /// Design §3 "Detail-page action row": one primary capsule and two
    /// `surfaceSecondary` ones, equal widths, 8 pt gap, icon above a 13 pt
    /// label. `More` has to stay a `Menu`, so it borrows ``PillButtonLabel``
    /// rather than growing its own capsule.
    private var actionRow: some View {
        HStack(spacing: Theme.Spacing.sm) {
            PillButton(
                style: .primary,
                layout: .iconAbove,
                title: "Finish",
                systemImage: "checkmark"
            ) {
                model.finish()
            }
            .disabled(model.isFinished)

            PillButton(
                style: .secondary,
                layout: .iconAbove,
                title: "Add exercise",
                systemImage: "plus"
            ) {
                model.isPickingExercise = true
            }

            moreMenu
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
            PillButtonLabel(
                style: .secondary,
                layout: .iconAbove,
                title: "More",
                systemImage: "ellipsis")
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

/// The discard confirmation (spec §6): the shared ``SlideToConfirmSheet`` with
/// the session's own words. It stays a named view so the call site reads as
/// what it does, not as a pile of strings.
struct DiscardSessionSheet: View {

    var onConfirm: () -> Void

    init(onConfirm: @escaping () -> Void) {
        self.onConfirm = onConfirm
    }

    var body: some View {
        SlideToConfirmSheet(
            symbol: "trash",
            title: "Discard session",
            message: "The session and all of its sets are removed, here and on every synced device.",
            onConfirm: onConfirm)
    }
}

// MARK: - Previews

#Preview("Discard") {
    DiscardSessionSheet(onConfirm: {})
}
