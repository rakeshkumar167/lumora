import AppKit
import LumoraKit
import SwiftUI

/// Fullscreen projection output: just the composited surfaces on pure black,
/// scaled to fill the projector display. No room photo, no editing handles.
struct ProjectionRootView: View {
    @EnvironmentObject var store: ProjectStore

    var body: some View {
        let size = store.canvasSize
        GeometryReader { geo in
            let scale = min(geo.size.width / size.width, geo.size.height / size.height)
            ZStack {
                Color.black
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    ZStack(alignment: .topLeading) {
                        ForEach(store.surfacesInDrawOrder) { surface in
                            if surface.isVisible {
                                SurfaceContentView(surface: surface, canvasSize: size, time: t)
                            }
                        }

                        ForEach(store.lightLines) { line in
                            if line.isVisible {
                                LightLineView(line: line, canvasSize: size, time: t)
                            }
                        }
                    }
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(scale)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .background(ProjectionWindowConfigurator())
        .onAppear { store.projecting = true }
        .onDisappear { store.projecting = false }
    }
}

/// Moves the projection window to a second display (if present) and enters
/// fullscreen — matching single-projector output. Esc exits fullscreen.
private struct ProjectionWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.title = "Projection"

            // Prefer a display other than the one the editor is on (the projector).
            if let projector = NSScreen.screens.first(where: { $0 != NSScreen.main }) ?? NSScreen.main {
                window.setFrame(projector.frame, display: true)
            }

            if !window.styleMask.contains(.fullScreen) {
                window.collectionBehavior.insert(.fullScreenPrimary)
                window.toggleFullScreen(nil)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
