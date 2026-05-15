import SwiftUI

@main
struct EchoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings window — opened via right-click on the status bar icon
        Settings {
            ContentView()
                .environment(appDelegate.notchLayoutGuide)
                .environment(appDelegate.launchAtLogin)
        }
    }
}
