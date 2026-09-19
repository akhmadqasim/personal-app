import Charts
import SwiftUI

/// Weekly training volume of one exercise as bars (design §4): Σ weight × reps
/// of the completed sets, twelve weeks wide, in the muscle-group accent.
///
/// The x scale is categorical — one band per week, labelled "8 Sep" — rather
/// than a continuous date scale: twelve bars of equal width read as a
/// comparison, which is what a bar chart is for, and no bar is half-clipped at
/// the edges. `BarMark` anchors at zero by construction, which is the dataviz
/// rule for bars.
struct WeeklyVolumeCard: View {

    /// Raw `muscle_group` slug — what ``Theme/accent(for:)`` expects.
    var muscleGroup: String
    var weeks: [ProgressWeek]
    /// The spoken summary of the series, built by the view model.
    var accessibilityValue: String

    /// Fixed like the line chart's: a chart has no intrinsic height, the text
    /// around it grows with Dynamic Type instead.
    private static let chartHeight: CGFloat = 180

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GroupCard {
            header
            chart
        }
    }

    // MARK: - Pieces

    private var accent: Color {
        Theme.accent(for: muscleGroup)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Weekly volume")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("Weight × reps of every completed set")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var chart: some View {
        Chart {
            ForEach(weeks) { week in
                BarMark(
                    x: .value("Week", week.label),
                    y: .value("Volume", week.volumeKg)
                )
                .foregroundStyle(accent)
                .cornerRadius(Theme.Spacing.xs)
            }
        }
        // No gridlines on the category axis: they would separate the bars
        // rather than help read their height.
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                    .foregroundStyle(Theme.Colors.hairline)
                AxisValueLabel()
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartXAxisLabel {
            axisLabel("Week")
        }
        .chartYAxisLabel {
            axisLabel("kg")
        }
        .frame(height: Self.chartHeight)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: weeks)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly volume over the last 12 weeks")
        .accessibilityValue(accessibilityValue)
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textTertiary)
    }
}

// MARK: - Previews

private let volumePreviewWeeks: [ProgressWeek] = {
    let start = Date(timeIntervalSince1970: 1_693_785_600)
    let volumes: [Double] = [2_400, 2_880, 0, 3_120, 3_400, 3_050]
    let labels = ["4 Sep", "11 Sep", "18 Sep", "25 Sep", "2 Oct", "9 Oct"]
    var result: [ProgressWeek] = []
    for index in volumes.indices {
        result.append(
            ProgressWeek(
                weekStart: start.addingTimeInterval(Double(index) * 7 * 24 * 60 * 60),
                label: labels[index],
                volumeKg: volumes[index]))
    }
    return result
}()

private struct WeeklyVolumeCardGallery: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            WeeklyVolumeCard(
                muscleGroup: "chest",
                weeks: volumePreviewWeeks,
                accessibilityValue: "6 weeks, 14850 kg in total")
            WeeklyVolumeCard(
                muscleGroup: "quads",
                weeks: volumePreviewWeeks,
                accessibilityValue: "6 weeks, 14850 kg in total")
        }
        .padding(Theme.Spacing.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.canvas)
    }
}

#Preview("Light") {
    WeeklyVolumeCardGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    WeeklyVolumeCardGallery()
        .preferredColorScheme(.dark)
}
