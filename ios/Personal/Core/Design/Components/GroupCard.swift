import SwiftUI

/// A `surface` container with radius 20 and 16 pt padding — the grouped card
/// every screen builds its sections from (§3 "Grouped rows").
///
/// No shadow: in light mode the white-on-off-white contrast does the work, in
/// dark mode the translucent white surface does.
struct GroupCard<Content: View>: View {

    var spacing: CGFloat
    var content: Content

    init(spacing: CGFloat = Theme.Spacing.md, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.cardPadding)
        .background(
            Theme.Colors.surface,
            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

// MARK: - Previews

private struct GroupCardGallery: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            GroupCard {
                Text("Push A")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("6 exercises · ~50 min")
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            GroupCard {
                HStack {
                    Text("Rest timer")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Text("90 s")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(minHeight: Theme.Spacing.rowMinHeight)
            }
        }
        .padding(Theme.Spacing.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.canvas)
    }
}

#Preview("Light") {
    GroupCardGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    GroupCardGallery()
        .preferredColorScheme(.dark)
}
