import PhotosUI
import SwiftUI
import UIKit

/// Drives one catalog entry's detail page, including the photo upload
/// (spec §7).
///
/// Uploading is gated on two things the user can do nothing about from here —
/// a token and a sync that is not failing — so the screen says which one is
/// missing instead of letting a `PUT` fail into a toast.
@Observable
@MainActor
final class ExerciseDetailViewModel {

    let exerciseId: String
    let imageStore: ImageStore?

    private(set) var name = ""
    private(set) var muscleLabel = ""
    private(set) var equipmentLabel = ""
    private(set) var muscleGroup = MuscleGroup.other.rawValue
    private(set) var notes: String?
    private(set) var art: ExerciseArt?
    /// The custom photo behind the content; `nil` for built-in art, which
    /// leaves the background plain `canvas` (spec §7).
    private(set) var ambientImage: UIImage?
    private(set) var hasPhoto = false
    private(set) var isUploading = false
    /// Set when the exercise is gone; the screen pops.
    private(set) var isGone = false

    var toast: ToastItem?
    var isEditing = false
    var isTakingPhoto = false

    let syncStatus: SyncStatus

    private let repository: GymRepository
    private let scheduler: SyncScheduler?
    private let api: APIClient
    private let tokenStore: any TokenStore

    init(
        exerciseId: String,
        repository: GymRepository,
        api: APIClient,
        tokenStore: any TokenStore,
        syncStatus: SyncStatus,
        scheduler: SyncScheduler? = nil,
        imageStore: ImageStore? = nil
    ) {
        self.exerciseId = exerciseId
        self.repository = repository
        self.api = api
        self.tokenStore = tokenStore
        self.syncStatus = syncStatus
        self.scheduler = scheduler
        self.imageStore = imageStore
    }

    // MARK: - Reading

    func load() {
        guard let found = try? repository.exercise(id: exerciseId) else {
            isGone = true
            return
        }
        name = found.name
        muscleLabel = found.muscleGroup.label
        equipmentLabel = found.equipment.label
        muscleGroup = found.muscleGroup.rawValue
        notes = found.notes
        art = ExerciseArt(found)
        hasPhoto = Self.isCustomPhoto(found.imageKey)
    }

    func loadAmbientImage() async {
        ambientImage = nil
        guard let key = art?.imageKey else { return }
        guard let store = imageStore else { return }
        guard let data = await store.imageData(for: key) else { return }
        ambientImage = UIImage(data: data)
    }

    /// A `builtin/…` key is art, not a photo: it can be replaced but not
    /// removed.
    nonisolated static func isCustomPhoto(_ key: String?) -> Bool {
        guard let key, key.isEmpty == false else { return false }
        return key.hasPrefix(BuiltinArt.builtinPrefix) == false
    }

    // MARK: - Photo

    /// Spec §6/§7: the upload needs a bearer token and a sync that is not in
    /// an error state.
    var canUploadPhoto: Bool {
        guard isUploading == false else { return false }
        guard hasToken else { return false }
        return isSyncFailing == false
    }

    /// Why the photo buttons are dead, or `nil` when they are not.
    var uploadHint: String? {
        if isUploading {
            return "Uploading…"
        }
        if hasToken == false {
            return "Add your API token in Settings to upload a photo."
        }
        if isSyncFailing {
            return "Sync is failing right now. Fix that first, then try again."
        }
        return nil
    }

    private var hasToken: Bool {
        guard let token = tokenStore.token() else { return false }
        return token.isEmpty == false
    }

    private var isSyncFailing: Bool {
        if case .error = syncStatus.state {
            return true
        }
        return false
    }

    /// Resize → `PUT` → `setImageKey` → sync (spec §7).
    func upload(_ image: UIImage) async {
        guard canUploadPhoto else { return }
        isUploading = true
        do {
            _ = try await ImageUploader.upload(
                image,
                exerciseId: exerciseId,
                api: api,
                repository: repository)
            isUploading = false
            scheduler?.trigger(.afterWrite)
            load()
            await loadAmbientImage()
            Haptics.success()
            toast = .success("Photo updated")
        } catch let error as ApiError {
            isUploading = false
            Haptics.error()
            toast = .error(error.message)
        } catch {
            isUploading = false
            Haptics.error()
            toast = .error("Could not upload the photo.")
        }
    }

    /// Drops the photo locally; the bytes stay on the server, where keys are
    /// immutable.
    func removePhoto() {
        do {
            try repository.setImageKey(exerciseId: exerciseId, key: nil)
            scheduler?.trigger(.afterWrite)
            load()
            ambientImage = nil
            toast = .success("Photo removed")
        } catch {
            toast = .error("Could not remove the photo.")
        }
    }
}

