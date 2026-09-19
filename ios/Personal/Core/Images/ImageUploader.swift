import Foundation
import UIKit

/// Sends a photo the user picked for an exercise to the server (spec §7).
///
/// The whole flow is `@MainActor`: `UIImage` is not `Sendable`, so the resize
/// has to happen where the image already is. Only bytes cross to the API
/// actor. On success the new `image_key` is written to the exercise, which
/// marks the row dirty and lets the next sync carry it.
enum ImageUploader {

    /// Longest side of the uploaded JPEG.
    static let maxPixelSide: CGFloat = 1024
    /// JPEG quality of the uploaded photo.
    static let compressionQuality: CGFloat = 0.8

    /// Uploads `image` and returns the key the server assigned.
    @MainActor
    @discardableResult
    static func upload(
        _ image: UIImage,
        exerciseId: String,
        api: APIClient,
        repository: GymRepository
    ) async throws -> String {
        guard let data = jpegData(from: image) else {
            throw ApiError.unsupportedMediaType
        }
        let response = try await api.putBytes(
            "/api/gym/exercises/\(exerciseId)/image",
            data: data,
            contentType: "image/jpeg")
        guard let key = response["image_key"], key.isEmpty == false else {
            throw ApiError.decoding
        }
        try repository.setImageKey(exerciseId: exerciseId, key: key)
        return key
    }

    /// The bytes that go on the wire: downscaled, then JPEG at 0.8.
    @MainActor
    static func jpegData(from image: UIImage) -> Data? {
        resized(image).jpegData(compressionQuality: compressionQuality)
    }

    /// Scales the longest side down to `maxPixelSide`. An image already small
    /// enough is returned untouched — re-rendering it would only cost quality.
    @MainActor
    static func resized(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxPixelSide, longest > 0 else { return image }
        let scale = maxPixelSide / longest
        let target = CGSize(
            width: (image.size.width * scale).rounded(),
            height: (image.size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        // Point size == pixel size: the server stores pixels, not points.
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
