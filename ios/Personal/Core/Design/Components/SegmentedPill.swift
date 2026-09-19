import SwiftUI

/// The header segmented control (§3 "Pill segmented control"): a
/// `surfaceSecondary` capsule track with a brighter selected segment that
/// slides between labels ("Upcoming | History").
///
/// Defined by the design system; no screen uses it yet.
struct SegmentedPill: View {

    @Binding var selection: Int
    var labels: [String]

    @Namespace private var namespace

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(selection: Binding<Int>, labels: [String]) {
        self._selection = selection
        self.labels = labels
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(labels.indices, id: \.self) { index in
                segment(index)
            }
        }
        .padding(Theme.Spacing.xs)
        .background(Theme.Colors.surfaceSecondary, in: Capsule())
    }

    private func segment(_ index: Int) -> some View {
        Button {
            // Reduce Motion: the selected capsule cuts to the new segment
            // instead of sliding across (design §5).
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                selection = index
            }
            Haptics.selection()
        } label: {
            Text(labels[index])
                .font(Theme.Typography.headline)
                .foregroundStyle(
                    index == selection ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background {
                    if index == selection {
                        Capsule()
                            .fill(Theme.Colors.surfaceSelected)
                            .matchedGeometryEffect(id: "segment", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(index == selection ? [.isSelected, .isButton] : [.isButton])
    }
}

// MARK: - Previews

private struct SegmentedPillGallery: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            SegmentedPill(selection: .constant(0), labels: ["Upcoming", "History"])
            SegmentedPill(selection: .constant(2), labels: ["Week", "Month", "Year"])
        }
        .padding(Theme.Spacing.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.canvas)
    }
}

#Preview("Light") {
    SegmentedPillGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SegmentedPillGallery()
        .preferredColorScheme(.dark)
}
