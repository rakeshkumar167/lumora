import AppKit
import SwiftUI

@main
struct LumoraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ProjectStore.sample()

    var body: some Scene {
        WindowGroup("Lumora") {
            WorkspaceView()
                .environmentObject(store)
                .frame(minWidth: 1200, minHeight: 700)
        }

        // Fullscreen projection output (send to a second display / projector).
        Window("Projection", id: "projection") {
            ProjectionRootView()
                .environmentObject(store)
        }
    }
}

/// Ensures the SwiftUI-package executable activates as a normal foreground app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
