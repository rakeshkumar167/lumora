import LumoraKit
import SwiftUI

/// Renders a light line network: a dim base structure, bright lit portions with
/// an additive glow, and bright tracer head(s) at the advancing fill front. The
/// front is driven by graph distance-from-source, so it splits at forks.
///
/// Drawn directly in normalized -> canvas space (no homography warp), so it
/// looks identical in the editor preview and the fullscreen projection.
struct LightLineView: View {
    let line: LightLine
    let canvasSize: CGSize
    let time: Double

    @State private var startRef: Double?

    var body: some View {
        Canvas { ctx, size in
            let elapsed = startRef.map { max(0, time - $0) } ?? 0
            LightLineView.draw(line: line, ctx: ctx, size: size, elapsed: elapsed)
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .opacity(line.opacity)
        .allowsHitTesting(false)
        .onAppear { if startRef == nil { startRef = Date().timeIntervalSinceReferenceDate } }
    }

    /// Pure-ish draw routine (static so the verify script can reuse it verbatim).
    static func draw(line: LightLine, ctx: GraphicsContext, size: CGSize, elapsed: Double) {
        guard line.segments.count > 0 else {
            // Still show a lone joint as a faint dot if present.
            for j in line.joints {
                let p = CGPoint(x: j.point.x * size.width, y: j.point.y * size.height)
                ctx.fill(dot(p, 3), with: .color(line.style.color.color.opacity(0.4)))
            }
            return
        }

        let distances = line.distancesFromSource()
        let maxD = distances.values.max() ?? 0
        let cycle = FillCycle(fillDuration: line.style.fillDuration, holdDuration: line.style.holdDuration)
        let front = cycle.frontFraction(elapsed: elapsed) * maxD

        let base = line.style.color.color
        let head = line.style.glowColor.color
        let core = line.style.thickness
        let glowR = line.style.glowRadius

        func pt(_ id: UUID) -> CGPoint? {
            guard let j = line.joint(id) else { return nil }
            return CGPoint(x: j.point.x * size.width, y: j.point.y * size.height)
        }

        // 1) Dim base structure — every segment faint, so geometry is visible.
        var basePath = Path()
        for s in line.segments {
            guard let a = pt(s.a), let b = pt(s.b) else { continue }
            basePath.move(to: a); basePath.addLine(to: b)
        }
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.blendMode = .plusLighter
            layer.stroke(basePath, with: .color(base.opacity(0.18)),
                         style: StrokeStyle(lineWidth: core, lineCap: .round, lineJoin: .round))
        }

        // 2) Lit portions + glow, per segment (lit from the near endpoint out).
        var litPath = Path()
        var heads: [CGPoint] = []
        for s in line.segments {
            let f = line.litFraction(of: s, front: front, distances: distances)
            guard f > 0, let a = pt(s.a), let b = pt(s.b) else { continue }
            // Order endpoints so `p0` is the one nearer the source.
            let dA = distances[s.a] ?? .greatestFiniteMagnitude
            let dB = distances[s.b] ?? .greatestFiniteMagnitude
            let (p0, p1) = dA <= dB ? (a, b) : (b, a)
            let litEnd = CGPoint(x: p0.x + (p1.x - p0.x) * f, y: p0.y + (p1.y - p0.y) * f)
            litPath.move(to: p0); litPath.addLine(to: litEnd)
            if f < 1 { heads.append(litEnd) } // still filling -> tracer head here
        }

        // Wide soft glow, brighter mid glow, crisp core.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: glowR * 1.4))
            layer.blendMode = .plusLighter
            layer.stroke(litPath, with: .color(base.opacity(0.5)),
                         style: StrokeStyle(lineWidth: core * 6, lineCap: .round, lineJoin: .round))
        }
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: glowR * 0.6))
            layer.blendMode = .plusLighter
            layer.stroke(litPath, with: .color(base.opacity(0.7)),
                         style: StrokeStyle(lineWidth: core * 2.5, lineCap: .round, lineJoin: .round))
        }
        ctx.stroke(litPath, with: .color(base.opacity(0.95)),
                   style: StrokeStyle(lineWidth: core, lineCap: .round, lineJoin: .round))

        // 3) Tracer head glow(s) at the front (one per actively-filling segment).
        for h in heads {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 6))
                layer.blendMode = .plusLighter
                layer.fill(dot(h, core * 2.5), with: .color(head))
            }
            ctx.fill(dot(h, core * 1.1), with: .color(.white))
        }
    }

    private static func dot(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
}
