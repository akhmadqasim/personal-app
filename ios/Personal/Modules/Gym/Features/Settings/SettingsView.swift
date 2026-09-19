import SwiftUI

/// The Settings sheet behind Today's gear (spec §6, design §4): grouped rows
/// for the API token, sync, export and About.
struct SettingsView: View {

    @State private var model: SettingsViewModel

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTokenFocused: Bool

    init(environment: AppEnvironment) {
        _model = State(
            initialValue: SettingsViewModel(
                tokenStore: environment.tokenStore,
                syncStatus: environment.syncStatus,
                api: environment.api,
                scheduler: environment.syncScheduler))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                SheetHeader(
                    symbol: "gearshape",
                    title: "Settings",
                    subtitle: "API token, sync and export.",
                    onClose: { dismiss() })

                section("Connection") {
                    tokenCard
                }
                section("Sync") {
                    syncCard
                }
                section("Data") {
                    exportCard
                }
                section("About") {
                    aboutCard
                }

                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.cardPadding)
        }
        .background(Theme.Colors.canvas)
        .presentationDetents([.large])
        .presentationCornerRadius(Theme.Radius.sheet)
        .toast($model.toast)
        .task {
            model.load()
        }
    }

    // MARK: - Connection

    private var tokenCard: some View {
        GroupCard {
            HStack(spacing: Theme.Spacing.md) {
                Text("API token")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer(minLength: Theme.Spacing.sm)
                Text(model.hasToken ? "Saved" : "Not set")
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(
                        model.hasToken ? Theme.Colors.success : Theme.Colors.textTertiary)
            }
            .frame(minHeight: Theme.Spacing.rowMinHeight)

            SecureField("Paste your token", text: $model.tokenText)
                .font(Theme.Typography.body)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isTokenFocused)
                .submitLabel(.done)
                .onSubmit {
                    model.saveToken()
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .frame(minHeight: Theme.Spacing.rowMinHeight)
                .background(
                    Theme.Colors.surfaceSecondary,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.input, style: .continuous))

            Text("Stored in the keychain and sent as a bearer token on every request.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)

            PillButton(style: .primary, title: "Save token", systemImage: "key") {
                isTokenFocused = false
                model.saveToken()
            }

            PillButton(style: .secondary, title: "Test connection", systemImage: "bolt.horizontal") {
                Task {
                    await model.testConnection()
                }
            }
            .disabled(model.isWorking)

            if model.hasToken {
                PillButton(style: .secondary, title: "Remove token", systemImage: "trash") {
                    model.clearToken()
                }
            }
        }
    }

    // MARK: - Sync

    private var syncCard: some View {
        GroupCard {
            valueRow(
                label: "Status",
                value: model.stateText,
                tint: model.isSyncFailing ? Theme.Colors.danger : Theme.Colors.textSecondary)
            Divider().overlay(Theme.Colors.hairline)
            valueRow(
                label: "Last synced",
                value: model.lastSyncedText,
                tint: Theme.Colors.textSecondary)

            PillButton(
                style: .primary,
                title: "Sync now",
                systemImage: "arrow.triangle.2.circlepath"
            ) {
                Task {
                    await model.syncNow()
                }
            }
            .disabled(model.isWorking)
        }
    }

    // MARK: - Data

    private var exportCard: some View {
        GroupCard {
            Text("Every program, session and set the server holds, as one JSON file.")
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Colors.textSecondary)

            PillButton(style: .secondary, title: "Prepare export", systemImage: "arrow.down.doc") {
                Task {
                    await model.export()
                }
            }
            .disabled(model.isWorking)

            if let url = model.exportURL {
                ShareLink(item: url) {
                    PillButtonLabel(
                        style: .primary,
                        title: "Share \(url.lastPathComponent)",
                        systemImage: "square.and.arrow.up")
                }
            }

            if model.isWorking {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView()
                    Text("Working…")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        GroupCard {
            valueRow(label: "Personal", value: model.aboutText, tint: Theme.Colors.textSecondary)
        }
    }

    // MARK: - Chrome

    private func section(
        _ label: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func valueRow(label: String, value: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Text(label)
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: Theme.Spacing.sm)
            Text(value)
                .font(Theme.Typography.secondary)
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: Theme.Spacing.rowMinHeight)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Light") {
    SettingsView(environment: AppEnvironment.preview())
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SettingsView(environment: AppEnvironment.preview())
        .preferredColorScheme(.dark)
}
