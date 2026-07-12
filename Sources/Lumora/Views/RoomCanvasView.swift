import AppKit
import LumoraKit
import SwiftUI

/// The room photo with all surfaces composited on top (live preview), plus
/// draggable corner handles for the selected surface.
struct RoomCanvasView: View {
    @EnvironmentObject var store: ProjectStore

    var body: some View {
        let canvas = store.canvasSize
        // Scale the canvas to fit the available area (aspect-preserving, never
        // upscaled past native) so it is always fully visible, even on a small
        // screen. All child geometry + the "canvas" coordinate space use this
        // fitted size, so drag handles stay correct.
        GeometryReader { geo in
            let scale = min(geo.size.width / canvas.width, geo.size.height / canvas.height, 1)
            let size = CGSize(width: canvas.width * scale, height: canvas.height * scale)
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    Image(nsImage: store.roomImage)
                        .resizable()
                        .frame(width: size.width, height: size.height)

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

                    if let selectedLine = store.selectedLine {
                        LightLineHandlesOverlay(line: selectedLine, canvasSize: size)
                            .id(selectedLine.id)
                    } else if let selected = store.selected {
                        HandlesOverlay(surface: selected, canvasSize: size)
                    }
                }
                .frame(width: size.width, height: size.height)
                .coordinateSpace(name: "canvas")
                .overlay(Rectangle().stroke(Color.black.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }
}

/// Outline + editing affordances for the selected surface. All geometry is
/// drawn in *display* space (i.e. with the surface's rotation applied).
///
/// - `.arrow`: draggable corner handles to warp the quad, plus a rotation knob.
/// - `.hand`: drag anywhere inside to translate the whole surface.
private struct HandlesOverlay: View {
    @EnvironmentObject var store: ProjectStore
    let surface: Surface
    let canvasSize: CGSize
    @State private var moveStart: [CGPoint]?

    private var rotation: Double { surface.rotation }

    /// Rotation pivot in canvas coordinates (the shape's center).
    private var pivot: CGPoint {
        CGPoint(x: surface.center.x * canvasSize.width,
                y: surface.center.y * canvasSize.height)
    }

    var body: some View {
        let pts = surface.displayQuadPoints(in: canvasSize)
        ZStack {
            outline(pts)

            if store.tool == .hand {
                moveArea(pts)
            } else {
                cornerHandles(pts)
                rotationKnob()
            }
        }
        .allowsHitTesting(true)
    }

    private func outline(_ pts: [CGPoint]) -> some View {
        ZStack {
            shapePath(pts).stroke(Color.white.opacity(0.9), lineWidth: 1.5)
            shapePath(pts).stroke(Color.accentColor,
                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
    }

    // MARK: Hand — move the whole surface

    private func moveArea(_ pts: [CGPoint]) -> some View {
        let quad = shapePath(pts)
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
        ForEach(0..<pts.count, id: \.self) { i in
            Circle()
                .fill(.white)
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 2.5))
                .frame(width: 15, height: 15)
                .position(pts[i])
                .gesture(
                    DragGesture(coordinateSpace: .named("canvas"))
                        .onChanged { value in
                            // Drag is in display space; map it back through the
                            // rotation to the surface's base (unrotated) point.
                            let base = unrotate(value.location)
                            let nx = min(max(base.x / canvasSize.width, 0), 1)
                            let ny = min(max(base.y / canvasSize.height, 0), 1)
                            store.update(surface.id) { $0.points[i] = CGPoint(x: nx, y: ny) }
                        }
                )
        }
    }

    // MARK: Rotation knob

    private func rotationKnob() -> some View {
        let bb = Surface.bounds(of: surface.points)
        let dist = bb.height / 2 * canvasSize.height + 34
        let dir = CGPoint(x: CGFloat(sin(rotation)), y: CGFloat(-cos(rotation)))
        let p = pivot
        let knob = CGPoint(x: p.x + dir.x * dist, y: p.y + dir.y * dist)
        return ZStack {
            Path { path in
                path.move(to: p)
                path.addLine(to: knob)
            }
            .stroke(Color.accentColor.opacity(0.7), lineWidth: 1.5)

            Circle()
                .fill(Color.accentColor)
                .overlay(
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                )
                .frame(width: 20, height: 20)
                .position(knob)
                .gesture(
                    DragGesture(coordinateSpace: .named("canvas"))
                        .onChanged { value in
                            let dx = Double(value.location.x - p.x)
                            let dy = Double(value.location.y - p.y)
                            store.update(surface.id) { $0.rotation = atan2(dy, dx) + .pi / 2 }
                        }
                )
                .help("Drag to rotate")
        }
    }

    /// Map a display-space point back to base (unrotated) space about the pivot.
    private func unrotate(_ p: CGPoint) -> CGPoint {
        guard rotation != 0 else { return p }
        let c = pivot
        let cs = cos(-rotation), sn = sin(-rotation)
        let dx = Double(p.x - c.x), dy = Double(p.y - c.y)
        return CGPoint(x: c.x + CGFloat(dx * cs - dy * sn),
                       y: c.y + CGFloat(dx * sn + dy * cs))
    }

    /// The selected surface's outline in canvas coordinates (polygon edges, or
    /// an ellipse fit to the — possibly rotated — corner points).
    private func shapePath(_ pts: [CGPoint]) -> Path {
        if surface.shape == .ellipse {
            return ellipsePath(pts)
        }
        return Path { p in
            p.addLines(pts)
            p.closeSubpath()
        }
    }

    /// An ellipse fit to four corner points (handles rotation/skew), so the
    /// outline matches the rotated clip.
    private func ellipsePath(_ pts: [CGPoint]) -> Path {
        guard pts.count == 4 else { return Path(ellipseIn: Surface.bounds(of: pts)) }
        let tl = pts[0], tr = pts[1], br = pts[2], bl = pts[3]
        let cx = (tl.x + tr.x + br.x + bl.x) / 4
        let cy = (tl.y + tr.y + br.y + bl.y) / 4
        let ux = ((tr.x + br.x) - (tl.x + bl.x)) / 4
        let uy = ((tr.y + br.y) - (tl.y + bl.y)) / 4
        let vx = ((bl.x + br.x) - (tl.x + tr.x)) / 4
        let vy = ((bl.y + br.y) - (tl.y + tr.y)) / 4
        var path = Path()
        let steps = 48
        for i in 0...steps {
            let a = Double(i) / Double(steps) * 2 * .pi
            let ca = CGFloat(cos(a)), sa = CGFloat(sin(a))
            let pt = CGPoint(x: cx + ux * ca + vx * sa, y: cy + uy * ca + vy * sa)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    private func centroid(_ pts: [CGPoint]) -> CGPoint {
        let n = CGFloat(max(pts.count, 1))
        let sx = pts.reduce(0) { $0 + $1.x }
        let sy = pts.reduce(0) { $0 + $1.y }
        return CGPoint(x: sx / n, y: sy / n)
    }
}
