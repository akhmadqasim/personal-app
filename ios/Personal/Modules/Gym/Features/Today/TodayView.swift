import SwiftUI

/// The Today tab (spec §6, design §4): "✦ Today", the "Next up" card with its
/// Start CTA, then the history grouped by day.
///
/// It owns the navigation stack of the tab: pushing a session id shows
/// ``SessionView``, and popping back reloads, so a session that was just
/// finished or discarded shows up correctly without any cross-screen plumbing.
struct TodayView: View {

    private let environment: AppEnvironment
    private let onCreateProgram: () -> Void

    @State private var model: TodayViewModel
    @State private var path: [String] = []
    @State private var isShowingSettings = false

    /// `environment` is passed in rather than read from `@Environment` so the
    /// view model can be built once, in `init`, instead of after the first
    /// render.
    init(environment: AppEnvironment, onCreateProgram: @escaping () -> Void) {
        self.environment = environment
        self.onCreateProgram = onCreateProgram
        _model = State(
            initialValue: TodayViewModel(
                repository: environment.repository,
                scheduler: environment.syncScheduler,
                imageStore: environment.imageStore))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxl) {
                    title
                    nextUpSection
                    historySection
                }
                .padding(.horizontal, Theme.Spacing.screenInset)
                .padding(.bottom, Theme.Spacing.xxxl)
            }
            .background(Theme.Colors.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CircleIconButton(systemImage: "gearshape", accessibilityLabel: "Settings") {
                        isShowingSettings = true
                    }
                }
            }
            .navigationDestination(for: String.self) { sessionId in
                SessionView(environment: environment, sessionId: sessionId)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(environment: environment)
        }
        .toast($model.toast)
        .task {
            model.reload()
        }
        .onChange(of: path) { _, newValue in
            // Back from a session: its sets, status and duration changed.
            if newValue.isEmpty {
                model.reload()
            }
        }
        // A sync that lands brings sessions and programs from other devices.
        .onChange(of: environment.syncStatus.lastSyncedAt) { _, _ in
            model.reload()
        }
    }

    // MARK: - Header

    private var title: some View {
        Text("✦ Today")
            .font(Theme.Typography.largeTitle)
            .tracking(Theme.Typography.largeTitleTracking)
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Next up

    @ViewBuilder
    private var nextUpSection: some View {
        switch model.state {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.xxl)
        case .noProgram:
            EmptyState(
                symbol: "list.bullet.rectangle",
                title: "No program yet",
                message: "Create a program with a few days and Today will suggest what to train next.",
                action: (title: "Create program", handler: onCreateProgram))
        case .ready:
            readySection
        }
    }

    @ViewBuilder
    private var readySection: some View {
        if let nextUp = model.nextUp {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionTitle("Next up")
                GroupCard {
                    HStack(alignment: .top, spacing: Theme.Spacing.md) {
                        ExerciseArtView(art: nextUp.art, size: 72, store: model.imageStore)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(nextUp.day.name)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(2)
                            Text(nextUp.meta)
                                .font(Theme.Typography.secondary)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer(minLength: Theme.Spacing.sm)
                    }
                    PillButton(style: .primary, title: "Start session", systemImage: "play.fill") {
                        start()
                    }
                }
            }
        } else {
            EmptyState(
                symbol: "calendar",
                title: "No days in this program",
                message: "Add a day with a few exercises and it will show up here.",
                action: (title: "Open programs", handler: onCreateProgram))
        }
    }

    private func start() {
        guard let sessionId = model.startSession() else { return }
        path.append(sessionId)
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            sectionTitle("History ›")
            if model.history.isEmpty {
                EmptyState(
                    symbol: "figure.strengthtraining.traditional",
                    title: "No sessions yet",
                    message: "Start a session and it will show up here.")
            } else {
                ForEach(model.history) { group in
                    historyGroup(group)
                }
            }
        }
    }

    private func historyGroup(_ group: TodayHistoryGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.rowSpacing) {
            // Design §3 date group: "Today / Friday" — the date in `headline`,
            // the weekday behind a slash in `textTertiary`.
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Text(group.primary)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("/")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text(group.secondary)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(group.items) { item in
                Button {
                    path.append(item.id)
                } label: {
                    historyRow(item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func historyRow(_ item: TodayHistoryItem) -> some View {
        ThumbnailRow(
            thumbnail: { size in
                ExerciseArtView(art: item.art, size: size, store: model.imageStore)
            },
            caption: item.time,
            captionSymbol: "clock",
            title: item.title,
            meta: metaLines(item),
            pill: StatusPill(item.isFinished ? .completed : .inProgress))
    }

    private func metaLines(_ item: TodayHistoryItem) -> [(symbol: String, text: String)] {
        var lines: [(symbol: String, text: String)] = [("checklist", item.setsText)]
        if let duration = item.durationText {
            lines.append((symbol: "timer", text: duration))
        }
        return lines
    }

    // MARK: - Chrome

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.section)
            .foregroundStyle(Theme.Colors.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Previews

#Preview("Light") {
    TodayView(environment: AppEnvironment.preview(), onCreateProgram: {})
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    TodayView(environment: AppEnvironment.preview(), onCreateProgram: {})
        .preferredColorScheme(.dark)
}
