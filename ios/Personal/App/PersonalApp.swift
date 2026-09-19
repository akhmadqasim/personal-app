import SwiftUI

@main
struct PersonalApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(AppEnvironment.shared)
        }
    }
}
