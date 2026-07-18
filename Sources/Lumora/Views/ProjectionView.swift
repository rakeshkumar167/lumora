import AppKit
import LumoraKit
import SwiftUI

/// Fullscreen projection output: just the composited surfaces on pure black,
/// scaled to fill the projector display. No room photo, no editing handles.
struct ProjectionRootView: View {
    @EnvironmentObject var store: ProjectStore
    @State private var startRef: Double?

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
        .background(ProjectionWindowConfigurator())
        .onAppear {
            store.projecting = true
            startRef = Date.timeIntervalSinceReferenceDate   // start at scene 1
        }
        .onDisappear { store.projecting = false }
    }
}

/// Moves the projection window to a second display (if present) and enters
/// fullscreen — matching single-projector output. Esc exits fullscreen.
private struct ProjectionWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ConfigView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Configures its host window every time it attaches to one — so the
    /// move-to-projector + fullscreen reapplies on each Start (not only the
    /// first). A one-shot in `makeNSView` doesn't re-run when the window is
    /// closed and reopened, which left the second Start windowed.
    final class ConfigView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
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
}
