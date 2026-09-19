import SwiftUI

/// The small tinted capsule that carries state in lists and on cards
/// (§3 "Status pill"). Status is never a full-colour row.
struct StatusPill: View {

    /// `nonisolated` so `CaseIterable` and `RawRepresentable` are witnessed
    /// outside the main actor, the way the model enums are.
    nonisolated enum Kind: String, CaseIterable, Sendable {
        case completed
        case inProgress
        /// Defined by the design system; no screen uses it yet.
        case skipped
        /// Defined by the design system; no screen uses it yet.
        case pr
        /// Defined by the design system; no screen uses it yet.
        case draft
        /// The one program Today reads from (spec §6, Programs list).
        case active

        /// Every pill carries a text label (spec §6) — VoiceOver reads this.
        var label: String {
            switch self {
            case .completed: "Completed"
            case .inProgress: "In progress"
            case .skipped: "Skipped"
            case .pr: "PR"
            case .draft: "Draft"
            case .active: "Active"
            }
        }
    }

    var kind: Kind

    init(_ kind: Kind) {
        self.kind = kind
    }

    init(kind: Kind) {
        self.kind = kind
    }

    var body: some View {
        Text(kind.label)
            .font(Theme.Typography.pill)
            .foregroundStyle(foreground)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(fillColor, in: Capsule())
    }

    /// `active` is `info`, not `success` (design §2): success means something
    /// finished, and the active program is a selection, not an achievement.
    private var foreground: Color {
        switch kind {
        case .completed, .pr: Theme.Colors.success
        case .inProgress, .active: Theme.Colors.info
        case .skipped: Theme.Colors.warning
        case .draft: Theme.Colors.textTertiary
        }
    }

    private var fillColor: Color {
        switch kind {
        case .completed, .pr: Theme.Colors.successSoft
        case .inProgress, .active: Theme.Colors.infoSoft
        case .skipped: Theme.Colors.warningSoft
        case .draft: Theme.Colors.surfaceSecondary
        }
    }
}

// MARK: - Previews

private struct StatusPillGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(StatusPill.Kind.allCases, id: \.rawValue) { kind in
                StatusPill(kind)
            }
        }
        .padding(Theme.Spacing.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Colors.canvas)
    }
}

#Preview("Light") {
    StatusPillGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    StatusPillGallery()
        .preferredColorScheme(.dark)
}
