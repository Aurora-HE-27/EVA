import SwiftUI

@main
struct EVAApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 920, minHeight: 620)
                .task {
                    await appState.start()
                }
        }
        .defaultSize(width: 1120, height: 760)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(width: 520, height: 420)
        }
    }
}
