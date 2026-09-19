import SwiftUI

@main
struct PersonalApp: App {

    /// Built once, at launch, and owned by the scene for the whole run.
    @State private var environment = AppEnvironment.live()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(environment)
                // Spec §5: sync on launch and whenever the scene comes back.
                // Both reasons run at once; the scheduler coalesces a second
                // request into the run already in flight.
                .task {
                    environment.syncScheduler.trigger(.launch)
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    environment.syncScheduler.trigger(.foreground)
                }
        }
    }
}
