import AppKit
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

/// Outline + editing affordances for the selected surface.
///
/// - `.arrow`: draggable corner handles to warp the quad.
/// - `.hand`: drag anywhere inside to translate the whole surface.
private struct HandlesOverlay: View {
    @EnvironmentObject var store: ProjectStore
    let surface: Surface
    let canvasSize: CGSize
    @State private var moveStart: [CGPoint]?

    var body: some View {
        let pts = surface.quadPoints(in: canvasSize)
        ZStack {
            outline(pts)

            if store.tool == .hand {
                moveArea(pts)
            } else {
                cornerHandles(pts)
            }
        }
        .allowsHitTesting(true)
    }

    private func outline(_ pts: [CGPoint]) -> some View {
        ZStack {
            quadPath(pts).stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            quadPath(pts).stroke(Color.accentColor,
                                 style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
    }

    // MARK: Hand — move the whole surface

    private func moveArea(_ pts: [CGPoint]) -> some View {
        let quad = quadPath(pts)
        return quad
            .fill(Color.accentColor.opacity(0.12))
            .overlay(
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 2)
                    .position(centroid(pts))
            )
            .contentShape(quad)
            .gesture(moveGesture)
            .onHover { inside in
                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
    }

    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .named("canvas"))
            .onChanged { value in
                let start = moveStart ?? surface.points
                if moveStart == nil { moveStart = surface.points }
                // Clamp the delta so the whole quad stays in bounds without
                // distorting (translate all four corners by the same amount).
                let dxRaw = value.translation.width / canvasSize.width
                let dyRaw = value.translation.height / canvasSize.height
                let minX = start.map(\.x).min() ?? 0
                let maxX = start.map(\.x).max() ?? 1
                let minY = start.map(\.y).min() ?? 0
                let maxY = start.map(\.y).max() ?? 1
                let dx = min(max(dxRaw, -minX), 1 - maxX)
                let dy = min(max(dyRaw, -minY), 1 - maxY)
                let moved = start.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
                store.update(surface.id) { $0.points = moved }
            }
            .onEnded { _ in moveStart = nil }
    }

    // MARK: Arrow — warp via corner handles

    private func cornerHandles(_ pts: [CGPoint]) -> some View {
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

    private func quadPath(_ pts: [CGPoint]) -> Path {
        Path { p in
            p.addLines(pts)
            p.closeSubpath()
        }
    }

    private func centroid(_ pts: [CGPoint]) -> CGPoint {
        let n = CGFloat(max(pts.count, 1))
        let sx = pts.reduce(0) { $0 + $1.x }
        let sy = pts.reduce(0) { $0 + $1.y }
        return CGPoint(x: sx / n, y: sy / n)
    }
}
