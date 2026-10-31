import AppKit
import LumoraKit
import SwiftUI

/// Fullscreen projection output: just the composited surfaces on pure black,
/// scaled to fill the projector display. No room photo, no editing handles.
struct ProjectionRootView: View {
    @EnvironmentObject var store: ProjectStore
    @State private var startRef: Double?
    @StateObject private var windowRef = ProjectionWindowRef()

    var body: some View {
        let size = store.canvasSize
        GeometryReader { geo in
            let scale = min(geo.size.width / size.width, geo.size.height / size.height)
            ZStack {
                Color.black
                if store.calibrating {
                    CalibrationPatternView()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    // Which scene is playing now (auto-advance + loop by duration).
                    let elapsed = t - (startRef ?? t)
                    let index = SceneTimeline.index(at: elapsed, durations: store.scenes.map(\.duration))
                    let scene = store.scenes.indices.contains(index) ? store.scenes[index] : nil

                    ZStack(alignment: .topLeading) {
                        if let scene {
                            ForEach(scene.surfacesInDrawOrder) { surface in
                                if surface.isVisible {
                                    SurfaceContentView(surface: surface, canvasSize: size, time: t)
                                }
                            }
                            ForEach(scene.lightLines) { line in
                                if line.isVisible {
                                    LightLineView(line: line, canvasSize: size, time: t)
                                }
                            }
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(scale)
                }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .background(ProjectionWindowConfigurator(windowRef: windowRef))
        .onAppear {
            store.projecting = true
            startRef = Date.timeIntervalSinceReferenceDate   // start at scene 1
            windowRef.enterFullScreen()   // re-applies on every Start (see below)
        }
        .onDisappear { store.projecting = false }
    }
}

/// Holds the projection's host window and drives it fullscreen onto the
/// projector display. `enterFullScreen()` is invoked from `ProjectionRootView`'s
/// `onAppear` so it re-applies on **every** Start: SwiftUI reuses a single
/// NSWindow/NSView for a `Window` scene, so the view-attach hooks
/// (`makeNSView`/`viewDidMoveToWindow`) fire only on the first open and can't
/// be relied on to reconfigure subsequent Starts. `onAppear`, by contrast,
/// fires each time the window reopens.
final class ProjectionWindowRef: ObservableObject {
    /// Captured once the configurator attaches; the same window persists across
    /// dismiss/reopen for a `Window` scene, so this stays valid.
    weak var window: NSWindow?

    func enterFullScreen() {
        // Let the (re)opened window settle before moving/fullscreening it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let window = self?.window else { return }
            window.title = "Projection"
            window.collectionBehavior.insert(.fullScreenPrimary)
            // Prefer a display other than the editor's (the projector).
            let projector = NSScreen.screens.first { $0 != NSScreen.main } ?? NSScreen.main
            guard let projector else { return }
            if !window.styleMask.contains(.fullScreen) {
                window.setFrame(projector.frame, display: true)
                window.toggleFullScreen(nil)
            }
        }
    }
}

/// Captures the projection's host window into `windowRef` so `onAppear` can
/// drive it fullscreen on every Start.
private struct ProjectionWindowConfigurator: NSViewRepresentable {
    let windowRef: ProjectionWindowRef

    func makeNSView(context: Context) -> NSView { ConfigView(windowRef: windowRef) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class ConfigView: NSView {
        let windowRef: ProjectionWindowRef

        init(windowRef: ProjectionWindowRef) {
            self.windowRef = windowRef
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { windowRef.window = window }
        }
    }
}
