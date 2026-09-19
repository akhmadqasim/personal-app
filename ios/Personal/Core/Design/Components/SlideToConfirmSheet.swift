import SwiftUI

/// The destructive confirmation of the design system (§3 "Bottom sheet"): a
/// ``SheetHeader`` over a red capsule the user drags to the end.
///
/// A tap button is too easy to hit by accident for something that removes a
/// session or a whole program on every synced device, so the spec asks for a
/// slider. VoiceOver cannot drag, which is why the track also carries an
/// accessibility action.
struct SlideToConfirmSheet: View {

    /// The 44 pt circular glyph in the header.
    var symbol: String
    var title: String
    /// What exactly is about to happen, in one sentence.
    var message: String
    /// The label on the track — "Slide to confirm", or something sharper.
    var confirmTitle: String
    var onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// 0 at rest, 1 at the far end; ≥ 0.9 on release confirms.
    @State private var progress: CGFloat = 0

    /// Design §3: a red capsule, 48 pt, arrow knob.
    private static let trackHeight: CGFloat = 48
    private static let knobSize: CGFloat = 40
    private static let confirmAt: CGFloat = 0.9

    init(
        symbol: String,
        title: String,
        message: String,
        confirmTitle: String = "Slide to confirm",
        onConfirm: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SheetHeader(
                symbol: symbol,
                title: title,
                subtitle: message,
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
                .fill(Theme.Colors.dangerSoft)
            Text(confirmTitle)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.danger)
                .frame(maxWidth: .infinity)
                .opacity(1 - Double(progress))
                .allowsHitTesting(false)
            knob
                .offset(x: Theme.Spacing.xs + progress * travel)
                .gesture(drag(travel: travel))
        }
        .frame(height: Self.trackHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
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
                Image(systemName: "arrow.right")
                    .font(.system(size: 17, weight: .semibold))
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

#Preview("Light") {
    SlideToConfirmSheet(
        symbol: "trash",
        title: "Delete program",
        message: "The program is removed here and on every synced device. Sessions you already logged stay.",
        onConfirm: {})
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SlideToConfirmSheet(
        symbol: "trash",
        title: "Discard session",
        message: "The session and all of its sets are removed, here and on every synced device.",
        onConfirm: {})
        .preferredColorScheme(.dark)
}
