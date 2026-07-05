import AppKit
import SwiftUI

/// Bundled brand assets (packaged via `resources:` in Package.swift).
enum AppAssets {
    static let icon: NSImage? = load("AppIcon")
    static let splash: NSImage? = load("Splash")

    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// The launch splash: the Lumora banner centered on black. Auto-dismisses, and
/// can be clicked to skip.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color.black
            if let banner = AppAssets.splash {
                Image(nsImage: banner)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(32)
                    .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            }
        }
        .ignoresSafeArea()
    }
}

/// Wraps the workspace and shows the splash on launch.
struct RootView: View {
    @State private var showSplash = true

    var body: some View {
        WorkspaceView()
            .overlay {
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                        .onTapGesture { dismiss() }
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { dismiss() }
                        }
                }
            }
    }

    private func dismiss() {
        guard showSplash else { return }
        withAnimation(.easeOut(duration: 0.6)) { showSplash = false }
    }
}
