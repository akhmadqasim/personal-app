import SwiftUI

/// One program (spec §6, design §4): a `GroupCard` per day, reorderable with
/// drag handles, plus "Make active" and "+ Add day".
///
/// It is a `List` rather than a `ScrollView`: `.onMove` and swipe-to-delete
/// are list behaviours, and reimplementing drag handles by hand would buy
/// nothing. The list chrome is hidden so the cards keep the design's look.
struct ProgramDetailView: View {

    private let environment: AppEnvironment

    @State private var model: ProgramDetailViewModel
    @State private var editMode: EditMode = .inactive
    @Environment(\.dismiss) private var dismiss

    init(environment: AppEnvironment, programId: String) {
        self.environment = environment
        _model = State(
            initialValue: ProgramDetailViewModel(
                programId: programId,
                repository: environment.repository,
                scheduler: environment.syncScheduler))
    }

    var body: some View {
        List {
            headerSection
            daysSection
            addDaySection
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.canvas)
        .environment(\.editMode, $editMode)
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
                CircleIconButton(
                    systemImage: editMode.isEditing ? "checkmark" : "arrow.up.arrow.down",
                    accessibilityLabel: editMode.isEditing ? "Done reordering" : "Reorder days"
                ) {
                    withAnimation(.snappy(duration: 0.25)) {
                        editMode = editMode.isEditing ? .inactive : .active
                    }
                }
                .disabled(model.days.isEmpty)
            }
        }
        .toast($model.toast)
        .task {
            model.reload()
        }
        // The stack that owns the path is two screens up, so this screen has
        // no `onChange(of: path)` to hang a reload on: popping back from the
        // day editor only ever runs `onAppear`. `reload()` is a plain re-read,
        // so running it twice on the first appearance costs nothing.
        .onAppear {
            model.reload()
        }
        .onChange(of: model.isGone) { _, isGone in
            if isGone {
                dismiss()
            }
        }
        .sheet(isPresented: $model.isAddingDay) {
            NewDaySheet(name: $model.newDayName) {
                model.addDay(name: model.newDayName)
            }
        }
        .alert("Rename program", isPresented: $model.isRenaming) {
            TextField("Name", text: $model.renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                model.commitRename()
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            GroupCard {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(model.name)
                        .font(Theme.Typography.section)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)
                    if model.isActive {
                        StatusPill(.active)
                    }
                    Spacer(minLength: 0)
                }
                Text(summary)
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)

                if model.isActive == false {
                    PillButton(style: .primary, title: "Make active", systemImage: "checkmark") {
                        model.makeActive()
                    }
                }
                PillButton(style: .secondary, title: "Rename", systemImage: "pencil") {
                    model.beginRename()
                }
            }
            .plainListRow()
        }
    }

    private var summary: String {
        let count = model.days.count
        if count == 0 {
            return "No days yet"
        }
        let noun = count == 1 ? "day" : "days"
        return "\(count) \(noun) · Today rotates through them in this order"
    }

    @ViewBuilder
    private var daysSection: some View {
        if model.days.isEmpty {
            Section {
                EmptyState(
                    symbol: "calendar",
                    title: "No days yet",
                    message: "Add a day, then fill it with the exercises you train that session.",
                    action: (title: "Add day", handler: { beginAddDay() }))
                    .plainListRow()
            }
        } else {
            Section {
                ForEach(model.days) { day in
                    NavigationLink(value: ProgramsRoute.day(day.id)) {
                        dayCard(day)
                    }
                    .plainListRow()
                }
                .onMove { source, destination in
                    model.move(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    model.delete(at: offsets)
                }
            } header: {
                sectionLabel("Days")
            }
        }
    }

    private var addDaySection: some View {
        Section {
            PillButton(style: .secondary, title: "Add day", systemImage: "plus") {
                beginAddDay()
            }
            .plainListRow()
        }
    }

    // MARK: - Pieces

    private func dayCard(_ day: ProgramDayRow) -> some View {
        GroupCard(spacing: Theme.Spacing.xs) {
            Text(day.name)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
            Text(day.meta)
                .font(Theme.Typography.secondary)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Colors.textTertiary)
            .textCase(nil)
            .padding(.horizontal, Theme.Spacing.screenInset)
            .padding(.top, Theme.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }

    private func beginAddDay() {
        model.newDayName = ""
        model.isAddingDay = true
    }
}

// MARK: - List row chrome

extension View {
    /// Strips a `List` row back to the design system: no separator, no fill,
    /// the screen's own inset and the row gap of design §3.
    func plainListRow() -> some View {
        listRowInsets(
            EdgeInsets(
                top: Theme.Spacing.sm,
                leading: Theme.Spacing.screenInset,
                bottom: Theme.Spacing.sm,
                trailing: Theme.Spacing.screenInset)
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

// MARK: - New day

/// The "+ Add day" sheet: one name field and a CTA.
struct NewDaySheet: View {

    @Binding var name: String
    var onCreate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SheetHeader(
                symbol: "calendar",
                title: "New day",
                subtitle: "\"Push A\", \"Legs\" — whatever you call that session.",
                onClose: { dismiss() })

            TextField("Push A", text: $name)
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

            PillButton(style: .primary, title: "Add day", systemImage: "plus") {
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

#Preview {
    NavigationStack {
        ProgramDetailView(environment: AppEnvironment.preview(), programId: "preview")
    }
}
