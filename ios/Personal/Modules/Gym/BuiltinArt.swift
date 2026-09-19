import SwiftUI

/// The illustration every catalog exercise falls back to.
///
/// The asset catalog may one day hold a drawing per `builtin/<slug>`; until
/// then — and for any exercise the user adds without a photo — the app draws
/// an SF Symbol on the muscle-group `Soft` tile. Choosing the symbol from
/// equipment and muscle group rather than from a 60-entry table keeps every
/// new exercise consistent by construction; a handful of slugs that deserve
/// better than their equipment default are named explicitly below.
enum BuiltinArt {

    /// The symbol drawn on the tile. `slug` wins, then a cardio muscle group,
    /// then the equipment table, then `dumbbell`.
    nonisolated static func symbol(
        for slug: String,
        equipment: Equipment? = nil,
        muscleGroup: MuscleGroup? = nil
    ) -> String {
        if let special = specialSymbols[slug] {
            return special
        }
        if muscleGroup == .cardio {
            return cardioSymbol
        }
        guard let equipment else {
            return defaultSymbol
        }
        switch equipment {
        case .barbell, .dumbbell, .other:
            return defaultSymbol
        case .machine:
            return "figure.strengthtraining.traditional"
        case .cable:
            return "cable.connector.horizontal"
        case .bodyweight:
            return "figure.core.training"
        }
    }

    /// The placeholder tile: rounded square filled with `Theme.soft(for:)`,
    /// symbol in `Theme.accent(for:)`. `muscleGroup` is the raw column value
    /// ("full_body"), so unknown strings degrade to the grey `other` accent.
    static func tile(
        slug: String,
        muscleGroup: String,
        size: CGFloat,
        equipment: Equipment? = nil
    ) -> some View {
        RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
            .fill(Theme.soft(for: muscleGroup))
            .frame(width: size, height: size)
            .overlay {
                Image(
                    systemName: symbol(
                        for: slug,
                        equipment: equipment,
                        muscleGroup: MuscleGroup(rawValue: muscleGroup))
                )
                .font(.system(size: max(16, size * 0.4), weight: .regular))
                .foregroundStyle(Theme.accent(for: muscleGroup))
            }
    }

    /// The slug of a `builtin/<slug>` image key, or an empty string for any
    /// other key — what `tile(slug:…)` wants.
    nonisolated static func slug(fromImageKey key: String?) -> String {
        guard let key, key.hasPrefix(builtinPrefix) else { return "" }
        return String(key.dropFirst(builtinPrefix.count))
    }

    /// `nonisolated` so the image store — an actor — can test a key
    /// against it without hopping to the main actor.
    nonisolated static let builtinPrefix = "builtin/"

    private nonisolated static let defaultSymbol = "dumbbell"
    private nonisolated static let cardioSymbol = "figure.run"

    /// The few seed slugs whose equipment default would be misleading. Every
    /// name here exists in SF Symbols on iOS 26.
    private nonisolated static let specialSymbols: [String: String] = [
        "treadmill": "figure.run.treadmill",
        "stationary-bike": "figure.indoor.cycle",
        "rowing-machine": "figure.rower",
        "elliptical": "figure.elliptical",
        "plank": "figure.core.training",
        "hanging-leg-raise": "figure.core.training",
        "cable-crunch": "figure.core.training",
        "ab-crunch-machine": "figure.core.training",
        "push-up": "figure.strengthtraining.functional",
        "dip": "figure.strengthtraining.functional",
        "pull-up": "figure.strengthtraining.functional",
        "chin-up": "figure.strengthtraining.functional",
        "kettlebell-swing": "figure.strengthtraining.functional",
        "farmers-walk": "figure.walk",
        "lunge": "figure.walk",
    ]
}

// MARK: - Previews

private struct BuiltinArtGallery: View {
    private let samples: [(slug: String, group: String, equipment: Equipment)] = [
        ("barbell-bench-press", "chest", .barbell),
        ("lat-pulldown", "back", .cable),
        ("leg-press", "quads", .machine),
        ("plank", "core", .bodyweight),
        ("treadmill", "cardio", .machine),
        ("kettlebell-swing", "full_body", .other),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(samples.indices, id: \.self) { index in
                HStack(spacing: Theme.Spacing.md) {
                    BuiltinArt.tile(
                        slug: samples[index].slug,
                        muscleGroup: samples[index].group,
                        size: 72,
                        equipment: samples[index].equipment)
                    Text(samples[index].slug)
                        .font(Theme.Typography.secondary)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
        .padding(Theme.Spacing.screenInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Colors.canvas)
    }
}

#Preview("Light") {
    BuiltinArtGallery()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    BuiltinArtGallery()
        .preferredColorScheme(.dark)
}
