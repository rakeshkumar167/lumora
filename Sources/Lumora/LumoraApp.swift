import AppKit
import SwiftUI

@main
struct LumoraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ProjectStore.sample()

    var body: some Scene {
        WindowGroup("Lumora") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 600)
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
        if let icon = AppAssets.icon { NSApp.applicationIconImage = icon }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
