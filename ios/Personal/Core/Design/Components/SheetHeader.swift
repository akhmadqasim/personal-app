import SwiftUI

/// The header row of a bottom sheet (§3 "Bottom sheet"): a 44 pt circular
/// `surfaceSecondary` icon on the left, a close circle on the right, then the
/// `section` title and an optional `secondary` subtitle.
struct SheetHeader: View {

    var symbol: String
    var title: String
    var subtitle: String?
    var onClose: (() -> Void)?

    init(
        symbol: String,
        title: String,
        subtitle: String? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Theme.Colors.surfaceSecondary, in: Circle())
                    // Decoration: the title says what the sheet is about.
                    .accessibilityHidden(true)
                Spacer(minLength: Theme.Spacing.sm)
                if let onClose {
                    CircleIconButton(
                        systemImage: "xmark",
                        accessibilityLabel: "Close",
                        action: onClose)
                }
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.section)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.secondary)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Previews

private struct SheetHeaderGallery: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            SheetHeader(
                symbol: "square.and.arrow.up",
                title: "Export data",
                subtitle: "Every session and set as JSON.",
                onClose: {})
            SheetHeader(symbol: "trash", title: "Delete program")
        }
        .padding(Theme.Spacing.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.surface)
    }
}

#Preview("Light") {
    SheetHeaderGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SheetHeaderGallery()
        .preferredColorScheme(.dark)
}
