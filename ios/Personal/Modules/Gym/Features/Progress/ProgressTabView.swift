import SwiftUI

/// The Progress tab (spec §6, design §4): "✦ Progress", a chips row of the
/// six exercises with the most recent volume, and — for the selected one —
/// the best-set line, the best-set tile and the weekly volume bars.
///
/// Named `ProgressTabView`, not `ProgressView`: SwiftUI already owns that name
/// and the spinner this very file draws while the first read runs.
struct ProgressTabView: View {

    private let environment: AppEnvironment

    @State private var model: ProgressTabViewModel
    @State private var isPickingExercise = false

    /// `environment` is passed in rather than read from `@Environment`, like
    /// ``TodayView``: the view model is then built once, in `init`.
    init(environment: AppEnvironment) {
        self.environment = environment
        _model = State(initialValue: ProgressTabViewModel(repository: environment.repository))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    title
                    content
                }
                .padding(.horizontal, Theme.Spacing.screenInset)
                .padding(.bottom, Theme.Spacing.xxxl)
            }
            .background(Theme.Colors.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CircleIconButton(
                        systemImage: "magnifyingglass",
                        accessibilityLabel: "Find an exercise"
                    ) {
                        isPickingExercise = true
                    }
                }
            }
            // The Session screen's picker, told what it is picking for: a
            // chart needs a movement that already has sets, so it neither
            // offers "+ new exercise" nor marks the rows with a plus.
            .sheet(isPresented: $isPickingExercise) {
                ExercisePickerSheet(
                    repository: environment.repository,
                    imageStore: environment.imageStore,
                    title: "Choose exercise",
                    allowsCreating: false,
                    rowSymbol: "chart.line.uptrend.xyaxis"
                ) { exercise in
                    model.select(exercise)
                }
            }
        }
        .toast($model.toast)
        .task {
            model.reload()
        }
    }

    // MARK: - Header

    private var title: some View {
        Text("✦ Progress")
            .font(Theme.Typography.largeTitle)
            .tracking(Theme.Typography.largeTitleTracking)
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xxl)
        case .empty:
            EmptyState(
                symbol: "chart.line.uptrend.xyaxis",
                title: "Nothing logged yet",
                message: "Complete a few sets in a session and your progress shows up here.")
        case .notEnoughData, .ready:
            exerciseSection
        }
    }

    @ViewBuilder
    private var exerciseSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ExerciseChips(
                exercises: model.chipExercises,
                selectedId: model.selected?.id
            ) { exercise in
                model.select(exercise)
            }

            if model.state == .notEnoughData {
                EmptyState(
                    symbol: "chart.line.uptrend.xyaxis",
                    title: "Not enough data yet",
                    message: "Log two sessions with this exercise to see progress.")
            } else {
                ExerciseChartCard(
                    exerciseName: model.exerciseName,
                    muscleGroup: model.accentGroup,
                    points: model.points,
                    accessibilityValue: model.chartAccessibilityValue)
                if let best = model.best {
                    BestSetTile(best: best, muscleGroup: model.accentGroup)
                }
                WeeklyVolumeCard(
                    muscleGroup: model.accentGroup,
                    weeks: model.weeklyVolume,
                    accessibilityValue: model.volumeAccessibilityValue)
            }
        }
    }
}

// MARK: - Chips

/// The exercise chips of the Progress tab, in the chip style of §3: a 36 pt
/// capsule, `surface` with a hairline border, flipping to the `ink` fill when
/// selected. Same shape as ``MuscleGroupChips``, different contents.
private struct ExerciseChips: View {

    var exercises: [Exercise]
    var selectedId: String?
    var onSelect: (Exercise) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(exercises) { exercise in
                    chip(exercise)
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ exercise: Exercise) -> some View {
        let isSelected = exercise.id == selectedId
        return Button {
            onSelect(exercise)
            Haptics.selection()
        } label: {
            Text(exercise.name)
                .font(Theme.Typography.secondary)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Theme.Colors.canvas : Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(minHeight: 36)
                .background(isSelected ? Theme.Colors.ink : Theme.Colors.surface, in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Theme.Colors.hairline, lineWidth: isSelected ? 0 : 1)
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }
}

// MARK: - Previews

#Preview("Light") {
    ProgressTabView(environment: AppEnvironment.preview())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ProgressTabView(environment: AppEnvironment.preview())
        .preferredColorScheme(.dark)
}
