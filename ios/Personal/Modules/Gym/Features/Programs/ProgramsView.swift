import SwiftUI

/// Where a push from the Programs tab can land. At file scope so both the
/// stack that declares the destinations and the screens that append to it can
/// name the cases.
nonisolated enum ProgramsRoute: Hashable, Sendable {
    case program(String)
    case day(String)
    case exercises
}

/// The Programs tab (spec §6, design §4): the programs as event rows, a "+"
/// for a new one and a magnifying glass onto the exercise catalog.
///
/// It owns the navigation stack of the tab, the way ``TodayView`` owns its
/// own: popping back reloads, so a day added two screens deeper shows up in
/// the "3 days · 18 exercises" meta without any cross-screen plumbing.
struct ProgramsView: View {

    private let environment: AppEnvironment

    @State private var model: ProgramsViewModel
    /// Type-erased on purpose. The stack pushes two unrelated route types:
    /// its own ``ProgramsRoute`` and the ``ExercisesRoute`` the catalog
    /// appends two screens down. A `[ProgramsRoute]` has nowhere to put the
    /// second one, so the link would render and the tap would do nothing —
    /// silently, because `NavigationLink(value:)` has no way to complain.
    @State private var path = NavigationPath()

    init(environment: AppEnvironment) {
        self.environment = environment
        _model = State(
            initialValue: ProgramsViewModel(
                repository: environment.repository,
                scheduler: environment.syncScheduler,
                imageStore: environment.imageStore))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    title
                    list
                }
                .padding(.horizontal, Theme.Spacing.screenInset)
                .padding(.bottom, Theme.Spacing.xxxl)
            }
            .background(Theme.Colors.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CircleIconButton(
                        systemImage: "magnifyingglass",
                        accessibilityLabel: "Exercise catalog"
                    ) {
                        path.append(ProgramsRoute.exercises)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    CircleIconButton(systemImage: "plus", accessibilityLabel: "New program") {
                        model.newName = ""
                        model.isCreating = true
                    }
                }
            }
            .navigationDestination(for: ProgramsRoute.self) { route in
                destination(route)
            }
            // Registered at the root, not on the catalog that pushes it: a
            // destination declared by a pushed view stops resolving the
            // moment that view leaves the hierarchy.
            .exerciseCatalogDestination(environment: environment)
        }
        .sheet(item: $model.pendingDeletion) { row in
            SlideToConfirmSheet(
                symbol: "trash",
                title: "Delete \(row.name)",
                message: "The program and its days are removed here and on every synced device. Sessions you already logged stay in your history.",
                onConfirm: {
                    model.delete(row.id)
                })
        }
        .sheet(isPresented: $model.isCreating) {
            NewProgramSheet(name: $model.newName) {
                if let programId = model.createProgram(name: model.newName) {
                    path.append(ProgramsRoute.program(programId))
                }
            }
        }
        .toast($model.toast)
        .task {
            model.reload()
        }
        .onChange(of: path) { _, newValue in
            if newValue.isEmpty {
                model.reload()
            }
        }
    }

    // MARK: - Destinations

    @ViewBuilder
    private func destination(_ route: ProgramsRoute) -> some View {
        switch route {
        case .program(let programId):
            ProgramDetailView(environment: environment, programId: programId)
        case .day(let dayId):
            DayEditorView(environment: environment, dayId: dayId)
        case .exercises:
            // The catalog registers its own destination for the entry it
            // pushes, so it stands up on its own in a preview.
            ExerciseListView(environment: environment)
        }
    }

    // MARK: - Pieces

    private var title: some View {
        // The brand glyph leads every tab root (design §3 "Header").
        Text("✦ Programs")
            .font(Theme.Typography.largeTitle)
            .tracking(Theme.Typography.largeTitleTracking)
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var list: some View {
        if model.programs.isEmpty {
            EmptyState(
                symbol: "list.bullet.rectangle",
                title: "No programs yet",
                message: "Create one, add a few days and Today will suggest what to train next.",
                action: (title: "Create program", handler: {
                    model.newName = ""
                    model.isCreating = true
                }))
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.rowSpacing) {
                ForEach(model.programs) { row in
                    NavigationLink(value: ProgramsRoute.program(row.id)) {
                        programRow(row)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            model.makeActive(row.id)
                        } label: {
                            Label("Make active", systemImage: "checkmark.circle")
                        }
                        .disabled(row.isActive)
                        Button(role: .destructive) {
                            model.pendingDeletion = row
                        } label: {
                            Label("Delete program", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    private func programRow(_ row: ProgramRow) -> some View {
        ThumbnailRow(
            thumbnail: { ExerciseArtView(art: row.art, size: 72, store: model.imageStore) },
            title: row.name,
            meta: [("calendar", row.meta)],
            pill: Self.pill(isActive: row.isActive))
    }

    /// Written out rather than inlined as a ternary: the parameter it feeds is
    /// `StatusPill?`, and an explicit return type is one less thing for the
    /// type checker to guess.
    private static func pill(isActive: Bool) -> StatusPill? {
        guard isActive else { return nil }
        return StatusPill(.active)
    }
}

// MARK: - New program

/// The "+" sheet: one name field and a CTA (design §3 "Bottom sheet").
struct NewProgramSheet: View {

    @Binding var name: String
    var onCreate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SheetHeader(
                symbol: "list.bullet.rectangle",
                title: "New program",
                subtitle: "Give it a name; days come next.",
                onClose: { dismiss() })

            TextField("Push Pull Legs", text: $name)
                .font(Theme.Typography.body)
                .textInputAutocapitalization(.words)
                .focused($isFocused)
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(minHeight: Theme.Spacing.rowMinHeight)
                .background(
                    Theme.Colors.surfaceSecondary,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))
                .onSubmit {
                    create()
                }

            PillButton(style: .primary, title: "Create program", systemImage: "plus") {
                create()
            }
            .disabled(isBlank)

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.canvas)
        .presentationDetents([.height(300)])
        .presentationCornerRadius(Theme.Radius.sheet)
        .task {
            isFocused = true
        }
    }

    private var isBlank: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func create() {
        guard isBlank == false else { return }
        dismiss()
        onCreate()
    }
}

// MARK: - Previews

#Preview("Light") {
    ProgramsView(environment: AppEnvironment.preview())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ProgramsView(environment: AppEnvironment.preview())
        .preferredColorScheme(.dark)
}
