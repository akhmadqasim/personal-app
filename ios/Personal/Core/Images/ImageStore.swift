import CryptoKit
import Foundation
import SwiftUI
import UIKit

/// Resolves an exercise `image_key` to bytes (spec §7).
///
/// Three kinds of key:
///
/// - `nil` — nothing to load; the caller draws `BuiltinArt.tile`.
/// - `builtin/<slug>` — an asset in the bundle. Assets are resolved on the
///   caller's side with `UIImage(named:)` (see ``ExerciseImage``) because
///   `UIImage` is not `Sendable` and must not cross this actor's boundary;
///   this actor answers `nil` for those keys.
/// - `exercises/…` — a user photo: memory cache, then
///   `Caches/images/<sha256(key)>`, then `GET /api/gym/images/{key}`. Keys are
///   immutable, so a cached file never goes stale.
///
/// The actor hands back `Data`, not `UIImage`: `UIImage` is not `Sendable`, so
/// the image is built on the main actor by whoever shows it.
actor ImageStore {

    private let api: APIClient
    private let cacheDirectory: URL
    private var memory: [String: Data] = [:]

    init(api: APIClient, cacheDirectory: URL = ImageStore.defaultCacheDirectory()) {
        self.api = api
        self.cacheDirectory = cacheDirectory
    }

    /// `Caches/images` — evictable by the system, which is right for a cache
    /// that can always be refilled from the server.
    nonisolated static func defaultCacheDirectory() -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let base = caches.first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appending(path: "images")
    }

    /// The bytes behind `key`, or `nil` when there are none to be had —
    /// offline, unknown key, or a `builtin/` key.
    func imageData(for key: String?) async -> Data? {
        guard let key, key.isEmpty == false else { return nil }
        guard key.hasPrefix(BuiltinArt.builtinPrefix) == false else { return nil }

        if let cached = memory[key] {
            return cached
        }
        let file = fileURL(for: key)
        if let onDisk = try? Data(contentsOf: file), onDisk.isEmpty == false {
            memory[key] = onDisk
            return onDisk
        }
        guard let response = try? await api.getData("/api/gym/images/\(key)") else {
            return nil
        }
        let data = response.0
        guard data.isEmpty == false else { return nil }
        memory[key] = data
        writeToCache(data, at: file)
        return data
    }

    /// Drops the in-memory half of the cache; the files stay.
    func clearMemoryCache() {
        memory.removeAll()
    }

    /// Where `key` is cached on disk.
    nonisolated func fileURL(for key: String) -> URL {
        cacheDirectory.appending(path: Self.cacheFileName(for: key))
    }

    /// SHA-256 of the key, hex — a flat, collision-free, slash-free file name
    /// for a key like `exercises/2026/uuid.jpg`.
    nonisolated static func cacheFileName(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func writeToCache(_ data: Data, at file: URL) {
        let manager = FileManager.default
        try? manager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }
}

// MARK: - The view that shows one

/// Draws an exercise image at `size`: the built-in tile first, replaced by the
/// asset or the downloaded photo once there is one.
///
/// It owns the `UIImage`, which is why it is `@MainActor`: the store only ever
/// deals in `Data`.
@MainActor
struct ExerciseImage: View {

    var key: String?
    /// The raw `muscle_group` column value — it picks the fallback tint.
    var muscleGroup: String
    var size: CGFloat
    var store: ImageStore?
    var equipment: Equipment?

    @State private var image: UIImage?

    init(
        key: String?,
        muscleGroup: String,
        size: CGFloat,
        store: ImageStore? = nil,
        equipment: Equipment? = nil
    ) {
        self.key = key
        self.muscleGroup = muscleGroup
        self.size = size
        self.store = store
        self.equipment = equipment
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous))
            .task(id: key) {
                await load()
            }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            BuiltinArt.tile(
                slug: BuiltinArt.slug(fromImageKey: key),
                muscleGroup: muscleGroup,
                size: size,
                equipment: equipment)
        }
    }

    private func load() async {
        image = nil
        guard let key else { return }
        if let assetName = Self.assetName(for: key) {
            image = UIImage(named: assetName)
            return
        }
        guard let store else { return }
        let data = await store.imageData(for: key)
        guard let data else { return }
        image = UIImage(data: data)
    }

    /// `builtin/push-up` → `Builtin/push-up`, the asset catalog folder.
    private static func assetName(for key: String) -> String? {
        guard key.hasPrefix(BuiltinArt.builtinPrefix) else { return nil }
        return "Builtin/" + String(key.dropFirst(BuiltinArt.builtinPrefix.count))
    }
}

// MARK: - Previews

#Preview("Light") {
    HStack(spacing: Theme.Spacing.md) {
        ExerciseImage(key: nil, muscleGroup: "chest", size: 72)
        ExerciseImage(key: "builtin/lat-pulldown", muscleGroup: "back", size: 72)
    }
    .padding(Theme.Spacing.screenInset)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Theme.Colors.canvas)
    .preferredColorScheme(.light)
}

#Preview("Dark") {
    HStack(spacing: Theme.Spacing.md) {
        ExerciseImage(key: nil, muscleGroup: "chest", size: 72)
        ExerciseImage(key: "builtin/lat-pulldown", muscleGroup: "back", size: 72)
    }
    .padding(Theme.Spacing.screenInset)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(Theme.Colors.canvas)
    .preferredColorScheme(.dark)
}
