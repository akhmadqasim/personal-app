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
        /// Defined by the design system; no screen uses it yet.
        case accent(Color)
        /// `danger` fill, white label.
        case destructive
    }

    /// How the symbol and the label sit inside the capsule.
    nonisolated enum Layout {
        /// Symbol before the label, one line, `headline` — the full-width CTA.
        case inline
        /// Symbol above a 13 pt label — the detail-page action row (§3): one
        /// primary capsule and two secondary ones, equal widths, 8 pt gap.
        case iconAbove
    }

    var style: Style
    var layout: Layout
    var title: String
    var systemImage: String?
    var action: () -> Void

    init(
        style: Style = .primary,
        layout: Layout = .inline,
        title: String,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) {
        self.style = style
        self.layout = layout
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            PillButtonLabel(
                style: style,
                layout: layout,
                title: title,
                systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - The capsule itself

/// The chrome of a ``PillButton``, on its own so a control that cannot be a
/// `Button` — the session's "More" `Menu` — can wear the same clothes instead
/// of growing a second, drifting copy of the capsule.
///
/// It reads `isEnabled` from the environment rather than taking a flag:
/// `.disabled(_:)` on the enclosing `Button` or `Menu` already propagates
/// there, so the disabled look cannot be forgotten at a call site.
struct PillButtonLabel: View {

    var style: PillButton.Style
    var layout: PillButton.Layout
    var title: String
    var systemImage: String?

    @Environment(\.isEnabled) private var isEnabled

    init(
        style: PillButton.Style = .primary,
        layout: PillButton.Layout = .inline,
        title: String,
        systemImage: String? = nil
    ) {
        self.style = style
        self.layout = layout
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .foregroundStyle(foreground)
            .background(fillColor, in: Capsule())
            .contentShape(Capsule())
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .inline:
            HStack(spacing: Theme.Spacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .regular))
                }
                Text(title)
                    .font(Theme.Typography.headline)
            }
        case .iconAbove:
            VStack(spacing: Theme.Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .regular))
                }
                Text(title)
                    .font(Theme.Typography.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.vertical, Theme.Spacing.md)
        }
    }

    private var minHeight: CGFloat {
        switch layout {
        case .iconAbove:
            return 64
        case .inline:
            switch style {
            case .secondary: return 48
            default: return 52
            }
        }
    }

    /// The action row puts three capsules across the screen; `xl` would eat
    /// the label.
    private var horizontalPadding: CGFloat {
        switch layout {
        case .inline: Theme.Spacing.xl
        case .iconAbove: Theme.Spacing.sm
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

    private var fillColor: Color {
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
            HStack(spacing: Theme.Spacing.sm) {
                PillButton(
                    style: .primary, layout: .iconAbove,
                    title: "Finish", systemImage: "checkmark") {}
                PillButton(
                    style: .secondary, layout: .iconAbove,
                    title: "Add exercise", systemImage: "plus") {}
                PillButton(
                    style: .secondary, layout: .iconAbove,
                    title: "More", systemImage: "ellipsis") {}
            }
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
