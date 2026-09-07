import AppKit
import SwiftUI

@main
struct EVAApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if appState.hasCompletedOnboarding {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
                .environmentObject(appState)
                .frame(minWidth: 920, minHeight: 620)
                .task {
                    // Unit tests own model loading and fixtures; the test host
                    // must not concurrently load the user's live conversation.
                    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                        await appState.start()
                    }
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: NSApplication.willTerminateNotification
                    )
                ) { _ in
                    appState.shutdown()
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
