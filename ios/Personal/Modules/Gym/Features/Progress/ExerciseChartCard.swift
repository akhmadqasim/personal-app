import Charts
import SwiftUI

/// The best-set line of one exercise over the last 12 weeks (design §4): a
/// monotone `LineMark` in the muscle-group accent over an `AreaMark` in its
/// `Soft` wash, with the latest value labelled directly on the point.
///
/// Dataviz rules the card keeps: one palette (the accent plus neutral text),
/// no gradients beyond the soft area fill, direct labels instead of a legend,
/// axis labels in `caption` / `textTertiary` and gridlines in `hairline`. The
/// area anchors the y scale at zero, so the slope never exaggerates a change.
struct ExerciseChartCard: View {

    var exerciseName: String
    /// Raw `muscle_group` slug — what ``Theme/accent(for:)`` expects.
    var muscleGroup: String
    var points: [ProgressPoint]
    /// The spoken summary of the series, built by the view model.
    var accessibilityValue: String

    /// Fixed on purpose: a chart has no intrinsic height, and the text around
    /// it is free to grow with Dynamic Type instead (spec §6).
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

    private var soft: Color {
        Theme.soft(for: muscleGroup)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("Best set per session")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(exerciseName)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Session", point.date),
                    y: .value("Weight", point.weightKg)
                )
                .foregroundStyle(soft)
                .interpolationMethod(.monotone)
            }
            ForEach(points) { point in
                LineMark(
                    x: .value("Session", point.date),
                    y: .value("Weight", point.weightKg)
                )
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }
            // The direct label the dataviz rules ask for instead of a legend:
            // only the latest value, so the line stays readable.
            if let last = points.last {
                PointMark(
                    x: .value("Session", last.date),
                    y: .value("Weight", last.weightKg)
                )
                .foregroundStyle(accent)
                .symbolSize(56)
                .annotation(position: .top, alignment: .trailing, spacing: Theme.Spacing.xs) {
                    Text("\(WeightFormat.plain(last.weightKg)) kg")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                    .foregroundStyle(Theme.Colors.hairline)
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
        // No x title: the labels already read as dates, and "Session date"
        // would only repeat the card's own header.
        .chartYAxisLabel {
            axisLabel("kg")
        }
        .frame(height: Self.chartHeight)
        // Reduce Motion: the redraw after a chip tap is a cut, not a morph.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: points)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Best set weight over the last 12 weeks")
        .accessibilityValue(accessibilityValue)
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textTertiary)
    }
}

// MARK: - Previews

private let chartPreviewPoints: [ProgressPoint] = {
    let start = Date(timeIntervalSince1970: 1_693_785_600)
    let weights: [Double] = [60, 62.5, 62.5, 65, 67.5, 70]
    var result: [ProgressPoint] = []
    for index in weights.indices {
        result.append(
            ProgressPoint(
                id: "session-\(index)",
                date: start.addingTimeInterval(Double(index) * 7 * 24 * 60 * 60),
                weightKg: weights[index]))
    }
    return result
}()

private struct ExerciseChartCardGallery: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ExerciseChartCard(
                exerciseName: "Bench press",
                muscleGroup: "chest",
                points: chartPreviewPoints,
                accessibilityValue: "6 sessions, from 60 kg to 70 kg")
            ExerciseChartCard(
                exerciseName: "Barbell row",
                muscleGroup: "back",
                points: chartPreviewPoints,
                accessibilityValue: "6 sessions, from 60 kg to 70 kg")
        }
        .padding(Theme.Spacing.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.canvas)
    }
}

#Preview("Light") {
    ExerciseChartCardGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ExerciseChartCardGallery()
        .preferredColorScheme(.dark)
}
