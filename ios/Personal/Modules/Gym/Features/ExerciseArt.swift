import Foundation
import SwiftUI

/// Everything a screen needs to draw one exercise's tile, snapshotted out of
/// the record so view models can stay `Sendable` and free of GRDB types.
///
/// `muscleGroup` is the raw `muscle_group` column value ("full_body"), which
/// is what ``Theme/accent(for:)`` and ``BuiltinArt/tile(slug:muscleGroup:size:equipment:)``
/// expect.
nonisolated struct ExerciseArt: Equatable, Sendable {

    var imageKey: String?
    var muscleGroup: String
    var equipment: Equipment?

    init(
        imageKey: String? = nil,
        muscleGroup: String = MuscleGroup.other.rawValue,
        equipment: Equipment? = nil
    ) {
        self.imageKey = imageKey
        self.muscleGroup = muscleGroup
        self.equipment = equipment
    }

    init(_ exercise: Exercise) {
        self.init(
            imageKey: exercise.imageKey,
            muscleGroup: exercise.muscleGroup.rawValue,
            equipment: exercise.equipment)
    }
}

/// ``ExerciseImage`` fed from an ``ExerciseArt``, with the generic `other`
/// tile as the fallback when there is no art at all.
struct ExerciseArtView: View {

    var art: ExerciseArt?
    var size: CGFloat
    var store: ImageStore?

    init(art: ExerciseArt?, size: CGFloat, store: ImageStore? = nil) {
        self.art = art
        self.size = size
        self.store = store
    }

    var body: some View {
        ExerciseImage(
            key: art?.imageKey,
            muscleGroup: art?.muscleGroup ?? MuscleGroup.other.rawValue,
            size: size,
            store: store,
            equipment: art?.equipment)
    }
}

/// Weights print without a trailing ".0": "60", "57.5" (spec §6 captions and
/// the `numeric` set rows).
nonisolated enum WeightFormat {
    static func plain(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded.rounded()))
        }
        return String(format: "%.1f", rounded)
    }
}
