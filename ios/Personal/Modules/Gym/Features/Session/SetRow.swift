import SwiftUI

/// One set of the Session screen: `#1  60 kg × 8  ○/✓` in `numeric`
/// (design §4).
///
/// Tapping the values opens the editor; tapping the circle completes the set.
/// A horizontal drag reveals Delete, and the same action sits in the row's
/// context menu — the drag competes with the enclosing `ScrollView`'s pan, so
/// it is an accelerator rather than the only way in.
struct SetRow: View {

    var row: SessionSetRow
    var onToggle: () -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var offset: CGFloat = 0
    @State private var isFlashing = false

    /// How far the row slides to uncover the Delete button.
    private static let revealWidth: CGFloat = 88

    init(
        row: SessionSetRow,
        onToggle: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.row = row
        self.onToggle = onToggle
        self.onEdit = onEdit
        self.onDelete = onDelete
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteAction
            content
                .background(
                    background,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
                .offset(x: offset)
                .gesture(swipe)
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete set", systemImage: "trash")
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("#\(row.number)")
                .font(Theme.Typography.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: 28, alignment: .leading)

            Button(action: onEdit) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(row.valueText)
                        .font(Theme.Typography.numeric)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let rpeText = row.rpeText {
                        Text(rpeText)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    Spacer(minLength: Theme.Spacing.sm)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(valueLabel)
            .accessibilityHint("Edit weight and reps")

            completionButton
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .frame(minHeight: Theme.Spacing.rowMinHeight)
    }

    /// The spoken row: "Set 2, 60 kg × 8, RPE 8.5".
    private var valueLabel: String {
        var text = "Set \(row.number), \(row.valueText)"
        if let rpeText = row.rpeText {
            text += ", \(rpeText)"
        }
        return text
    }

    private var completionButton: some View {
        Button {
            // `row` is this view's snapshot, taken before the write, so it
            // still says whether the tap completes or un-completes the set.
            let isCompleting = row.completed == false
            onToggle()
            Haptics.selection()
            if isCompleting {
                flash()
            }
        } label: {
            completionSymbol
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.completed ? "Completed" : "Not completed")
        .accessibilityHint("Completes this set")
    }

    /// Two symbols swapped by a transition rather than one symbol with a
    /// scale: the resting state is then a plain 1.0 in both directions, and
    /// the 0.8 → 1 bounce (design §5) belongs to the checkmark's arrival only.
    private var completionSymbol: some View {
        ZStack {
            if row.completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.success)
                    .transition(completionTransition)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .transition(.opacity)
            }
        }
        .font(.system(size: 26, weight: .regular))
        .animation(completionAnimation, value: row.completed)
    }

    private var deleteAction: some View {
        Button(role: .destructive) {
            reset()
            onDelete()
        } label: {
            Label("Delete", systemImage: "trash")
                .labelStyle(.iconOnly)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: Self.revealWidth - Theme.Spacing.sm, height: 44)
                .background(Theme.Colors.danger, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete set \(row.number)")
        .opacity(offset < -8 ? 1 : 0)
    }

    // MARK: - Motion (design §5)

    /// The checkmark scales 0.8 → 1 with `.bouncy`; Reduce Motion replaces
    /// the scale with a plain fade (design §5).
    private var completionTransition: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity)
    }

    private var completionAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .bouncy(duration: 0.3)
    }

    /// The row background flashes `successSoft` for 400 ms.
    private var background: Color {
        isFlashing ? Theme.Colors.successSoft : Theme.Colors.surfaceSecondary.opacity(0)
    }

    private func flash() {
        guard reduceMotion == false else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            isFlashing = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(.easeOut(duration: 0.25)) {
                isFlashing = false
            }
        }
    }

    // MARK: - Swipe

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                // Vertical intent belongs to the scroll view, not to us.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                offset = min(0, max(-Self.revealWidth, value.translation.width))
            }
            .onEnded { value in
                if value.translation.width < -Self.revealWidth / 2 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        offset = -Self.revealWidth
                    }
                } else {
                    reset()
                }
            }
    }

    private func reset() {
        withAnimation(.easeOut(duration: 0.2)) {
            offset = 0
        }
    }
}

// MARK: - Previews

private struct SetRowGallery: View {
    var body: some View {
        GroupCard {
            SetRow(
                row: SessionSetRow(
                    id: "1", number: 1, weightKg: 60, reps: 8, rpe: nil, completed: true),
                onToggle: {}, onEdit: {}, onDelete: {})
            SetRow(
                row: SessionSetRow(
                    id: "2", number: 2, weightKg: 57.5, reps: 10, rpe: 8.5, completed: false),
                onToggle: {}, onEdit: {}, onDelete: {})
        }
        .padding(Theme.Spacing.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.canvas)
    }
}

#Preview("Light") {
    SetRowGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SetRowGallery()
        .preferredColorScheme(.dark)
}
