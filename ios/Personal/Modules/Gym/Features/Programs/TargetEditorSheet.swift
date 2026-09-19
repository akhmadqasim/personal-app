import SwiftUI

/// The target editor of one planned exercise (spec §6): sets, reps, an
/// optional working weight and the rest between sets.
///
/// The ranges are the contract with the repository (spec §8): sets 1–10, reps
/// 1–50, weight ≥ 0, rest 0–300 s in steps of 15. A stepper cannot produce
/// anything outside them, so no row the sheet writes can be rejected.
struct TargetEditorSheet: View {

    var row: DayExerciseRow
    /// `(sets, reps, weightKg, restSeconds)`; the last two are `nil` when the
    /// user left them off.
    var onSave: (Int, Int, Double?, Int?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var sets: Int
    @State private var reps: Int
    @State private var hasWeight: Bool
    @State private var weightText: String
    @State private var hasRest: Bool
    @State private var rest: Int

    init(row: DayExerciseRow, onSave: @escaping (Int, Int, Double?, Int?) -> Void) {
        self.row = row
        self.onSave = onSave
        _sets = State(initialValue: min(10, max(1, row.targetSets)))
        _reps = State(initialValue: min(50, max(1, row.targetReps)))
        _hasWeight = State(initialValue: row.targetWeightKg != nil)
        // Empty, not "0", when the plan carries no weight: a prefilled zero
        // reads as "lift nothing" and would be saved as a real target the
        // moment the toggle is flipped on.
        var initialWeight = ""
        if let stored = row.targetWeightKg {
            initialWeight = WeightFormat.plain(stored)
        }
        _weightText = State(initialValue: initialWeight)
        _hasRest = State(initialValue: row.restSeconds != nil)
        _rest = State(initialValue: Self.snapped(row.restSeconds ?? 90))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                SheetHeader(
                    symbol: "slider.horizontal.3",
                    title: row.name,
                    subtitle: "What this day plans for the movement.",
                    onClose: { dismiss() })

                GroupCard {
                    setsStepper
                    Divider().overlay(Theme.Colors.hairline)
                    repsStepper
                }

                GroupCard {
                    weightControl
                    Divider().overlay(Theme.Colors.hairline)
                    restControl
                }

                PillButton(style: .primary, title: "Save") {
                    save()
                }

                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.cardPadding)
        }
        .background(Theme.Colors.canvas)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Theme.Radius.sheet)
    }

    // MARK: - Fields

    private var setsStepper: some View {
        Stepper(value: $sets, in: 1 ... 10) {
            valueRow(label: "Sets", value: "\(sets)")
        }
        .frame(minHeight: Theme.Spacing.rowMinHeight)
    }

    private var repsStepper: some View {
        Stepper(value: $reps, in: 1 ... 50) {
            valueRow(label: "Reps", value: "\(reps)")
        }
        .frame(minHeight: Theme.Spacing.rowMinHeight)
    }

    private var weightControl: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Toggle(isOn: $hasWeight) {
                Text("Target weight")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .frame(minHeight: Theme.Spacing.rowMinHeight)

            if hasWeight {
                HStack(spacing: Theme.Spacing.md) {
                    Spacer(minLength: 0)
                    TextField("0", text: $weightText)
                        .font(Theme.Typography.numeric)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(maxWidth: 140)
                    Text("kg")
                        .font(Theme.Typography.secondary)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            } else {
                Text("A new session prefills from the last set you completed.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private var restControl: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Toggle(isOn: $hasRest) {
                Text("Rest")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .frame(minHeight: Theme.Spacing.rowMinHeight)

            if hasRest {
                Stepper(value: $rest, in: 0 ... 300, step: 15) {
                    valueRow(label: "Seconds", value: "\(rest)")
                }
                .frame(minHeight: Theme.Spacing.rowMinHeight)
            } else {
                Text("Today assumes 90 s when the plan does not say.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private func valueRow(label: String, value: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(label)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: Theme.Spacing.sm)
            Text(value)
                .font(Theme.Typography.numeric)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    // MARK: - Saving

    /// Accepts both decimal separators: a German keyboard types "57,5".
    ///
    /// The toggle being on is not enough to write a weight — the field has to
    /// hold a number. Left empty it saves `nil`, which is what lets a new
    /// session keep prefilling from the last set the user completed.
    private func save() {
        var weight: Double?
        if hasWeight {
            let normalised = weightText
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespaces)
            if let parsed = Double(normalised) {
                weight = max(0, parsed)
            }
        }
        onSave(sets, reps, weight, hasRest ? rest : nil)
        dismiss()
    }

    /// Rounds a stored rest onto the stepper's 15 s grid, so a value pulled
    /// from another device does not freeze the control.
    private static func snapped(_ seconds: Int) -> Int {
        let clamped = min(300, max(0, seconds))
        return ((clamped + 7) / 15) * 15
    }
}

// MARK: - Previews

#Preview("Light") {
    TargetEditorSheet(
        row: DayExerciseRow(
            id: "pe1",
            exerciseId: "e1",
            name: "Barbell Bench Press",
            art: ExerciseArt(muscleGroup: "chest", equipment: .barbell),
            targetSets: 3,
            targetReps: 10,
            targetWeightKg: 60,
            restSeconds: 90),
        onSave: { _, _, _, _ in })
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    TargetEditorSheet(
        row: DayExerciseRow(
            id: "pe1",
            exerciseId: "e1",
            name: "Lat Pulldown",
            art: ExerciseArt(muscleGroup: "back", equipment: .cable),
            targetSets: 4,
            targetReps: 12,
            targetWeightKg: nil,
            restSeconds: nil),
        onSave: { _, _, _, _ in })
        .preferredColorScheme(.dark)
}
