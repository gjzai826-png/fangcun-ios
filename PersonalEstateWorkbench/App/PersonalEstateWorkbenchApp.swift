import SwiftUI

@main
struct PersonalEstateWorkbenchApp: App {
    @State private var workspace = WorkspaceController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(workspace)
                .tint(Theme.accent)
        }
    }
}
