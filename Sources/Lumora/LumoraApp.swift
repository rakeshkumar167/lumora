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
        .commands {
            // Replace the default (help-book) Help item with our in-app help.
            CommandGroup(replacing: .help) {
                HelpMenuButton()
            }
        }

        // Fullscreen projection output (send to a second display / projector).
        Window("Projection", id: "projection") {
            ProjectionRootView()
                .environmentObject(store)
        }

        // In-app help window, opened from the Help menu.
        Window("Lumora Help", id: "help") {
            HelpView()
        }
        .defaultSize(width: 520, height: 620)
    }
}

/// Help-menu item that opens the in-app help window.
private struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Lumora Help") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
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
