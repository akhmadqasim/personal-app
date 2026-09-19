import UIKit

/// The two haptics the design system asks for (§6): `.success` when a session
/// is finished, `.selection` when a set is completed or a segment changes.
///
/// Main-actor isolated by the module default, which is where UIKit's feedback
/// generators belong anyway. Generators are created per call: they are cheap,
/// and keeping one alive only matters when you `prepare()` ahead of a gesture.
enum Haptics {

    /// A session was saved, a PR was hit — something finished well.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Something went wrong and the user has to act.
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// A discrete choice changed: a set ticked off, a segment tapped.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