/// One catalog entry (spec §6, design §4): the ambient background of its own
/// photo, the title, muscle and equipment chips, notes, and the photo actions.
struct ExerciseDetailView: View {

    private let environment: AppEnvironment

    @State private var model: ExerciseDetailViewModel
    @State private var photoItem: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss

    init(environment: AppEnvironment, exerciseId: String) {
        self.environment = environment
        _model = State(
            initialValue: ExerciseDetailViewModel(
                exerciseId: exerciseId,
                repository: environment.repository,
                api: environment.api,
                tokenStore: environment.tokenStore,
                syncStatus: environment.syncStatus,
                scheduler: environment.syncScheduler,
                imageStore: environment.imageStore))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                hero
                chips
                notesSection
                photoSection
            }
            .padding(.horizontal, Theme.Spacing.screenInset)
            .padding(.bottom, Theme.Spacing.xxxl)
        }
        .background {
            AmbientBackground(image: model.ambientImage)
        }
        .navigationTitle(model.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CircleIconButton(systemImage: "chevron.left", accessibilityLabel: "Back") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                CircleIconButton(systemImage: "square.and.pencil", accessibilityLabel: "Edit") {
                    model.isEditing = true
                }
            }
        }
        .toast($model.toast)
        .task {
            model.load()
        }
        .task(id: model.art) {
            await model.loadAmbientImage()
        }
        .onChange(of: model.isGone) { _, isGone in
            if isGone {
                dismiss()
            }
        }
        .sheet(isPresented: $model.isEditing) {
            ExerciseEditorView(
                repository: environment.repository,
                scheduler: environment.syncScheduler,
                exerciseId: model.exerciseId,
                onSaved: { _ in
                    model.load()
                })
        }
        .fullScreenCover(isPresented: $model.isTakingPhoto) {
            CameraPicker(
                onImage: { image in
                    Task {
                        await model.upload(image)
                    }
                },
                onFinish: {
                    model.isTakingPhoto = false
                })
            .ignoresSafeArea()
        }
        // `task(id:)` rather than `onChange`: loading the bytes is async and
        // this way a second pick cancels the first.
        .task(id: photoItem) {
            await loadPickedPhoto()
        }
    }

    // MARK: - Pieces

    private var hero: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            ExerciseArtView(art: model.art, size: 96, store: model.imageStore)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(model.name)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(3)
                    .accessibilityAddTraits(.isHeader)
                if model.isUploading {
                    HStack(spacing: Theme.Spacing.sm) {
                        ProgressView()
                        Text("Uploading photo…")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var chips: some View {
        HStack(spacing: Theme.Spacing.sm) {
            chip(model.muscleLabel, tint: Theme.accent(for: model.muscleGroup))
            chip(model.equipmentLabel, tint: Theme.Colors.textSecondary)
            Spacer(minLength: 0)
        }
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(Theme.Typography.secondary)
            .foregroundStyle(tint)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(minHeight: 36)
            .background(Theme.Colors.surface, in: Capsule())
            .overlay {
                Capsule().strokeBorder(Theme.Colors.hairline, lineWidth: 1)
            }
    }

    @ViewBuilder
    private var notesSection: some View {
        if let notes = model.notes, notes.isEmpty == false {
            GroupCard(spacing: Theme.Spacing.sm) {
                Text("Notes")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text(notes)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
    }

    private var photoSection: some View {
        GroupCard(spacing: Theme.Spacing.md) {
            Text("Photo")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)

            PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                PillButtonLabel(
                    style: .secondary,
                    title: "Choose from library",
                    systemImage: "photo.on.rectangle")
            }
            .disabled(model.canUploadPhoto == false)

            if CameraPicker.isAvailable {
                PillButton(
                    style: .secondary,
                    title: "Take a photo",
                    systemImage: "camera"
                ) {
                    model.isTakingPhoto = true
                }
                .disabled(model.canUploadPhoto == false)
            }

            if model.hasPhoto {
                PillButton(style: .destructive, title: "Remove photo", systemImage: "trash") {
                    model.removePhoto()
                }
            }

            if let hint = model.uploadHint {
                Text(hint)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    /// `PhotosPickerItem` hands back bytes; `UIImage` is built here, on the
    /// main actor, because it is not `Sendable`.
    private func loadPickedPhoto() async {
        guard let photoItem else { return }
        let data = try? await photoItem.loadTransferable(type: Data.self)
        self.photoItem = nil
        guard let data else {
            model.toast = .error("Could not read that photo.")
            return
        }
        guard let image = UIImage(data: data) else {
            model.toast = .error("Could not read that photo.")
            return
        }
        await model.upload(image)
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        ExerciseDetailView(environment: AppEnvironment.preview(), exerciseId: "preview")
    }
}
