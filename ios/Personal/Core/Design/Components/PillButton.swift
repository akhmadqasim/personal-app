import SwiftUI

/// The capsule button of the design system (§3 "Buttons").
///
/// Four fills, one shape: primary is the `ink` capsule with an inverse label,
/// secondary the quiet `surfaceSecondary` one, accent the contextual
/// muscle-group colour, destructive the `danger` fill. Disabled always falls
/// back to `surfaceSecondary` + `textTertiary`, whatever the style.
struct PillButton: View {

    /// `nonisolated` so the enum does not inherit the module's main-actor
    /// default isolation; it carries a `Color` and nothing else.
    nonisolated enum Style {
        /// `ink` fill, inverse label — one per screen.
        case primary
        /// `surfaceSecondary` fill, primary-text label.
        case secondary
        /// Contextual accent fill (`Theme.accent(for:)`), white label.
        case accent(Color)
        /// `danger` fill, white label.
        case destructive
    }

    var style: Style
    var title: String
    var systemImage: String?
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(
        style: Style = .primary,
        title: String,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) {
        self.style = style
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .regular))
                }
                Text(title)
                    .font(Theme.Typography.headline)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var minHeight: CGFloat {
        switch style {
        case .secondary: 48
        default: 52
        }
    }

    /// `canvas` is the inverse of `ink` in both schemes (near-white on the
    /// black light-mode fill, near-black on the white dark-mode fill), so the
    /// primary label needs no colour of its own.
    private var foreground: Color {
        guard isEnabled else { return Theme.Colors.textTertiary }
        switch style {
        case .primary: return Theme.Colors.canvas
        case .secondary: return Theme.Colors.textPrimary
        case .accent: return Color.white
        case .destructive: return Color.white
        }
    }

    private var background: Color {
        guard isEnabled else { return Theme.Colors.surfaceSecondary }
        switch style {
        case .primary: return Theme.Colors.ink
        case .secondary: return Theme.Colors.surfaceSecondary
        case .accent(let color): return color
        case .destructive: return Theme.Colors.danger
        }
    }
}

// MARK: - Previews

private struct PillButtonGallery: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            PillButton(style: .primary, title: "Start session", systemImage: "play.fill") {}
            PillButton(style: .secondary, title: "Add exercise", systemImage: "plus") {}
            PillButton(style: .accent(Theme.accent(for: "chest")), title: "Subscribe") {}
            PillButton(style: .destructive, title: "Delete", systemImage: "trash") {}
            PillButton(style: .primary, title: "Disabled") {}
                .disabled(true)
        }
        .padding(Theme.Spacing.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.canvas)
    }
}

#Preview("Light") {
    PillButtonGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    PillButtonGallery()
        .preferredColorScheme(.dark)
}
