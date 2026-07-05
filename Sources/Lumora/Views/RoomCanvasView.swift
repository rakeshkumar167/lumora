import LumoraKit
import SwiftUI

/// The room photo with all surfaces composited on top (live preview), plus
/// draggable corner handles for the selected surface.
struct RoomCanvasView: View {
    @EnvironmentObject var store: ProjectStore

    var body: some View {
        let size = store.canvasSize
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                Image(nsImage: store.roomImage)
                    .resizable()
                    .frame(width: size.width, height: size.height)

                ForEach(store.surfaces) { surface in
                    if surface.isVisible {
                        SurfaceContentView(surface: surface, canvasSize: size, time: t)
                    }
                }

                if let selected = store.selected {
                    HandlesOverlay(surface: selected, canvasSize: size)
                }
            }
            .frame(width: size.width, height: size.height)
            .coordinateSpace(name: "canvas")
            .overlay(Rectangle().stroke(Color.black.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
    }
}

/// Corner handles + outline for the selected surface. Dragging a handle
/// rewrites the surface's normalized corner point.
private struct HandlesOverlay: View {
    @EnvironmentObject var store: ProjectStore
    let surface: Surface
    let canvasSize: CGSize

    var body: some View {
        let pts = surface.quadPoints(in: canvasSize)
        ZStack {
            Path { p in
                p.addLines(pts)
                p.closeSubpath()
            }
            .stroke(Color.white.opacity(0.9), lineWidth: 1.5)

            Path { p in
                p.addLines(pts)
                p.closeSubpath()
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))

            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 2.5))
                    .frame(width: 15, height: 15)
                    .position(pts[i])
                    .gesture(
                        DragGesture(coordinateSpace: .named("canvas"))
                            .onChanged { value in
                                let nx = min(max(value.location.x / canvasSize.width, 0), 1)
                                let ny = min(max(value.location.y / canvasSize.height, 0), 1)
                                store.update(surface.id) { $0.points[i] = CGPoint(x: nx, y: ny) }
                            }
                    )
            }
        }
        .allowsHitTesting(true)
    }
}
