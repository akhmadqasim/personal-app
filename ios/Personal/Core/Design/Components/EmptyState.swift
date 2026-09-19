import SwiftUI

/// The centred placeholder a list shows when it has nothing to show
/// (§3 "Empty state"): a 72 pt rounded-square tile, a title, a message and an
/// optional call to action.
struct EmptyState: View {

    var symbol: String
    var title: String
    var message: String
    /// Label and handler of the optional primary button below the message.
    var action: (title: String, handler: () -> Void)?

    init(
        symbol: String,
        title: String,
        message: String,
        action: (title: String, handler: () -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.action = action
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: 72, height: 72)
                .background(
                    Theme.Colors.surfaceSecondary,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(message)
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Colors.textTertiary)
                .multilineTextAlignment(.center)
            if let action {
                PillButton(style: .primary, title: action.title, action: action.handler)
                    .padding(.top, Theme.Spacing.sm)
                    .frame(maxWidth: 260)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Previews

private struct EmptyStateGallery: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.xxxl) {
            EmptyState(
                symbol: "figure.strengthtraining.traditional",
                title: "No sessions yet",
                message: "Start a session from a program day and it will show up here.",
                action: (title: "Start session", handler: {}))
            EmptyState(
                symbol: "magnifyingglass",
                title: "No exercises found",
                message: "Try another muscle group or clear the filters.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.canvas)
    }
}

#Preview("Light") {
    EmptyStateGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    EmptyStateGallery()
        .preferredColorScheme(.dark)
}
