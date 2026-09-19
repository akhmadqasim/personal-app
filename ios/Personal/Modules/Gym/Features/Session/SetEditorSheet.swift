import SwiftUI

/// The set editor (spec §6): weight on a decimal pad, reps on a stepper, RPE
/// optional.
///
/// The inputs are what keep the repository from ever seeing an invalid row
/// (spec §8): reps ≥ 1, weight ≥ 0, RPE 1–10.
struct SetEditorSheet: View {

    var row: SessionSetRow
    var onSave: (Double, Int, Double?) -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isWeightFocused: Bool

    @State private var weightText: String
    @State private var reps: Int
    @State private var hasRPE: Bool
    @State private var rpe: Double

    init(
        row: SessionSetRow,
        onSave: @escaping (Double, Int, Double?) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.row = row
        self.onSave = onSave
        self.onDelete = onDelete
        _weightText = State(initialValue: WeightFormat.plain(row.weightKg))
        _reps = State(initialValue: row.reps)
        _hasRPE = State(initialValue: row.rpe != nil)
        _rpe = State(initialValue: row.rpe ?? 8)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                SheetHeader(
                    symbol: "slider.horizontal.3",
                    title: "Set #\(row.number)",
                    subtitle: "Weight, reps and how hard it felt.",
                    onClose: { dismiss() })

                GroupCard {
                    weightField
                    Divider().overlay(Theme.Colors.hairline)
                    repsStepper
                    Divider().overlay(Theme.Colors.hairline)
                    rpeControl
                }

                PillButton(style: .primary, title: "Save") {
                    save()
                }
                PillButton(style: .destructive, title: "Delete set", systemImage: "trash") {
                    dismiss()
                    onDelete()
                }
            }
            .padding(Theme.Spacing.cardPadding)
        }
        .background(Theme.Colors.canvas)
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Theme.Radius.sheet)
    }

    // MARK: - Fields

    private var weightField: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text("Weight")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: Theme.Spacing.sm)
            TextField("0", text: $weightText)
                .font(Theme.Typography.numeric)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .focused($isWeightFocused)
                .frame(maxWidth: 140)
            Text("kg")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(minHeight: Theme.Spacing.rowMinHeight)
    }

    private var repsStepper: some View {
        Stepper(value: $reps, in: 1 ... 100) {
            HStack(spacing: Theme.Spacing.md) {
                Text("Reps")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: Theme.Spacing.sm)
                Text("\(reps)")
                    .font(Theme.Typography.numeric)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
        .frame(minHeight: Theme.Spacing.rowMinHeight)
    }

    private var rpeControl: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Toggle(isOn: $hasRPE) {
                Text("RPE")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .frame(minHeight: Theme.Spacing.rowMinHeight)

            if hasRPE {
                HStack(spacing: Theme.Spacing.md) {
                    Slider(value: $rpe, in: 1 ... 10, step: 0.5)
                    Text(WeightFormat.plain(rpe))
                        .font(Theme.Typography.headline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Rate of perceived exertion")
            }
        }
    }

    // MARK: - Saving

    /// Accepts both decimal separators: a German keyboard types "57,5".
    private func save() {
        let normalised = weightText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        let weight = max(0, Double(normalised) ?? row.weightKg)
        onSave(weight, max(1, reps), hasRPE ? rpe : nil)
        dismiss()
    }
}

// MARK: - Previews

#Preview("Light") {
    SetEditorSheet(
        row: SessionSetRow(id: "1", number: 2, weightKg: 57.5, reps: 8, rpe: 8, completed: false),
        onSave: { _, _, _ in },
        onDelete: {})
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SetEditorSheet(
        row: SessionSetRow(id: "1", number: 2, weightKg: 57.5, reps: 8, rpe: nil, completed: false),
        onSave: { _, _, _ in },
        onDelete: {})
        .preferredColorScheme(.dark)
}
