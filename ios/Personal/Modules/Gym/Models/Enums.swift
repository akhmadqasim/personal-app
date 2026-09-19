import Foundation

/// The muscle group an exercise trains — the API's `exercise.muscle_group`
/// values, stored verbatim as TEXT.
nonisolated enum MuscleGroup: String, Codable, Sendable, CaseIterable, Identifiable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case forearms
    case core
    case quads
    case hamstrings
    case glutes
    case calves
    case fullBody = "full_body"
    case cardio
    case other

    var id: String { rawValue }

    /// Title-cased name for chips, filters and detail headers.
    var label: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .forearms: "Forearms"
        case .core: "Core"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .glutes: "Glutes"
        case .calves: "Calves"
        case .fullBody: "Full body"
        case .cardio: "Cardio"
        case .other: "Other"
        }
    }
}

/// The equipment an exercise needs — the API's `exercise.equipment` values.
nonisolated enum Equipment: String, Codable, Sendable, CaseIterable, Identifiable {
    case barbell
    case dumbbell
    case machine
    case cable
    case bodyweight
    case other

    var id: String { rawValue }

    /// Title-cased name for chips and the exercise editor.
    var label: String {
        switch self {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .machine: "Machine"
        case .cable: "Cable"
        case .bodyweight: "Bodyweight"
        case .other: "Other"
        }
    }
}
