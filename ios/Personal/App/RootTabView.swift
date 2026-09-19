import SwiftUI

/// Floating capsule tab bar: Today · Programs · Progress.
///
/// The appearance is the system Liquid Glass tab bar tinted with `ink`; it
/// minimises as the content scrolls down (iOS 26) and content scrolls beneath it.
struct RootTabView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "sun.max") {
                NavigationStack {
                    Text("Today")
                        .navigationTitle("Today")
                }
            }
            Tab("Programs", systemImage: "list.bullet.rectangle") {
                NavigationStack {
                    Text("Programs")
                        .navigationTitle("Programs")
                }
            }
            Tab("Progress", systemImage: "chart.line.uptrend.xyaxis") {
                NavigationStack {
                    Text("Progress")
                        .navigationTitle("Progress")
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tint(Theme.Colors.ink)
    }
}

#Preview {
    RootTabView()
        .environment(AppEnvironment.shared)
}
