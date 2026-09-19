import SwiftUI
import UIKit

/// `UIImagePickerController` with `sourceType = .camera`, wrapped for SwiftUI.
///
/// SwiftUI has no camera control of its own — `PhotosPicker` only reaches the
/// library — so the one screen that needs a shutter borrows UIKit's. Callers
/// must check ``isAvailable`` first: on a simulator, and on a device whose
/// camera is restricted, presenting it throws.
struct CameraPicker: UIViewControllerRepresentable {

    /// The photo the user took.
    var onImage: (UIImage) -> Void
    /// Taken or cancelled — either way the sheet has to come down.
    var onFinish: () -> Void

    /// `false` on every simulator, so the caller can hide the button.
    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.allowsEditing = true
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    /// The delegate. `UIImagePickerControllerDelegate` is main-actor bound in
    /// the SDK, which is also where this class lives by the module's default
    /// isolation — the two agree, so no hop is needed.
    final class Coordinator: NSObject, UIImagePickerControllerDelegate,
        UINavigationControllerDelegate
    {
        private let onImage: (UIImage) -> Void
        private let onFinish: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onFinish: @escaping () -> Void) {
            self.onImage = onImage
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let edited = info[.editedImage] as? UIImage {
                onImage(edited)
            } else if let original = info[.originalImage] as? UIImage {
                onImage(original)
            }
            onFinish()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish()
        }
    }
}
