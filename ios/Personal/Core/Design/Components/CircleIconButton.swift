import SwiftUI

/// A 40 pt circular Liquid Glass button — the back button, the header actions
/// and the modal close (§3 "Header", "Buttons").
///
/// `.glassEffect(.regular.interactive(), in: .circle)` needs no availability
/// check: the deployment target is iOS 26.
struct CircleIconButton: View {

    var systemImage: String
    /// VoiceOver label. Required, not optional: an icon-only control with no
    /// label is announced as its symbol name ("chevron.left"), which spec §6
    /// rules out, and a default would let that slip through unnoticed.
    var accessibilityLabel: String
    var action: () -> Void

    init(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: 40, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Previews

private struct CircleIconButtonGallery: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            CircleIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") {}
            CircleIconButton(systemImage: "square.and.pencil", accessibilityLabel: "Edit") {}
            CircleIconButton(systemImage: "ellipsis", accessibilityLabel: "More") {}
            CircleIconButton(systemImage: "xmark", accessibilityLabel: "Close") {}
        }
        .padding(Theme.Spacing.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.canvas)
    }
}

#Preview("Light") {
    CircleIconButtonGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    CircleIconButtonGallery()
        .preferredColorScheme(.dark)
}
