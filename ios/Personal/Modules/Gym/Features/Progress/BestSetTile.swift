import SwiftUI

/// The "Best set" tile under the line chart (design §4): the heaviest set of
/// the last 12 weeks in `numeric`, coloured with the muscle-group accent, and
/// the day it was logged.
///
/// One element to VoiceOver — "Best set, 65 kg × 8 on Mon 4 Sep" — rather than
/// three labels read in a row.
struct BestSetTile: View {

    var best: ProgressBest
    /// Raw `muscle_group` slug — what ``Theme/accent(for:)`` expects.
    var muscleGroup: String

    var body: some View {
        GroupCard(spacing: Theme.Spacing.xs) {
            Text("Best set")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
                Text(best.valueText)
                    .font(Theme.Typography.numeric)
                    .foregroundStyle(Theme.accent(for: muscleGroup))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: Theme.Spacing.sm)
                Text(best.dateText)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Best set")
        .accessibilityValue("\(best.valueText) on \(best.dateText)")
    }
}

// MARK: - Previews

private struct BestSetTileGallery: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            BestSetTile(
                best: ProgressBest(valueText: "65 kg × 8", dateText: "Mon 4 Sep"),
                muscleGroup: "chest")
            BestSetTile(
                best: ProgressBest(valueText: "107.5 kg × 3", dateText: "Wed 20 Sep"),
                muscleGroup: "back")
        }
        .padding(Theme.Spacing.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.canvas)
    }
}

#Preview("Light") {
    BestSetTileGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    BestSetTileGallery()
        .preferredColorScheme(.dark)
}
