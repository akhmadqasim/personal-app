import SwiftUI

/// The three tabs, at file scope: nesting the enum inside ``RootTabView``
/// would shadow SwiftUI's own `Tab` inside the body.
nonisolated enum RootTab: Hashable, Sendable {
    case today
    case programs
    case progress
}

/// Floating capsule tab bar: Today · Programs · Progress.
///
/// The appearance is the system Liquid Glass tab bar tinted with `ink`; it
/// minimises as the content scrolls down (iOS 26) and content scrolls beneath it.
///
/// Progress is a placeholder until task 7; Today's empty state switches to
/// Programs through ``selection``, which is why the tab choice lives here
/// rather than inside `TabView`'s own storage.
struct RootTabView: View {

    @Environment(AppEnvironment.self) private var environment

    @State private var selection: RootTab = .today

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: RootTab.today) {
                TodayView(environment: environment) {
                    selection = .programs
                }
            }
            Tab("Programs", systemImage: "list.bullet.rectangle", value: RootTab.programs) {
                ProgramsView(environment: environment)
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis", value: RootTab.progress) {
                NavigationStack {
                    placeholder("Progress — Task 7")
                        .navigationTitle("Progress")
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Theme.Colors.ink)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.secondary)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.canvas)
    }
}

#Preview {
    RootTabView()
        .environment(AppEnvironment.preview())
}
