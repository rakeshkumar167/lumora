import CoreImage
import LumoraKit
import SwiftUI
import Vision

/// Renders one surface's media, perspective-warped onto its quad.
///
/// The media is laid out to fill the whole canvas box, then warped so that
/// box's corners land on the surface's quad — i.e. the media's full extent
/// maps into the surface. Uses SwiftUI's native `ProjectionTransform`, driven
/// by the pure `Homography` from the model core.
struct SurfaceContentView: View {
    let surface: Surface
    let canvasSize: CGSize
    let time: Double

    var body: some View {
        switch surface.shape {
        case .quad:
            quadBody
        case .polygon, .ellipse:
            clippedBody
        }
    }

    /// A true quad: the media fills the canvas and is perspective-warped so the
    /// canvas corners land on the surface's four corners.
    private var quadBody: some View {
        let quad = surface.displayQuadPoints(in: canvasSize)
        let transform = Homography.transform(
            from: CGRect(origin: .zero, size: canvasSize),
            to: quad
        )

        return mediaContent
            .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
            .clipped()
            .opacity(surface.opacity)
            .projectionEffect(ProjectionTransform(transform))
            .allowsHitTesting(false)
    }

    /// A polygon or ellipse: the media fills the shape's bounding box and is
    /// clipped to the outline (no perspective warp).
    private var clippedBody: some View {
        let pts = surface.quadPoints(in: canvasSize)
        let bb = Surface.bounds(of: pts)
        let w = max(bb.width, 1)
        let h = max(bb.height, 1)
        let local = pts.map { CGPoint(x: $0.x - bb.minX, y: $0.y - bb.minY) }

        return mediaContent
            .frame(width: w, height: h, alignment: .topLeading)
            .clipShape(SurfaceMask(localPoints: local, isEllipse: surface.shape == .ellipse))
            .rotationEffect(.radians(surface.rotation))
            .opacity(surface.opacity)
            .position(x: bb.midX, y: bb.midY)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var mediaContent: some View {
        switch surface.media {
        case .none:
            Color.clear
        case .color(let c):
            c.color
        case .effect(let kind, let c, let accent):
            EffectView(kind: kind, color: c, accent: accent, time: time, name: surface.name, marquee: surface.marquee, christmas: surface.christmasLights, game: surface.gameOfLife, leaves: surface.fallingLeaves, treeImage: surface.christmasTreeImage, three: surface.threeD, paint: surface.paintDrip, outline: effectOutline, audioReactive: surface.audioReactive)
        case .image(let url):
            ImageContent(url: url)
        case .video(let url):
            VideoContent(url: url)
        case .laserTrace(let url, let c, let speed):
            LaserTraceContent(url: url, color: c, speed: speed, time: time)
        case .contourTrace(let cfg):
            ContourTraceContent(config: cfg, time: time)
        }
    }

    /// The surface's outline in the effect Canvas's coordinate space, used by
    /// edge effects (e.g. Outline Glow). Quads draw a rect that is warped onto
    /// the real quad; polygon/ellipse fill their bounding box.
    private var effectOutline: EffectOutline {
        switch surface.shape {
        case .quad:
            return .rect
        case .ellipse:
            return .ellipse
        case .polygon:
            let pts = surface.quadPoints(in: canvasSize)
            let bb = Surface.bounds(of: pts)
            let w = max(bb.width, 1), h = max(bb.height, 1)
            return .polygon(pts.map { CGPoint(x: ($0.x - bb.minX) / w, y: ($0.y - bb.minY) / h) })
        }
    }
}

/// Describes a surface outline for edge effects, in the effect Canvas's space.
/// Polygon points are normalized to 0…1 against the drawing box.
enum EffectOutline {
    case rect
    case polygon([CGPoint])
    case ellipse
}

// MARK: - Shared outline geometry (used by OutlineGlowView and GrowingIvyView)

/// The surface outline as a closed polyline in Canvas coordinates.
func outlinePolyline(_ outline: EffectOutline, in size: CGSize) -> [CGPoint] {
    let w = size.width, h = size.height
    switch outline {
    case .rect:
        return [CGPoint(x: 0, y: 0), CGPoint(x: w, y: 0),
                CGPoint(x: w, y: h), CGPoint(x: 0, y: h)]
    case .polygon(let norm):
        return norm.map { CGPoint(x: $0.x * w, y: $0.y * h) }
    case .ellipse:
        let n = 120
        let cx = w / 2, cy = h / 2, rx = w / 2, ry = h / 2
        return (0..<n).map { i in
            let a = Double(i) / Double(n) * 2 * .pi
            return CGPoint(x: cx + rx * CGFloat(cos(a)), y: cy + ry * CGFloat(sin(a)))
        }
    }
}

/// Cumulative arc length at each vertex of the closed loop; `cum[i]` is the
/// length from vertex 0 to vertex i, and `cum[count]` is the full perimeter.
func closedLengths(_ pts: [CGPoint]) -> (cum: [CGFloat], total: CGFloat) {
    var cum: [CGFloat] = [0]
    var total: CGFloat = 0
    for i in 0..<pts.count {
        let a = pts[i], b = pts[(i + 1) % pts.count]
        total += hypot(b.x - a.x, b.y - a.y)
        cum.append(total)
    }
    return (cum, total)
}

func closedPath(_ pts: [CGPoint]) -> Path {
    var p = Path()
    guard let first = pts.first else { return p }
    p.move(to: first)
    for pt in pts.dropFirst() { p.addLine(to: pt) }
    p.closeSubpath()
    return p
}

/// Path along the closed loop from vertex 0 up to arc length `length`.
func subPath(_ pts: [CGPoint], _ cum: [CGFloat], upTo length: CGFloat) -> Path {
    var path = Path()
    guard let first = pts.first else { return path }
    path.move(to: first)
    for i in 0..<pts.count {
        let a = pts[i], b = pts[(i + 1) % pts.count]
        let segEnd = cum[i + 1]
        if segEnd <= length {
            path.addLine(to: b)
        } else {
            let segStart = cum[i]
            let segLen = segEnd - segStart
            let f = segLen > 0 ? (length - segStart) / segLen : 0
            path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f))
            break
        }
    }
    return path
}

/// The point on the closed loop at arc length `length`.
func pointAt(_ pts: [CGPoint], _ cum: [CGFloat], length: CGFloat) -> CGPoint {
    guard let first = pts.first else { return .zero }
    for i in 0..<pts.count {
        let segEnd = cum[i + 1]
        if segEnd >= length {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            let segStart = cum[i]
            let segLen = segEnd - segStart
            let f = segLen > 0 ? (length - segStart) / segLen : 0
            return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
        }
    }
    return first
}

/// Traces a glowing light around the surface's outline once — starting when the
/// effect appears — then holds the completed outline with a gentle breathing
/// pulse. Because the effect clock is global, "fill once then stay" needs a
/// per-view start time (`startRef`, captured on appear); the fill does NOT loop.
private struct OutlineGlowView: View {
    let color: RGBAColor
    let accent: RGBAColor
    let time: Double
    var outline: EffectOutline = .rect

    @State private var startRef: Double?

    private let fillDur = 3.5

    var body: some View {
        Canvas { ctx, size in
            let elapsed = startRef.map { max(0, time - $0) } ?? 0
            draw(ctx: ctx, size: size, elapsed: elapsed)
        }
        .onAppear { if startRef == nil { startRef = Date().timeIntervalSinceReferenceDate } }
    }

    private func draw(ctx: GraphicsContext, size: CGSize, elapsed: Double) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        let pts = outlinePolyline(outline, in: size)
        guard pts.count >= 2 else { return }
        let (cum, total) = closedLengths(pts)
        guard total > 0 else { return }

        // Fill once from appearance, then hold forever (no loop).
        let headFrac = min(elapsed / fillDur, 1.0)
        let inHold = elapsed >= fillDur
        let pulse = inHold ? (0.8 + 0.2 * sin(time * 1.5)) : 1.0
        let litLen = CGFloat(headFrac) * total

        let glow = color.color
        let full = closedPath(pts)
        let lit = subPath(pts, cum, upTo: litLen)

        // Dim base — always present so the outline never goes fully dark.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 10))
            layer.blendMode = .plusLighter
            layer.stroke(full, with: .color(glow.opacity(0.22)),
                         style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
        }
        // Lit portion — soft wide glow + brighter mid glow + crisp core.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 16))
            layer.blendMode = .plusLighter
            layer.stroke(lit, with: .color(glow.opacity(0.5 * pulse)),
                         style: StrokeStyle(lineWidth: 22, lineCap: .round, lineJoin: .round))
        }
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 7))
            layer.blendMode = .plusLighter
            layer.stroke(lit, with: .color(glow.opacity(0.6 * pulse)),
                         style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
        }
        ctx.stroke(lit, with: .color(glow.opacity(0.95 * pulse)),
                   style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

        // Bright running head — only while the outline is still filling.
        if !inHold {
            let head = pointAt(pts, cum, length: litLen)
            let r: CGFloat = 9
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 6))
                layer.blendMode = .plusLighter
                layer.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)),
                           with: .color(accent.color))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: head.x - 3.5, y: head.y - 3.5, width: 7, height: 7)),
                     with: .color(.white))
        }
    }
}

/// Ivy that crawls along the surface's true outline, sprouting inward leafy
/// side-branches, then turns autumn colors, drops its leaves, and regrows — a
/// looping grow → hold → autumn/fall cycle. Uses primary (leaf green) + accent
/// (autumn) color. Like `OutlineGlowView`, the cycle is anchored to a per-view
/// `startRef` captured on appear (the effect clock is global; `time % period`
/// would snap), and the outline is shared via the file-level `outlinePolyline`.
private struct GrowingIvyView: View {
    let color: RGBAColor
    let accent: RGBAColor
    let time: Double
    var outline: EffectOutline = .rect

    @State private var startRef: Double?

    // Per-cycle precomputed branch layout, rebuilt only when the cycle index
    // (or canvas size) changes — not every frame.
    private final class Layout {
        var cycleIndex: Int = .min
        var size: CGSize = .zero
        var branches: [Branch] = []
    }
    private struct Branch {
        var anchorArc: CGFloat      // arc length from the cycle's start point
        var dir: CGVector           // unit growth direction (inward-ish)
        var perp: CGVector          // unit perpendicular (for curl)
        var length: CGFloat
        var curl: CGFloat
        var seed: Int
    }
    @State private var layout = Layout()

    private let growDur = 14.0
    private let holdDur = 4.0
    private let autumnDur = 4.0
    private var period: Double { growDur + holdDur + autumnDur }

    var body: some View {
        Canvas { ctx, size in
            let elapsed = startRef.map { max(0, time - $0) } ?? 0
            draw(ctx: ctx, size: size, elapsed: elapsed)
        }
        .onAppear { if startRef == nil { startRef = Date().timeIntervalSinceReferenceDate } }
    }

    private func hash01(_ i: Int, _ salt: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return CGFloat(v - floor(v))
    }

    private func draw(ctx: GraphicsContext, size: CGSize, elapsed: Double) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.02)))

        let pts = outlinePolyline(outline, in: size)
        guard pts.count >= 2 else { return }
        let (cum, total) = closedLengths(pts)
        guard total > 0 else { return }

        let cycleIndex = Int(elapsed / period)
        let localT = elapsed.truncatingRemainder(dividingBy: period)
        let minDim = min(size.width, size.height)

        // Each cycle starts the stem at a different point on the outline.
        let startArc = hash01(cycleIndex, 7) * total

        rebuildIfNeeded(cycleIndex: cycleIndex, size: size, pts: pts, cum: cum, total: total, minDim: minDim)

        // --- Phase timing -----------------------------------------------------
        let growFrac = min(localT / growDur, 1.0)                     // 0…1 stem growth
        let litLen = CGFloat(growFrac) * total
        let inAutumn = localT >= growDur + holdDur
        let autumnT = inAutumn ? (localT - growDur - holdDur) / autumnDur : 0   // 0…1

        // Leaf color: green (primary) → autumn (accent) over the first ~half of autumn.
        let colorT = min(1, autumnT / 0.5)
        let leafColor = lerp(color, accent, colorT)
        // Leaves detach and fall in the back half of autumn; stems fade last.
        let fallT = max(0, (autumnT - 0.35) / 0.65)                  // 0…1
        let stemFade = 1 - max(0, (autumnT - 0.6) / 0.4)             // stems fade at the very end

        func loopPoint(_ arc: CGFloat) -> CGPoint {
            var a = arc.truncatingRemainder(dividingBy: total)
            if a < 0 { a += total }
            return pointAt(pts, cum, length: a)
        }

        // --- Build the grown stem path (main vine along the outline) ----------
        var stemPath = Path()
        let step = max(4, total / 400)
        var arc: CGFloat = 0
        var first = true
        while arc <= litLen {
            let p = loopPoint(startArc + arc)
            if first { stemPath.move(to: p); first = false } else { stemPath.addLine(to: p) }
            arc += step
        }
        if !first {
            stemPath.addLine(to: loopPoint(startArc + litLen))
        }

        // --- Build grown branch stems + collect leaves ------------------------
        struct LeafDraw { var center: CGPoint; var size: CGFloat; var angle: CGFloat; var opacity: Double }
        var branchPath = Path()
        var leaves: [LeafDraw] = []
        let leafParams: [CGFloat] = [0.34, 0.55, 0.74, 0.92]

        for b in layout.branches {
            // A branch extends only after the stem head passes its anchor.
            var prog = max(0, min(1, (litLen - b.anchorArc) / 70))
            if localT > growDur { prog = min(1, prog + CGFloat((localT - growDur) / 1.5)) }
            if prog <= 0.001 { continue }

            let base = loopPoint(startArc + b.anchorArc)
            func branchPoint(_ t: CGFloat) -> CGPoint {
                let d = b.length * t
                let c = b.curl * sin(Double(t) * .pi)
                return CGPoint(x: base.x + b.dir.dx * d + b.perp.dx * c,
                               y: base.y + b.dir.dy * d + b.perp.dy * c)
            }
            // Draw branch stem as a short polyline up to its current progress.
            branchPath.move(to: base)
            let segs = 8
            for s in 1...segs {
                let t = CGFloat(s) / CGFloat(segs) * prog
                branchPath.addLine(to: branchPoint(t))
            }

            // Leaves appear along the branch as it extends; sway while alive.
            for (li, lt) in leafParams.enumerated() where lt <= prog + 0.02 {
                let idx = b.seed &* 17 &+ li
                let baseAngle = atan2(b.dir.dy, b.dir.dx)
                let sidesign: CGFloat = (li % 2 == 0) ? 1 : -1
                let sway = CGFloat(sin(time * 1.3 + Double(idx))) * 0.18
                let angle = baseAngle + sidesign * (0.7 + 0.5 * hash01(idx, 3)) + sway
                let lsz = (minDim * 0.028) * (0.7 + 0.7 * hash01(idx, 4))
                var center = branchPoint(lt)
                // While falling, detach and drift downward with horizontal sway.
                var opacity = 1.0
                if fallT > 0 {
                    let personal = min(1, Double(fallT) * (0.7 + Double(hash01(idx, 6)) * 0.9))
                    let drop = CGFloat(personal * personal) * minDim * 0.6
                    let drift = CGFloat(sin(time * 1.7 + Double(idx))) * CGFloat(personal) * minDim * 0.05
                    center.x += drift
                    center.y += drop
                    opacity = max(0, 1 - personal)
                }
                leaves.append(LeafDraw(center: center, size: lsz, angle: angle, opacity: opacity))
            }
        }

        let leafC = leafColor
        let stemC = color.color
        let stemStyle = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)

        // Soft green under-glow for stems + leaves (one batched blurred layer).
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 8))
            layer.blendMode = .plusLighter
            layer.opacity = stemFade
            layer.stroke(stemPath, with: .color(stemC.opacity(0.45)),
                         style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            layer.stroke(branchPath, with: .color(stemC.opacity(0.4)),
                         style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            var glowLeaves = Path()
            for lf in leaves where lf.opacity > 0.05 {
                glowLeaves.addPath(leafPath(center: lf.center, size: lf.size, angle: lf.angle))
            }
            layer.fill(glowLeaves, with: .color(leafC.opacity(0.5)))
        }

        // Crisp stems.
        ctx.stroke(stemPath, with: .color(stemC.opacity(0.95 * stemFade)), style: stemStyle)
        ctx.stroke(branchPath, with: .color(stemC.opacity(0.9 * stemFade)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        // Crisp leaves (per-leaf opacity for the stagger during fall).
        for lf in leaves where lf.opacity > 0.02 {
            let p = leafPath(center: lf.center, size: lf.size, angle: lf.angle)
            ctx.fill(p, with: .color(leafC.opacity(lf.opacity)))
            // A small vein/highlight down the leaf.
            ctx.fill(Path(ellipseIn: CGRect(x: lf.center.x - lf.size * 0.08,
                                            y: lf.center.y - lf.size * 0.08,
                                            width: lf.size * 0.16, height: lf.size * 0.16)),
                     with: .color(.white.opacity(0.25 * lf.opacity)))
        }

        // Bright running head while the stem is still growing.
        if growFrac < 1.0 && !first {
            let head = loopPoint(startArc + litLen)
            let r: CGFloat = 7
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 6))
                layer.blendMode = .plusLighter
                layer.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)),
                           with: .color(stemC))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: head.x - 2.5, y: head.y - 2.5, width: 5, height: 5)),
                     with: .color(.white))
        }
    }

    /// A teardrop-ish leaf path centered at `center`, rotated by `angle`.
    private func leafPath(center: CGPoint, size: CGFloat, angle: CGFloat) -> Path {
        let rect = CGRect(x: -size * 0.45, y: -size, width: size * 0.9, height: size * 2)
        var p = Path(ellipseIn: rect)
        var t = CGAffineTransform(translationX: center.x, y: center.y)
        t = t.rotated(by: angle)
        return p.applying(t)
    }

    private func lerp(_ a: RGBAColor, _ b: RGBAColor, _ t: Double) -> Color {
        let t = max(0, min(1, t))
        return Color(.sRGB,
                     red: a.r + (b.r - a.r) * t,
                     green: a.g + (b.g - a.g) * t,
                     blue: a.b + (b.b - a.b) * t,
                     opacity: 1)
    }

    /// Precompute this cycle's branch anchors/directions/seeds once.
    private func rebuildIfNeeded(cycleIndex: Int, size: CGSize, pts: [CGPoint],
                                 cum: [CGFloat], total: CGFloat, minDim: CGFloat) {
        if layout.cycleIndex == cycleIndex && layout.size == size { return }
        layout.cycleIndex = cycleIndex
        layout.size = size

        // Centroid (vertex average) — inward direction points toward it.
        var cx: CGFloat = 0, cy: CGFloat = 0
        for p in pts { cx += p.x; cy += p.y }
        cx /= CGFloat(pts.count); cy /= CGFloat(pts.count)
        let center = CGPoint(x: cx, y: cy)

        let startArc = hash01(cycleIndex, 7) * total
        func loopPoint(_ arc: CGFloat) -> CGPoint {
            var a = arc.truncatingRemainder(dividingBy: total)
            if a < 0 { a += total }
            return pointAt(pts, cum, length: a)
        }

        let spacing: CGFloat = 46
        let count = max(4, min(60, Int(total / spacing)))
        var branches: [Branch] = []
        branches.reserveCapacity(count)
        for i in 0..<count {
            let salt = cycleIndex &* 131 &+ i
            let jitter = (hash01(salt, 1) - 0.5) * spacing * 0.6
            let anchorArc = CGFloat(i) * spacing + jitter
            let anchor = loopPoint(startArc + anchorArc)

            // Inward toward centroid, plus a tangential lean for variety.
            var inx = center.x - anchor.x, iny = center.y - anchor.y
            let ilen = max(0.0001, hypot(inx, iny)); inx /= ilen; iny /= ilen
            let ahead = loopPoint(startArc + anchorArc + 6)
            let behind = loopPoint(startArc + anchorArc - 6)
            var tx = ahead.x - behind.x, ty = ahead.y - behind.y
            let tlen = max(0.0001, hypot(tx, ty)); tx /= tlen; ty /= tlen
            let lean = (hash01(salt, 2) - 0.5) * 1.1
            var dx = inx + tx * lean, dy = iny + ty * lean
            let dlen = max(0.0001, hypot(dx, dy)); dx /= dlen; dy /= dlen
            let perp = CGVector(dx: -dy, dy: dx)

            let length = minDim * (0.10 + 0.10 * hash01(salt, 3))
            let curl = length * 0.22 * (hash01(salt, 4) - 0.5) * 2
            branches.append(Branch(anchorArc: anchorArc,
                                   dir: CGVector(dx: dx, dy: dy),
                                   perp: perp, length: length, curl: curl, seed: salt))
        }
        layout.branches = branches
    }
}

/// Draws an order-6 Hilbert space-filling curve end-to-end with a glowing pen
/// head, colored by an arc-length rainbow, then holds the finished curve,
/// fades out, and repeats — flipping orientation each cycle. Fixed rainbow
/// coloring (no primary/accent color use). Because the effect clock is global,
/// "draw once from appearance" needs a per-view start time (`startRef`,
/// captured on appear), mirroring `OutlineGlowView`.
private struct HilbertCurveView: View {
    let time: Double

    @State private var startRef: Double?

    private static let order = 6
    private static let gridSpan = 1 << order              // 64
    private static let curvePoints = HilbertCurve.points(order: order)

    private let drawDur = 15.0
    private let holdDur = 3.0
    private let fadeDur = 1.5
    private let bandCount = 32

    var body: some View {
        Canvas { ctx, size in
            let elapsed = startRef.map { max(0, time - $0) } ?? 0
            draw(ctx: &ctx, size: size, elapsed: elapsed)
        }
        .onAppear { if startRef == nil { startRef = Date().timeIntervalSinceReferenceDate } }
    }

    private func draw(ctx: inout GraphicsContext, size: CGSize, elapsed: Double) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.02)))

        let period = drawDur + holdDur + fadeDur
        let cycleIndex = Int(elapsed / period)
        let localT = elapsed.truncatingRemainder(dividingBy: period)
        let mirrored = cycleIndex % 2 == 1

        let headFrac = min(localT / drawDur, 1.0)
        let total = Self.curvePoints.count
        let litCount = max(1, Int(headFrac * Double(total)))

        let opacity: Double
        if localT < drawDur + holdDur {
            opacity = 1
        } else {
            let fadeFrac = (localT - drawDur - holdDur) / fadeDur
            opacity = max(0, 1 - fadeFrac)
        }
        guard opacity > 0.001 else { return }

        // Map integer grid cells (0…gridSpan-1) into a centered square box with
        // a small margin, mirroring x on alternating cycles.
        let margin = min(size.width, size.height) * 0.08
        let boxSize = min(size.width, size.height) - margin * 2
        let ox = (size.width - boxSize) / 2
        let oy = (size.height - boxSize) / 2
        let cell = boxSize / CGFloat(Self.gridSpan - 1)
        func mapPoint(_ p: CGPoint) -> CGPoint {
            let gx = mirrored ? CGFloat(Self.gridSpan - 1) - p.x : p.x
            return CGPoint(x: ox + gx * cell, y: oy + p.y * cell)
        }

        // Bucket the lit segments into rainbow bands by arc-length (point index)
        // fraction — one Path per band, so we stroke each band once rather than
        // issuing thousands of individual stroke calls.
        var bands = [Path](repeating: Path(), count: bandCount)
        for i in 1..<litCount {
            let a = mapPoint(Self.curvePoints[i - 1])
            let b = mapPoint(Self.curvePoints[i])
            let frac = Double(i) / Double(total)
            let bi = min(bandCount - 1, Int(frac * Double(bandCount)))
            bands[bi].move(to: a)
            bands[bi].addLine(to: b)
        }
        func bandColor(_ bi: Int) -> Color {
            Color(hue: (Double(bi) + 0.5) / Double(bandCount), saturation: 0.9, brightness: 1)
        }

        ctx.opacity = opacity

        // Soft wide glow underlayer, brighter mid glow, then a crisp core stroke.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 9))
            layer.blendMode = .plusLighter
            for bi in bands.indices where !bands[bi].isEmpty {
                layer.stroke(bands[bi], with: .color(bandColor(bi).opacity(0.5)),
                             style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            }
        }
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            layer.blendMode = .plusLighter
            for bi in bands.indices where !bands[bi].isEmpty {
                layer.stroke(bands[bi], with: .color(bandColor(bi).opacity(0.75)),
                             style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        for bi in bands.indices where !bands[bi].isEmpty {
            ctx.stroke(bands[bi], with: .color(bandColor(bi)),
                       style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }

        // Bright pen head — only while still drawing.
        if headFrac < 1.0 {
            let headIdx = min(litCount, total - 1)
            let head = mapPoint(Self.curvePoints[headIdx])
            let r: CGFloat = 6
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 6))
                layer.blendMode = .plusLighter
                layer.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)),
                           with: .color(.white))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: head.x - 3, y: head.y - 3, width: 6, height: 6)),
                     with: .color(.white))
        }
    }
}

/// The built-in generative animations. Effects that support a second color use
/// `accent` (see `EffectKind.usesAccent`).
private struct EffectView: View {
    let kind: EffectKind
    let color: RGBAColor
    let accent: RGBAColor
    let time: Double
    var name: String = ""
    var marquee: MarqueeConfig? = nil
    var christmas: ChristmasLightsConfig? = nil
    var game: GameOfLifeConfig? = nil
    var leaves: FallingLeavesConfig? = nil
    var treeImage: Int = 0
    var three: ThreeDConfig? = nil
    var paint: PaintDripConfig? = nil
    var outline: EffectOutline = .rect
    var audioReactive: Bool = false

    var body: some View {
        switch kind {
        case .grid, .colorWash, .gradientSweep, .breathingGlow, .rainbowSweep, .radialPulse, .aurora, .plasma, .strobe:
            gradientEffects
        case .checkerboard, .barberStripes, .colorBars, .halftoneDots, .truchet, .concentricPolygons,
             .infiniteKaleidoscope, .mandalaExpansion, .sacredGeometry, .fractalZoom, .tessellationMorph,
             .chladni, .hilbertCurve:
            patternEffects
        case .sparkle, .starfieldWarp, .fireflies, .snow, .lava, .fire, .rain, .lightning, .bubbles, .fallingLeaves, .fireworks, .particleSwarm, .audioParticles:
            natureEffects
        case .waves, .equalizer, .tunnel, .kaleidoscope, .prismFalls, .liquidSlosh, .pendulumPaint:
            motionEffects
        case .tvStatic, .matrixRain, .pixelDissolve, .dvdBounce, .marqueeText:
            retroEffects
        case .voronoi, .metaballs, .hexGrid:
            fieldEffects
        case .vectorGrid, .particleMesh:
            geometryEffects
        case .livingTexture, .gameOfLife, .flowingPlasma, .reactionDiffusion, .driftingNebula, .perlinFlow, .circuitTrace:
            ambientEffects
        case .torus3D, .sphere3D, .pointCloud3D:
            threeDEffects
        case .outlineGlow, .growingIvy:
            edgeEffects
        case .analogClock, .digitalClock, .weatherWidget:
            clockEffects
        case .christmasTree, .chasingLights, .multiColorLights, .twinklingLights, .warmBulbs:
            christmasEffects
        }
    }

    @ViewBuilder private var christmasEffects: some View {
        switch kind {
        case .christmasTree:
            Canvas { ctx, size in
                // Dark backing so unlit margins read as night, not white.
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(red: 0.02, green: 0.03, blue: 0.02)))
                if let img = ChristmasTreeAsset.image(treeImage) {
                    let resolved = ctx.resolve(Image(nsImage: img))
                    let isz = img.size
                    let scale = min(size.width / isz.width, size.height / isz.height)
                    let w = isz.width * scale, h = isz.height * scale
                    let ox = (size.width - w) / 2, oy = (size.height - h) / 2
                    let rect = CGRect(x: ox, y: oy, width: w, height: h)
                    ctx.draw(resolved, in: rect)
                    drawTreeGlints(ctx, imageRect: rect)
                } else {
                    drawTreeGlints(ctx, imageRect: CGRect(origin: .zero, size: size))
                }
            }

        case .chasingLights, .multiColorLights, .twinklingLights, .warmBulbs:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(red: 0.03, green: 0.04, blue: 0.07)))
                let round = (kind == .warmBulbs)
                let cfg = christmas ?? ChristmasLightsConfig()
                for strand in ChristmasLights.strands(in: size, config: cfg) {
                    let bulbs = strand.bulbs
                    // The hanging wire runs through the attach points; bulbs dangle below.
                    var wire = Path()
                    wire.addLines(bulbs)
                    ctx.stroke(wire, with: .color(Color(white: 0.35).opacity(0.6)),
                               lineWidth: max(1.2, size.width * 0.0018))
                    // Bulb size scales with spacing between bulbs (width-driven so
                    // it doesn't grow when the surface is stretched taller), times
                    // the user's size multiplier.
                    let spacing = bulbs.count > 1 ? hypot(bulbs[1].x - bulbs[0].x, bulbs[1].y - bulbs[0].y) : 24
                    let r = min(spacing * (round ? 0.40 : 0.34), size.width * 0.045) * CGFloat(cfg.bulbScale)
                    for (i, b) in bulbs.enumerated() {
                        let (col, bright) = bulbState(index: i, count: bulbs.count)
                        drawBulb(ctx, at: b, color: col, brightness: bright, radius: r, round: round)
                    }
                }
            }

        default:
            EmptyView()
        }
    }

    /// Twinkle glints on the tree: soft glowing dots that pulse on their own
    /// phase, only at the precomputed on-tree points.
    private func drawTreeGlints(_ ctx: GraphicsContext, imageRect: CGRect) {
        let points = ChristmasTreeAsset.litPoints(treeImage)
        guard !points.isEmpty else { return }
        let palette = ChristmasLights.palette
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            layer.blendMode = .plusLighter
            for (i, p) in points.enumerated() {
                let phase = Double(i) * 0.7
                let pulse = 0.5 + 0.5 * sin(time * 2.2 + phase)
                guard pulse > 0.55 else { continue }
                let intensity = (pulse - 0.55) / 0.45
                // Warm-white/gold dominate; occasional colored sparkle.
                let col: Color = (i % 5 == 0) ? palette[i % palette.count].color
                                              : (i % 2 == 0 ? palette[4].color : palette[2].color)
                let c = CGPoint(x: imageRect.minX + p.x * imageRect.width,
                                y: imageRect.minY + p.y * imageRect.height)
                let r = 2.0 + 4.0 * intensity
                layer.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(col.opacity(0.35 + 0.65 * intensity)))
            }
        }
    }

    /// Per-bulb color + brightness for the three string variations.
    private func bulbState(index i: Int, count: Int) -> (Color, Double) {
        let palette = ChristmasLights.palette
        switch kind {
        case .chasingLights:
            // A bright band runs along the strand; color cycles slowly.
            let pos = Double(i) / Double(max(count - 1, 1))
            let head = (time * 0.5).truncatingRemainder(dividingBy: 1)
            let d = abs(pos - head)
            let wrapped = min(d, 1 - d)
            let bright = max(0, 1 - wrapped * 6)
            let col = palette[(i + Int(time)) % palette.count].color
            return (col, 0.15 + 0.85 * bright)
        case .multiColorLights:
            // Steady alternating palette with a gentle per-bulb shimmer.
            let col = palette[i % palette.count].color
            let shimmer = 0.75 + 0.25 * sin(time * 1.5 + Double(i) * 0.9)
            return (col, shimmer)
        case .twinklingLights:
            // Smooth pseudo-random fade per bulb.
            let seed = Double((i * 2654435761) % 1000) / 1000.0
            let tw = 0.5 + 0.5 * sin(time * 1.8 + seed * 6.283)
            let col = palette[i % palette.count].color
            return (col, 0.1 + 0.9 * pow(tw, 2))
        case .warmBulbs:
            // Steady warm amber glow with a gentle per-bulb flicker.
            let warm = Color(red: 1.0, green: 0.82, blue: 0.52)
            let flicker = 0.82 + 0.18 * sin(time * 1.1 + Double(i) * 1.3)
            return (warm, flicker)
        default:
            return (palette[i % palette.count].color, 1)
        }
    }

    /// A glowing bulb hanging from the wire at `p`: a small socket cap, an oval
    /// (mini light) or round (globe) glass body dangling below with a soft
    /// plusLighter halo, and a specular highlight.
    private func drawBulb(_ ctx: GraphicsContext, at p: CGPoint, color: Color,
                          brightness: Double, radius r: CGFloat, round: Bool) {
        // Socket cap straddling the wire.
        let capW = r * 0.75, capH = r * 0.55
        let capRect = CGRect(x: p.x - capW / 2, y: p.y - capH * 0.35, width: capW, height: capH)
        ctx.fill(Path(roundedRect: capRect, cornerSize: CGSize(width: capH * 0.3, height: capH * 0.3)),
                 with: .color(Color(white: 0.32)))

        // Glass body dangling below the cap. Globes are round; the others are
        // C7/C9-style flame bulbs — a wide rounded shoulder near the cap
        // tapering to a pointed tip.
        let halfH: CGFloat = round ? r : r * 1.6
        let halfW: CGFloat = round ? r : r * 0.82
        let cy = p.y + capH * 0.5 + halfH
        let center = CGPoint(x: p.x, y: cy)

        // Soft glow halo.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: r * 1.3))
            layer.blendMode = .plusLighter
            let hr = halfH * (1.1 + 0.8 * brightness)
            layer.fill(Path(ellipseIn: CGRect(x: center.x - hr, y: center.y - hr, width: 2 * hr, height: 2 * hr)),
                       with: .color(color.opacity(0.55 * brightness)))
        }

        // Glass body.
        let body = round
            ? Path(ellipseIn: CGRect(x: center.x - halfW, y: center.y - halfH, width: 2 * halfW, height: 2 * halfH))
            : flameBulbPath(center: center, halfW: halfW, halfH: halfH)
        ctx.fill(body, with: .color(color.opacity(0.55 + 0.45 * brightness)))
        ctx.stroke(body, with: .color(.black.opacity(0.18)), lineWidth: max(0.6, r * 0.06))

        // Specular highlight, upper-left near the shoulder.
        let hlR = halfW * 0.32
        let hl = CGPoint(x: center.x - halfW * 0.34, y: center.y - halfH * 0.45)
        ctx.fill(Path(ellipseIn: CGRect(x: hl.x - hlR, y: hl.y - hlR, width: 2 * hlR, height: 2 * hlR)),
                 with: .color(.white.opacity(0.55 * max(0.4, brightness))))
    }

    /// A C7/C9 "flame" bulb outline: a rounded egg-shaped shoulder near the top
    /// (cap side) with a long smooth taper to a blunt rounded tip at the bottom.
    /// `center` is the body center.
    private func flameBulbPath(center: CGPoint, halfW: CGFloat, halfH: CGFloat) -> Path {
        let cx = center.x
        let ty = center.y - halfH                  // top (cap side)
        let by = center.y + halfH                  // tip
        let shoulderY = center.y - halfH * 0.45    // widest, ~27% down from top
        let tipHalf = halfW * 0.16                 // half-width of the blunt tip
        var p = Path()
        // Blunt rounded bottom tip.
        p.move(to: CGPoint(x: cx - tipHalf, y: by))
        p.addQuadCurve(to: CGPoint(x: cx + tipHalf, y: by),
                       control: CGPoint(x: cx, y: by + halfH * 0.06))
        // Up the right side, curving out to the widest shoulder.
        p.addQuadCurve(to: CGPoint(x: cx + halfW, y: shoulderY),
                       control: CGPoint(x: cx + halfW * 0.92, y: by - halfH * 0.55))
        // Rounded egg dome over the top to the left shoulder.
        p.addCurve(to: CGPoint(x: cx - halfW, y: shoulderY),
                   control1: CGPoint(x: cx + halfW, y: ty),
                   control2: CGPoint(x: cx - halfW, y: ty))
        // Down the left side back to the tip.
        p.addQuadCurve(to: CGPoint(x: cx - tipHalf, y: by),
                       control: CGPoint(x: cx - halfW * 0.92, y: by - halfH * 0.55))
        p.closeSubpath()
        return p
    }

    @ViewBuilder private var gradientEffects: some View {
        switch kind {
        case .grid:
            // A crisp alignment grid — ideal default for a fresh surface, since
            // each cell visibly distorts under the perspective warp.
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color))
                let spacing: CGFloat = 48
                let line = color.color.opacity(0.85)
                var x: CGFloat = 0
                while x <= size.width + 0.5 {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(p, with: .color(line), lineWidth: 1.5)
                    x += spacing
                }
                var y: CGFloat = 0
                while y <= size.height + 0.5 {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(line), lineWidth: 1.5)
                    y += spacing
                }
                // Bright border + center cross to make corner/edge alignment easy.
                ctx.stroke(Path(CGRect(origin: .zero, size: size)), with: .color(color.color), lineWidth: 3)
                var cross = Path()
                cross.move(to: CGPoint(x: size.width / 2, y: 0))
                cross.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                cross.move(to: CGPoint(x: 0, y: size.height / 2))
                cross.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                ctx.stroke(cross, with: .color(color.color.opacity(0.5)), lineWidth: 2)
            }

        case .colorWash:
            let hue = (time * 0.08).truncatingRemainder(dividingBy: 1)
            Color(hue: hue, saturation: 0.7, brightness: 0.95)

        case .gradientSweep:
            LinearGradient(
                colors: [color.color, accent.color, color.color],
                startPoint: unitPoint(time * 0.7),
                endPoint: unitPoint(time * 0.7 + .pi)
            )

        case .breathingGlow:
            let pulse = 0.5 + 0.5 * sin(time * 1.6)
            ZStack {
                accent.color
                color.color.opacity(0.30 + 0.70 * pulse)
            }

        case .rainbowSweep:
            AngularGradient(
                gradient: Gradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red]),
                center: .center,
                angle: .degrees(time * 50)
            )

        case .radialPulse:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color.opacity(0.20)))
                let spacing: CGFloat = 70
                let phase = CGFloat(time.truncatingRemainder(dividingBy: 1)) * spacing
                let maxR = hypot(size.width, size.height)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                var r = phase
                while r < maxR {
                    let rect = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
                    ctx.stroke(Path(ellipseIn: rect), with: .color(color.color), lineWidth: 12)
                    r += spacing
                }
            }

        case .aurora:
            Canvas { ctx, size in
                let w = Double(size.width)
                let h = Double(size.height)

                // Night sky with a faint gradient.
                ctx.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.03, green: 0.04, blue: 0.11),
                            Color(red: 0.01, green: 0.02, blue: 0.05),
                        ]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )

                // Stars.
                for i in 0..<70 {
                    let sx = Double(hash01(i, 11)) * w
                    let sy = Double(hash01(i, 12)) * h * 0.92
                    let tw = 0.4 + 0.6 * abs(sin(time * 1.3 + Double(i)))
                    let s = 1.0 + Double(hash01(i, 13)) * 1.4
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: sx, y: sy, width: s, height: s)),
                        with: .color(.white.opacity(0.12 + 0.4 * tw))
                    )
                }

                // Curtains, drawn back (high, dim, purple) to front (low, bright, green).
                // Each: base height fraction, wave amplitude, curtain drop, drift
                // speed, phase, tint.
                let curtains: [(base: Double, amp: Double, drop: Double, speed: Double, phase: Double, tint: Color)] = [
                    (0.30, 24, 0.44, 0.22, 0.0, Color(red: 0.55, green: 0.25, blue: 0.85)),
                    (0.27, 30, 0.52, 0.30, 2.1, Color(red: 0.10, green: 0.80, blue: 0.80)),
                    (0.24, 36, 0.62, 0.40, 4.3, Color(red: 0.18, green: 0.98, blue: 0.50)),
                ]

                for cur in curtains {
                    let baseY = h * cur.base
                    let ch = h * cur.drop

                    // Wavy top rim of the curtain, and a parallel bottom edge.
                    func rim(_ x: Double) -> Double {
                        baseY
                            + sin(x * 0.006 + time * cur.speed + cur.phase) * cur.amp
                            + sin(x * 0.018 + time * cur.speed * 1.7 + cur.phase) * cur.amp * 0.35
                    }

                    var band = Path()
                    var bottom: [CGPoint] = []
                    var x = 0.0
                    band.move(to: CGPoint(x: 0, y: rim(0)))
                    while x <= w {
                        band.addLine(to: CGPoint(x: x, y: rim(x)))
                        bottom.append(CGPoint(x: x, y: rim(x) + ch))
                        x += 12
                    }
                    for pt in bottom.reversed() { band.addLine(to: pt) }
                    band.closeSubpath()

                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 8))
                        layer.clip(to: band)

                        // Bright top rim fading downward.
                        let fill = GraphicsContext.Shading.linearGradient(
                            Gradient(stops: [
                                .init(color: cur.tint.opacity(0.0), location: 0.0),
                                .init(color: cur.tint.opacity(0.9), location: 0.14),
                                .init(color: cur.tint.opacity(0.35), location: 0.55),
                                .init(color: cur.tint.opacity(0.0), location: 1.0),
                            ]),
                            startPoint: CGPoint(x: 0, y: baseY - cur.amp),
                            endPoint: CGPoint(x: 0, y: baseY + ch)
                        )
                        layer.fill(band, with: fill)

                        // Vertical ray striations that shimmer sideways.
                        var rx = 0.0
                        while rx <= w {
                            let bright = pow(abs(sin(rx * 0.028 + time * 1.5 + cur.phase)), 3)
                            if bright > 0.05 {
                                var ray = Path()
                                ray.move(to: CGPoint(x: rx, y: baseY - cur.amp - 6))
                                ray.addLine(to: CGPoint(x: rx, y: baseY + ch))
                                layer.stroke(ray, with: .color(cur.tint.opacity(0.5 * bright)), lineWidth: 2)
                            }
                            rx += 9
                        }
                    }
                }
            }

        case .plasma:
            ZStack {
                color.color
                RadialGradient(colors: [.white.opacity(0.9), .clear],
                               center: animatedCenter(time, 0.0),
                               startRadius: 0, endRadius: 280)
                    .blendMode(.screen)
                RadialGradient(colors: [accent.color.opacity(0.95), .clear],
                               center: animatedCenter(time, 2.0),
                               startRadius: 0, endRadius: 340)
                    .blendMode(.screen)
            }

        case .strobe:
            AudioReactiveEffect(active: audioReactive) { levels in
                StrobeView(color: color, accent: accent, time: time, levels: levels)
            }

        default: EmptyView()
        }
    }

    @ViewBuilder private var patternEffects: some View {
        switch kind {
        case .checkerboard:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color))
                let cell: CGFloat = 44
                let offset = CGFloat((time * 30).truncatingRemainder(dividingBy: Double(cell * 2)))
                var row = 0
                var y: CGFloat = -cell * 2
                while y < size.height + cell * 2 {
                    var col = 0
                    var x: CGFloat = -cell * 2
                    while x < size.width + cell * 2 {
                        if (row + col) % 2 == 0 {
                            ctx.fill(Path(CGRect(x: x + offset, y: y, width: cell, height: cell)),
                                     with: .color(color.color))
                        }
                        x += cell; col += 1
                    }
                    y += cell; row += 1
                }
            }

        case .barberStripes:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color))
                let stripe: CGFloat = 42
                let offset = CGFloat((time * 45).truncatingRemainder(dividingBy: Double(stripe * 2)))
                let diag = size.width + size.height
                var d = -size.height + offset - diag
                while d < size.width + diag {
                    var p = Path()
                    p.move(to: CGPoint(x: d, y: 0))
                    p.addLine(to: CGPoint(x: d + stripe, y: 0))
                    p.addLine(to: CGPoint(x: d + stripe + size.height, y: size.height))
                    p.addLine(to: CGPoint(x: d + size.height, y: size.height))
                    p.closeSubpath()
                    ctx.fill(p, with: .color(color.color))
                    d += stripe * 2
                }
            }

        case .colorBars:
            Canvas { ctx, size in
                let bars: [Color] = [.white, .yellow, .cyan, .green,
                                     Color(red: 1, green: 0, blue: 1), .red, .blue]
                let w = size.width / CGFloat(bars.count)
                for (i, c) in bars.enumerated() {
                    let rect = CGRect(x: CGFloat(i) * w, y: 0, width: w + 1, height: size.height)
                    ctx.fill(Path(rect), with: .color(c))
                }
            }

        case .halftoneDots:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color))
                let spacing: CGFloat = 36
                var y: CGFloat = spacing / 2
                while y < size.height {
                    var x: CGFloat = spacing / 2
                    while x < size.width {
                        let wave = 0.5 + 0.5 * sin(Double(x + y) * 0.05 - time * 3)
                        let r = CGFloat(2 + 14 * wave)
                        let rect = CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)
                        ctx.fill(Path(ellipseIn: rect), with: .color(color.color))
                        x += spacing
                    }
                    y += spacing
                }
            }

        case .truchet:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color))
                let cell: CGFloat = 40
                let cols = Int(size.width / cell) + 1
                let rows = Int(size.height / cell) + 1
                let epoch = Int(time / 2.5)
                for row in 0..<rows {
                    for col in 0..<cols {
                        let idx = row * 1000 + col
                        let flip = hash01(idx, epoch) > 0.5
                        let x = CGFloat(col) * cell
                        let y = CGFloat(row) * cell
                        var path = Path()
                        if flip {
                            path.addArc(center: CGPoint(x: x, y: y), radius: cell / 2,
                                        startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
                            path.addArc(center: CGPoint(x: x + cell, y: y + cell), radius: cell / 2,
                                        startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
                        } else {
                            path.addArc(center: CGPoint(x: x + cell, y: y), radius: cell / 2,
                                        startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
                            path.addArc(center: CGPoint(x: x, y: y + cell), radius: cell / 2,
                                        startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
                        }
                        ctx.stroke(path, with: .color(color.color), lineWidth: 3)
                    }
                }
            }

        case .concentricPolygons:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.03)))
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let rings = 6
                for i in 0..<rings {
                    let radius = 30.0 + Double(i) * 34.0
                    let speed = 0.3 + Double(i) * 0.15
                    let rotation = time * speed * (i % 2 == 0 ? 1 : -1)
                    let path = polygonPath(center: center, radius: CGFloat(radius), sides: 6, rotation: rotation)
                    let c = i % 2 == 0 ? color.color : accent.color
                    ctx.stroke(path, with: .color(c), lineWidth: 3)
                }
            }
        case .infiniteKaleidoscope:
            Canvas { ctx, size in drawInfiniteKaleidoscope(ctx: ctx, size: size) }
        case .mandalaExpansion:
            Canvas { ctx, size in drawMandala(ctx: ctx, size: size) }
        case .sacredGeometry:
            Canvas { ctx, size in drawSacredGeometry(ctx: ctx, size: size) }
        case .fractalZoom:
            Canvas { ctx, size in drawFractalZoom(ctx: ctx, size: size) }
        case .tessellationMorph:
            Canvas { ctx, size in drawTessellation(ctx: ctx, size: size) }
        case .hilbertCurve:
            HilbertCurveView(time: time)
        default: EmptyView()
        }
    }

    @ViewBuilder private var natureEffects: some View {
        switch kind {
        case .particleSwarm:
            ParticleSwarmView(mode: .swarm, color: color, accent: accent, time: time)
        case .audioParticles:
            ParticleSwarmView(mode: .audio, color: color, accent: accent, time: time)

        case .sparkle:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                for i in 0..<90 {
                    let x = hash01(i, 1) * size.width
                    let y = hash01(i, 2) * size.height
                    let twinkle = 0.5 + 0.5 * sin(time * 2 + Double(i) * 1.3)
                    let s = CGFloat(2 + 3 * twinkle)
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                             with: .color(color.color.opacity(twinkle)))
                }
            }

        case .starfieldWarp:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxR = Double(hypot(size.width, size.height)) / 2
                for i in 0..<130 {
                    let angle = Double(hash01(i, 1)) * .pi * 2
                    let speed = 0.25 + Double(hash01(i, 2)) * 0.6
                    let f = fract(Double(hash01(i, 3)) + time * speed)
                    let r = f * maxR
                    let streak = 6 + f * 26
                    var p = Path()
                    p.move(to: point(center, angle, r))
                    p.addLine(to: point(center, angle, r + streak))
                    ctx.stroke(p, with: .color(.white.opacity(f)), lineWidth: CGFloat(1 + f * 1.6))
                }
            }

        case .fireflies:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.04)))
                for i in 0..<40 {
                    let x = fract(Double(hash01(i, 1)) + 0.04 * sin(time * 0.5 + Double(i))) * Double(size.width)
                    let y = fract(Double(hash01(i, 2)) + 0.04 * cos(time * 0.4 + Double(i) * 1.7)) * Double(size.height)
                    let glow = max(0.0, 0.35 + 0.65 * sin(time * 1.5 + Double(i) * 2.0))
                    let radius = 7.0
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 5))
                        layer.fill(Path(ellipseIn: rect), with: .color(color.color.opacity(glow)))
                    }
                }
            }

        case .snow:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.03)))
                for i in 0..<130 {
                    let speed = 0.15 + Double(hash01(i, 3)) * 0.45
                    let y = fract(Double(hash01(i, 2)) + time * speed) * Double(size.height)
                    let sway = 0.03 * sin(time + Double(i))
                    let x = (Double(hash01(i, 1)) + sway) * Double(size.width)
                    let s = 2.0 + Double(hash01(i, 4)) * 3.5
                    let rect = CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
                    ctx.fill(Path(ellipseIn: rect), with: .color(color.color.opacity(0.9)))
                }
            }

        case .lava:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.03)))
                ctx.addFilter(.alphaThreshold(min: 0.5, color: color.color))
                ctx.addFilter(.blur(radius: 22))
                ctx.drawLayer { layer in
                    for i in 0..<6 {
                        let x = (0.5 + 0.42 * sin(time * 0.5 + Double(i) * 1.1)) * Double(size.width)
                        let y = (0.5 + 0.42 * cos(time * 0.4 + Double(i) * 1.7)) * Double(size.height)
                        let r = 55.0 + 22.0 * sin(time + Double(i))
                        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                        layer.fill(Path(ellipseIn: rect), with: .color(.white))
                    }
                }
            }
        case .fire:
            Canvas { ctx, size in drawFire(ctx: ctx, size: size) }
        case .rain:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.03)))
                for i in 0..<120 {
                    let speed = 3.0 + Double(hash01(i, 1)) * 4.0
                    let x = Double(hash01(i, 2)) * Double(size.width)
                    let len = 14.0 + Double(hash01(i, 3)) * 20.0
                    let y = fract(Double(hash01(i, 4)) + time * speed * 0.15) * Double(size.height + CGFloat(len)) - len
                    var p = Path()
                    p.move(to: CGPoint(x: CGFloat(x), y: CGFloat(y)))
                    p.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(y + len)))
                    ctx.stroke(p, with: .color(color.color.opacity(0.7)), lineWidth: 1.5)
                }
            }

        case .lightning:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.02)))
                let period = 3.0
                let cycle = fract(time / period)
                if cycle < 0.15 {
                    let flash = 1 - cycle / 0.15
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color.opacity(0.35 * flash)))
                    let strikeIndex = Int(time / period)
                    var x = Double(hash01(strikeIndex, 1)) * Double(size.width)
                    var y = 0.0
                    var path = Path()
                    path.move(to: CGPoint(x: CGFloat(x), y: CGFloat(y)))
                    var seg = 0
                    while y < Double(size.height) {
                        let dx = (Double(hash01(strikeIndex, seg + 10)) - 0.5) * 60
                        x += dx
                        y += Double(size.height) / 12
                        path.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(y)))
                        seg += 1
                    }
                    ctx.stroke(path, with: .color(color.color.opacity(flash)), lineWidth: 3)
                }
            }
        case .bubbles:
            Canvas { ctx, size in drawBubbles(ctx: ctx, size: size) }

        case .fallingLeaves:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.05)))
                let leafScale = CGFloat(leaves?.leafScale ?? 1.0)
                for i in 0..<30 {
                    // Gentler descent than before (~1/3 the old speed).
                    let speed = 0.06 + Double(hash01(i, 1)) * 0.1
                    let fallT = fract(Double(hash01(i, 2)) + time * speed)
                    let y = Double(size.height) * fallT - 20
                    let baseX = Double(hash01(i, 3)) * Double(size.width)
                    let sway = sin(time * 0.7 + Double(i) * 1.7) * 26
                    let x = baseX + sway
                    let rot = time * (0.25 + Double(hash01(i, 4)) * 0.5) + Double(i)
                    let s: CGFloat = (9 + CGFloat(hash01(i, 5)) * 8) * leafScale
                    let tint = i % 2 == 0 ? color.color : accent.color
                    ctx.drawLayer { layer in
                        layer.translateBy(x: CGFloat(x), y: CGFloat(y))
                        layer.rotate(by: .radians(rot))
                        layer.fill(Self.mapleLeafPath(scale: s), with: .color(tint.opacity(0.9)))
                    }
                }
            }
        case .fireworks:
            Canvas { ctx, size in drawFireworks(ctx: ctx, size: size) }
        default: EmptyView()
        }
    }

    @ViewBuilder private var motionEffects: some View {
        switch kind {
        case .waves:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color.opacity(0.20)))
                let bands = 5
                for b in 0..<bands {
                    var path = Path()
                    let baseY = size.height * CGFloat(b) / CGFloat(bands - 1)
                    path.move(to: CGPoint(x: 0, y: baseY))
                    var x: CGFloat = 0
                    while x <= size.width {
                        let y = baseY + CGFloat(sin(Double(x) / 40 + time * 2 + Double(b)) * 16)
                        path.addLine(to: CGPoint(x: x, y: y))
                        x += 8
                    }
                    ctx.stroke(path, with: .color(color.color), lineWidth: 5)
                }
            }

        case .equalizer:
            AudioReactiveEffect(active: audioReactive) { levels in
                EqualizerView(color: color, accent: accent, time: time, levels: levels)
            }

        case .tunnel:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black))
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxR = Double(hypot(size.width, size.height)) / 2
                let rings = 14
                let speed = 0.5
                for i in 0..<rings {
                    let f = fract(Double(i) / Double(rings) + time * speed)
                    let r = f * maxR
                    let rect = CGRect(x: center.x - CGFloat(r), y: center.y - CGFloat(r), width: CGFloat(r * 2), height: CGFloat(r * 2))
                    let c = i % 2 == 0 ? color.color : accent.color
                    ctx.stroke(Path(ellipseIn: rect), with: .color(c.opacity(0.2 + 0.8 * f)), lineWidth: CGFloat(4 + f * 10))
                }
            }
        case .kaleidoscope:
            Canvas { ctx, size in drawKaleidoscope(ctx: ctx, size: size) }

        case .prismFalls:
            // Horizontal colour bands falling continuously through the full bright
            // spectrum, each with a wavy liquid leading edge. Bands are indexed by an
            // absolute band number `k`, so each keeps a FIXED hue for its whole life and
            // its screen position `(s - k)·bandH` grows smoothly downward — no snap or
            // colour reshuffle at period boundaries.
            Canvas { ctx, size in
                let bandH = max(size.height * 0.18, 1)           // thinner bands → less gap between waves
                let speed = size.height / 3.5                     // px/sec downward
                let s = (time * speed) / Double(bandH)            // continuous scroll, in bands
                let newest = floor(s)
                let amp = bandH * 0.2
                // Background is the incoming band's hue, so any sliver above the topmost
                // wave crest bleeds in as the new colour instead of flashing to black.
                let incomingHue = fract((newest + 1) * 0.11)
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(hue: incomingHue, saturation: 0.9, brightness: 1.0)))
                let dx = max(size.width / 40, 4)
                let visible = 9
                func edgeY(_ x: CGFloat, _ base: CGFloat, _ phase: Double) -> CGFloat {
                    base + amp * CGFloat(sin(Double(x) * 0.012 + time * 0.8 + phase))
                }
                // Oldest first (bottom), newest last (top) so the incoming wave laps over.
                // n = -1 is the band still entering above the top edge (fills the top gap).
                for n in stride(from: visible, through: -1, by: -1) {
                    let k = newest - Double(n)                    // absolute band index
                    let topBase = CGFloat(s - k) * bandH          // grows downward, continuous
                    let botBase = topBase + bandH + amp           // slight overlap onto band below
                    let phaseTop = k * 1.7
                    let phaseBot = (k - 1) * 1.7
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: edgeY(0, topBase, phaseTop)))
                    var x: CGFloat = 0
                    while x <= size.width { path.addLine(to: CGPoint(x: x, y: edgeY(x, topBase, phaseTop))); x += dx }
                    path.addLine(to: CGPoint(x: size.width, y: edgeY(size.width, botBase, phaseBot)))
                    x = size.width
                    while x >= 0 { path.addLine(to: CGPoint(x: x, y: edgeY(x, botBase, phaseBot))); x -= dx }
                    path.closeSubpath()
                    let hue = fract(k * 0.11)
                    ctx.fill(path, with: .color(Color(hue: hue, saturation: 0.9, brightness: 1.0)))
                    // sheen along the leading (top) wavy edge
                    var edge = Path()
                    edge.move(to: CGPoint(x: 0, y: edgeY(0, topBase, phaseTop)))
                    x = 0
                    while x <= size.width { edge.addLine(to: CGPoint(x: x, y: edgeY(x, topBase, phaseTop))); x += dx }
                    ctx.stroke(edge, with: .color(.white.opacity(0.15)), lineWidth: 2)
                }
            }

        case .liquidSlosh:
            // Liquid ~60%-filling a box with a gently sloshing surface. Motion is the
            // physical tank-slosh mode `cos(π·u)` (liquid piles at one wall while it dips
            // at the other, level at the centre) plus a smaller 2nd mode and a tiny
            // travelling ripple. Body is lit near the surface and darkens with depth.
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color))
                let w = size.width, h = size.height
                let baseLevel = h * 0.42
                let dx = max(w / 80, 2)
                func surfaceY(_ x: CGFloat) -> CGFloat {
                    let u = Double(x / max(w, 1))
                    let s1 = 0.055 * Double(h) * cos(.pi * u) * sin(time * 1.1)          // fundamental slosh
                    let s2 = 0.022 * Double(h) * cos(2 * .pi * u) * sin(time * 1.7 + 0.6) // 2nd mode
                    let ripple = 0.010 * Double(h) * sin(5 * .pi * u - time * 2.2)        // fine ripple
                    return baseLevel + CGFloat(s1 + s2 + ripple)
                }
                // Sample the surface once and reuse for every layer.
                var pts: [CGPoint] = []
                var x: CGFloat = 0
                while x <= w { pts.append(CGPoint(x: x, y: surfaceY(x))); x += dx }
                if (pts.last?.x ?? 0) < w { pts.append(CGPoint(x: w, y: surfaceY(w))) }

                // Liquid body.
                var body = Path()
                body.move(to: pts[0])
                for p in pts { body.addLine(to: p) }
                body.addLine(to: CGPoint(x: w, y: h))
                body.addLine(to: CGPoint(x: 0, y: h))
                body.closeSubpath()
                ctx.fill(body, with: .color(color.color))
                // Depth shading: lit just under the surface, darker toward the bottom.
                ctx.fill(body, with: .linearGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(0.22), location: 0.0),
                        .init(color: .clear,               location: 0.22),
                        .init(color: .black.opacity(0.05), location: 0.55),
                        .init(color: .black.opacity(0.42), location: 1.0),
                    ]),
                    startPoint: CGPoint(x: 0, y: baseLevel - 0.06 * h),
                    endPoint: CGPoint(x: 0, y: h)))
                // Sunlit near-surface layer (thin lighter ribbon hugging the surface).
                var ribbon = Path()
                ribbon.move(to: pts[0])
                for p in pts { ribbon.addLine(to: p) }
                for p in pts.reversed() { ribbon.addLine(to: CGPoint(x: p.x, y: p.y + 10)) }
                ribbon.closeSubpath()
                ctx.fill(ribbon, with: .color(.white.opacity(0.14)))
                // Bright specular waterline.
                var surf = Path()
                surf.move(to: pts[0])
                for p in pts { surf.addLine(to: p) }
                ctx.stroke(surf, with: .color(.white.opacity(0.55)), lineWidth: 1.5)
            }

        case .pendulumPaint:
            Canvas { ctx, size in drawPendulumPaint(ctx: ctx, size: size) }

        default: EmptyView()
        }
    }

    /// Pendulum Paint: a hidden rotating, swaying paint bucket lays a
    /// harmonograph trail that accumulates into a painting, then holds, fades,
    /// and re-seeds a different figure. Pure function of `time` (see
    /// `PendulumPaint`). Trail is drawn in contiguous bands so hue and paint
    /// thickness (pooling where the path moves slowly) can vary along the arc.
    private func drawPendulumPaint(ctx: GraphicsContext, size: CGSize) {
        let W = size.width, H = size.height
        // Dark canvas backing so layered paint reads with depth.
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.07)))
        let rainbow = paint?.rainbow ?? true

        // Cycle: draw → hold → fade, then next figure.
        let cycleLen = 90.0
        let idx = Int(floor(time / cycleLen))
        let ct = time.truncatingRemainder(dividingBy: cycleLen) / cycleLen   // 0..1
        let drawEnd = 0.72, holdEnd = 0.90
        let reveal = min(1.0, ct / drawEnd)
        let fade: Double = ct <= holdEnd ? 1.0 : max(0.0, 1.0 - (ct - holdEnd) / (1.0 - holdEnd))
        guard fade > 0.001 else { return }

        let norm = PendulumPaint.samples(cycle: idx)
        guard norm.count > 2 else { return }
        let pts = norm.map { CGPoint(x: $0.x * W, y: $0.y * H) }

        // Cumulative arc length in pixels.
        var cum = [Double](repeating: 0, count: pts.count)
        for i in 1..<pts.count {
            cum[i] = cum[i - 1] + Double(hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y))
        }
        let total = cum[pts.count - 1]
        guard total > 0 else { return }
        let target = reveal * total
        let medianSeg = total / Double(pts.count - 1)

        let baseW = max(1.5, min(W, H) * 0.011)

        // Later paint reads slightly lighter (layered on top) when single-color.
        func lighten(_ t: Double) -> Color {
            let f = 0.35 * t
            return Color(red: color.r + (1 - color.r) * f,
                         green: color.g + (1 - color.g) * f,
                         blue: color.b + (1 - color.b) * f)
        }

        // Walk the trail in contiguous index chunks; each chunk strokes once with
        // its own hue + width, truncated at the revealed head.
        let bands = 64
        let chunk = max(1, (pts.count - 1) / bands)
        var head = pts[0]
        var i = 0
        stroke: while i < pts.count - 1 {
            let a = i
            let b = min(i + chunk, pts.count - 1)
            i = b
            if cum[a] >= target { break }

            var path = Path()
            path.move(to: pts[a])
            var last = pts[a]
            for k in (a + 1)...b {
                if cum[k] <= target {
                    path.addLine(to: pts[k]); last = pts[k]
                } else {
                    // Interpolate the exact head position within this segment.
                    let segStart = cum[k - 1], segLen = cum[k] - segStart
                    let f = segLen > 0 ? CGFloat((target - segStart) / segLen) : 0
                    let hp = CGPoint(x: pts[k - 1].x + (pts[k].x - pts[k - 1].x) * f,
                                     y: pts[k - 1].y + (pts[k].y - pts[k - 1].y) * f)
                    path.addLine(to: hp); last = hp; head = hp
                    strokeBand(ctx, path, a: a, b: b, cum: cum, total: total, idx: idx,
                               baseW: baseW, medianSeg: medianSeg, rainbow: rainbow,
                               fade: fade, lighten: lighten)
                    break stroke
                }
            }
            head = last
            strokeBand(ctx, path, a: a, b: b, cum: cum, total: total, idx: idx,
                       baseW: baseW, medianSeg: medianSeg, rainbow: rainbow,
                       fade: fade, lighten: lighten)
        }

        // Wet paint head: a glowing dab riding the tip while the painting is
        // still being laid down.
        if reveal < 1.0 {
            let u = target / total
            let hue = (u * 1.5 + Double(idx) * 0.11).truncatingRemainder(dividingBy: 1.0)
            let headColor = rainbow ? Color(hue: hue, saturation: 0.85, brightness: 1.0) : lighten(0.6)
            ctx.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.addFilter(.blur(radius: baseW * 1.6))
                let r = baseW * 2.4
                layer.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(headColor.opacity(0.9 * fade)))
                let rc = baseW * 0.9
                layer.fill(Path(ellipseIn: CGRect(x: head.x - rc, y: head.y - rc, width: 2 * rc, height: 2 * rc)),
                           with: .color(.white.opacity(0.9 * fade)))
            }
        }
    }

    /// Stroke one band of the pendulum-paint trail: hue by arc position, width
    /// thicker where the path moves slowly (paint pooling), with a lighter core.
    private func strokeBand(_ ctx: GraphicsContext, _ path: Path, a: Int, b: Int,
                            cum: [Double], total: Double, idx: Int,
                            baseW: CGFloat, medianSeg: Double, rainbow: Bool,
                            fade: Double, lighten: (Double) -> Color) {
        let u = (cum[a] + (cum[b] - cum[a]) * 0.5) / total       // arc position 0..1
        let avgSeg = max(1e-6, (cum[b] - cum[a]) / Double(max(1, b - a)))
        // Slow (small avgSeg) → thicker paint. Clamp so it stays sane.
        let poolFactor = min(2.4, max(0.7, medianSeg / avgSeg))
        let w = baseW * CGFloat(poolFactor)

        let paintColor: Color
        if rainbow {
            let hue = (u * 1.5 + Double(idx) * 0.11).truncatingRemainder(dividingBy: 1.0)
            paintColor = Color(hue: hue, saturation: 0.82, brightness: 0.95)
        } else {
            paintColor = lighten(u)
        }
        ctx.stroke(path, with: .color(paintColor.opacity(0.92 * fade)),
                   style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        // Lighter core for a wet sheen.
        ctx.stroke(path, with: .color(.white.opacity(0.16 * fade)),
                   style: StrokeStyle(lineWidth: max(1, w * 0.35), lineCap: .round, lineJoin: .round))
    }

    @ViewBuilder private var retroEffects: some View {
        switch kind {
        case .tvStatic:
            Canvas { ctx, size in
                let cell: CGFloat = 24
                let cols = Int(size.width / cell) + 1
                let rows = Int(size.height / cell) + 1
                let frame = Int(time * 20)
                for row in 0..<rows {
                    for col in 0..<cols {
                        let idx = row * 1000 + col
                        let v = hash01(idx, frame)
                        let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                        ctx.fill(Path(rect), with: .color(Color(white: Double(v))))
                    }
                }
            }

        case .matrixRain:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.02)))
                let glyphs = Array("01アイウエオカキクケコ")
                let colWidth: CGFloat = 24
                let cols = Int(size.width / colWidth)
                let rowHeight: CGFloat = 20
                for c in 0..<cols {
                    let speed = 2.0 + Double(hash01(c, 1)) * 3.0
                    let colLen = 6 + Int(hash01(c, 2) * 8)
                    let headY = fract(Double(hash01(c, 3)) + time * speed * 0.1)
                        * Double(size.height + CGFloat(colLen) * rowHeight)
                    for k in 0..<colLen {
                        let y = headY - Double(k) * Double(rowHeight)
                        if y < 0 || y > Double(size.height) { continue }
                        let epoch = Int(time * 4)
                        let glyphIdx = Int(Double(hash01(c * 31 + k, epoch)) * Double(glyphs.count))
                        let glyph = String(glyphs[glyphIdx % glyphs.count])
                        let bright = k == 0
                        let tint = bright ? accent.color : color.color.opacity(max(0.15, 1 - Double(k) / Double(colLen)))
                        let text = Text(glyph).font(.system(size: 15, design: .monospaced)).foregroundColor(tint)
                        ctx.draw(text, at: CGPoint(x: CGFloat(c) * colWidth + colWidth / 2, y: CGFloat(y)))
                    }
                }
            }

        case .pixelDissolve:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black))
                let cell: CGFloat = 30
                let cols = Int(size.width / cell) + 1
                let rows = Int(size.height / cell) + 1
                for row in 0..<rows {
                    for col in 0..<cols {
                        let idx = row * 1000 + col
                        let phase = Double(hash01(idx, 7))
                        let t = 0.5 + 0.5 * sin(time * 1.2 + phase * 6.28)
                        let mix = t > 0.5 ? accent.color : color.color
                        let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell - 2, height: cell - 2)
                        ctx.fill(Path(rect), with: .color(mix.opacity(0.6 + 0.4 * t)))
                    }
                }
            }

        case .dvdBounce:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black))
                let w: CGFloat = 90, h: CGFloat = 60
                let rangeX = Double(size.width - w)
                let rangeY = Double(size.height - h)
                let rawX = time * 90.0
                let rawY = time * 70.0
                let cycleX = rawX.truncatingRemainder(dividingBy: rangeX * 2)
                let cycleY = rawY.truncatingRemainder(dividingBy: rangeY * 2)
                let posX = cycleX <= rangeX ? cycleX : rangeX * 2 - cycleX
                let posY = cycleY <= rangeY ? cycleY : rangeY * 2 - cycleY
                let bounceCountX = Int(rawX / rangeX)
                let bounceCountY = Int(rawY / rangeY)
                let tint = (bounceCountX + bounceCountY) % 2 == 0 ? color.color : accent.color
                let rect = CGRect(x: CGFloat(posX), y: CGFloat(posY), width: w, height: h)
                ctx.fill(Path(rect), with: .color(tint))
            }
        case .marqueeText:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color))
                let cfg = marquee ?? MarqueeConfig()
                let base = cfg.text.isEmpty ? (name.isEmpty ? "LUMORA" : name) : cfg.text
                let label = base + "     "
                let font: Font = cfg.fontName.isEmpty
                    ? .system(size: cfg.fontSize, weight: .bold, design: .monospaced)
                    : .custom(cfg.fontName, size: cfg.fontSize)

                // Measure each character once so a rainbow run can color glyphs
                // individually while the whole string tiles seamlessly.
                let chars = Array(label)
                var widths: [CGFloat] = []
                widths.reserveCapacity(chars.count)
                var unitWidth: CGFloat = 0
                for ch in chars {
                    let w = ctx.resolve(Text(String(ch)).font(font))
                        .measure(in: CGSize(width: 10000, height: 10000)).width
                    widths.append(w)
                    unitWidth += w
                }
                if unitWidth < 1 { unitWidth = 1 }

                let scrollSpeed: CGFloat = 120
                let offset = CGFloat(time) * scrollSpeed
                var tileX = -offset.truncatingRemainder(dividingBy: unitWidth)
                if tileX > 0 { tileX -= unitWidth }
                let y = size.height / 2
                let denom = Double(max(chars.count, 1))
                while tileX < size.width {
                    var x = tileX
                    for (i, ch) in chars.enumerated() {
                        let w = widths[i]
                        let col: Color = cfg.rainbow
                            ? Color(hue: (Double(i) / denom + time * 0.08).truncatingRemainder(dividingBy: 1),
                                    saturation: 0.95, brightness: 1)
                            : color.color
                        ctx.draw(Text(String(ch)).font(font).foregroundColor(col),
                                 at: CGPoint(x: x + w / 2, y: y))
                        x += w
                    }
                    tileX += unitWidth
                }
            }

        default: EmptyView()
        }
    }

    @ViewBuilder private var fieldEffects: some View {
        switch kind {
        case .voronoi:
            Canvas { ctx, size in drawVoronoi(ctx: ctx, size: size) }

        case .metaballs:
            Canvas { ctx, size in drawMetaballs(ctx: ctx, size: size) }

        case .hexGrid:
            Canvas { ctx, size in drawHexGrid(ctx: ctx, size: size) }

        default: EmptyView()
        }
    }

    @ViewBuilder private var geometryEffects: some View {
        switch kind {
        case .vectorGrid:
            Canvas { ctx, size in drawVectorGrid(ctx: ctx, size: size) }

        case .particleMesh:
            Canvas { ctx, size in drawParticleMesh(ctx: ctx, size: size) }

        default: EmptyView()
        }
    }

    @ViewBuilder private var ambientEffects: some View {
        switch kind {
        case .livingTexture:
            Canvas { ctx, size in drawLivingTexture(ctx: ctx, size: size) }

        case .gameOfLife:
            Canvas { ctx, size in drawGameOfLife(ctx: ctx, size: size) }

        case .flowingPlasma:
            Canvas { ctx, size in drawFlowingPlasma(ctx: ctx, size: size) }

        case .driftingNebula:
            Canvas { ctx, size in drawDriftingNebula(ctx: ctx, size: size) }

        case .perlinFlow:
            Canvas { ctx, size in drawPerlinFlow(ctx: ctx, size: size) }

        case .circuitTrace:
            Canvas { ctx, size in drawCircuit(ctx: ctx, size: size) }

        case .reactionDiffusion:
            ReactionDiffusionContent(color: color, accent: accent, time: time)

        default: EmptyView()
        }
    }

    @ViewBuilder private var threeDEffects: some View {
        switch kind {
        case .torus3D:
            Canvas { ctx, size in drawTorus3D(ctx: ctx, size: size) }
        case .sphere3D:
            Canvas { ctx, size in drawSphere3D(ctx: ctx, size: size) }
        case .pointCloud3D:
            Canvas { ctx, size in drawPointCloud3D(ctx: ctx, size: size) }
        default: EmptyView()
        }
    }

    @ViewBuilder private var edgeEffects: some View {
        switch kind {
        case .outlineGlow:
            OutlineGlowView(color: color, accent: accent, time: time, outline: outline)
        case .growingIvy:
            GrowingIvyView(color: color, accent: accent, time: time, outline: outline)

        default: EmptyView()
        }
    }

    @ViewBuilder private var clockEffects: some View {
        switch kind {
        case .analogClock:
            Canvas { ctx, size in drawAnalogClock(ctx: ctx, size: size) }

        case .digitalClock:
            DigitalClockView(color: color, accent: accent, time: time)

        case .weatherWidget:
            WeatherWidgetView(time: time)

        default: EmptyView()
        }
    }

    /// Map flame "temperature" (0 = cool dark red … 1 = white-hot) to colour.
    private func fireColor(_ t: Double) -> Color {
        if t > 0.8 { let k = (t - 0.8) / 0.2; return Color(red: 1, green: 0.9 + 0.1 * k, blue: 0.55 + 0.4 * k) }
        if t > 0.5 { let k = (t - 0.5) / 0.3; return Color(red: 1, green: 0.55 + 0.35 * k, blue: 0.10 + 0.12 * k) }
        if t > 0.2 { let k = (t - 0.2) / 0.3; return Color(red: 0.92 + 0.08 * k, green: 0.18 + 0.37 * k, blue: 0.0) }
        let k = t / 0.2; return Color(red: 0.45 + 0.47 * k, green: 0.02 + 0.16 * k, blue: 0.0)
    }

    private func drawFire(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        // Additive, blurred flame particles rising from the base.
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.addFilter(.blur(radius: 9))
            drawFireGlow(&layer, size: size)
            drawFlameParticles(&layer, size: size)
            drawEmbers(&layer, size: size)
        }
    }

    /// Warm base glow so the fire has a bright, grounded root.
    private func drawFireGlow(_ layer: inout GraphicsContext, size: CGSize) {
        let glowH: CGFloat = size.height * 0.4
        let rect = CGRect(x: 0, y: size.height - glowH, width: size.width, height: glowH)
        let colors: [Color] = [Color(red: 1.0, green: 0.45, blue: 0.08).opacity(0.5), .clear]
        layer.fill(Path(rect), with: .linearGradient(
            Gradient(colors: colors),
            startPoint: CGPoint(x: 0, y: size.height),
            endPoint: CGPoint(x: 0, y: size.height - glowH)))
    }

    private func drawFlameParticles(_ layer: inout GraphicsContext, size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        for i in 0..<70 {
            let speed: Double = 0.5 + Double(hash01(i, 2)) * 0.9
            let riseT: Double = fract(Double(hash01(i, 3)) + time * speed)   // 0 base … 1 top
            // Concentrate flames toward the centre for a natural fire shape.
            let spread: Double = 0.5 + (Double(hash01(i, 1)) - 0.5) * (0.9 - riseT * 0.4)
            let flicker: Double = sin(time * (3 + Double(hash01(i, 6)) * 4) + Double(i) * 1.7)
            let sway: Double = flicker * (8 + riseT * 26)
            let x: Double = spread * w + sway
            let y: Double = h * (1 - riseT * 0.98) - h * 0.02
            // Hottest at the base, cooling as it rises; flicker jitters it.
            let temp: Double = max(0, (1 - riseT * 1.05) + flicker * 0.06)
            let r: Double = (10.0 + Double(hash01(i, 4)) * 12.0) * (1 - riseT * 0.55)
            let alpha: Double = min(1, (1 - riseT) * 1.6) * (0.55 + 0.45 * (0.5 + 0.5 * flicker))
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            let colors: [Color] = [fireColor(temp).opacity(alpha), .clear]
            layer.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: colors),
                center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
        }
    }

    /// A few bright rising embers/sparks.
    private func drawEmbers(_ layer: inout GraphicsContext, size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        for i in 0..<14 {
            let speed: Double = 0.7 + Double(hash01(i, 11)) * 0.9
            let riseT: Double = fract(Double(hash01(i, 12)) + time * speed)
            let x: Double = Double(hash01(i, 13)) * w + sin(time * 3 + Double(i)) * 20
            let y: Double = h * (1 - riseT)
            let er: Double = 1.5 + Double(hash01(i, 14)) * 1.5
            let rect = CGRect(x: x - er, y: y - er, width: er * 2, height: er * 2)
            let ember = Color(red: 1, green: 0.8, blue: 0.4).opacity((1 - riseT) * 0.9)
            layer.fill(Path(ellipseIn: rect), with: .color(ember))
        }
    }

    private func drawBubbles(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.05)))
        // Transparent soap bubbles: a near-clear body so the background shows
        // through, a thin iridescent (pastel spectrum) film on the rim, and a
        // small offset specular glint. Normal blending for the body keeps
        // overlaps from glowing like metal; only the glints are additive.
        for i in 0..<34 {
            let speed = 0.12 + Double(hash01(i, 1)) * 0.26
            let riseT = fract(Double(hash01(i, 2)) + time * speed)
            let y = Double(size.height) * (1 - riseT)
            let baseX = Double(hash01(i, 3)) * Double(size.width)
            let wobble = sin(time * 1.1 + Double(i) * 2.1) * 12
            let x = baseX + wobble
            let r = 7.0 + Double(hash01(i, 4)) * 20.0
            let cx = CGFloat(x), cy = CGFloat(y)
            let rect = CGRect(x: cx - CGFloat(r), y: cy - CGFloat(r), width: CGFloat(r * 2), height: CGFloat(r * 2))
            let hueShift = Double(hash01(i, 5))

            // Faint see-through body: clear center → a whisper of tint that only
            // gathers near the film at the edge.
            let tint = Color(hue: fract(0.55 + hueShift * 0.25), saturation: 0.22, brightness: 1.0)
            ctx.fill(Path(ellipseIn: rect),
                     with: .radialGradient(
                        Gradient(stops: [
                            .init(color: .white.opacity(0.015), location: 0.0),
                            .init(color: tint.opacity(0.05), location: 0.65),
                            .init(color: tint.opacity(0.16), location: 0.93),
                            .init(color: .white.opacity(0.06), location: 1.0),
                        ]),
                        center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: CGFloat(r)))

            // Iridescent film on the rim — pastel spectrum, thin and soft,
            // slowly rotating so the sheen shifts.
            let irid = Gradient(colors: [
                Color(hue: 0.95, saturation: 0.32, brightness: 1),   // pink
                Color(hue: 0.55, saturation: 0.32, brightness: 1),   // cyan
                Color(hue: 0.33, saturation: 0.30, brightness: 1),   // green
                Color(hue: 0.75, saturation: 0.32, brightness: 1),   // violet
                Color(hue: 0.08, saturation: 0.28, brightness: 1),   // warm
                Color(hue: 0.95, saturation: 0.32, brightness: 1),   // back to pink
            ])
            ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 1, dy: 1)),
                       with: .conicGradient(irid, center: CGPoint(x: cx, y: cy),
                                            angle: .radians(time * 0.5 + hueShift * 6.28)),
                       lineWidth: max(1, CGFloat(r * 0.11)))
            // Crisp thin outer edge.
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.16)), lineWidth: 1)

            // Specular glints (additive, localized so overlaps stay glassy).
            ctx.drawLayer { layer in
                layer.blendMode = .plusLighter
                let gx = cx - CGFloat(r * 0.38), gy = cy - CGFloat(r * 0.38)
                let gr = CGFloat(r * 0.5)
                layer.fill(Path(ellipseIn: CGRect(x: gx - gr, y: gy - gr, width: gr * 2, height: gr * 2)),
                           with: .radialGradient(
                                Gradient(colors: [.white.opacity(0.7), .white.opacity(0)]),
                                center: CGPoint(x: gx, y: gy), startRadius: 0, endRadius: gr))
                let sr = CGFloat(r * 0.1)
                layer.fill(Path(ellipseIn: CGRect(x: gx - sr, y: gy - sr, width: sr * 2, height: sr * 2)),
                           with: .color(.white.opacity(0.85)))
                // faint reflected catchlight, lower-right
                let lx = cx + CGFloat(r * 0.4), ly = cy + CGFloat(r * 0.45), lr = CGFloat(r * 0.14)
                layer.fill(Path(ellipseIn: CGRect(x: lx - lr, y: ly - lr, width: lr * 2, height: lr * 2)),
                           with: .color(.white.opacity(0.18)))
            }
        }
    }

    private func drawAnalogClock(ctx: GraphicsContext, size: CGSize) {
        // Real local time reconstructed from the global reference clock.
        let date = Date(timeIntervalSinceReferenceDate: time)
        let comps = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let hours = Double(comps.hour ?? 0)
        let minutes = Double(comps.minute ?? 0)
        let seconds = Double(comps.second ?? 0) + Double(comps.nanosecond ?? 0) / 1_000_000_000

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = Double(min(size.width, size.height)) * 0.45
        let lw = max(2.0, radius * 0.02)

        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.05)))
        let faceRect = CGRect(x: center.x - CGFloat(radius), y: center.y - CGFloat(radius),
                              width: CGFloat(radius * 2), height: CGFloat(radius * 2))
        ctx.fill(Path(ellipseIn: faceRect), with: .color(Color(white: 0.09)))
        ctx.stroke(Path(ellipseIn: faceRect), with: .color(color.color.opacity(0.75)), lineWidth: CGFloat(lw))

        // Minute/hour ticks.
        for i in 0..<60 {
            let a: Double = Double(i) / 60 * 2 * .pi - .pi / 2
            let isHour = i % 5 == 0
            let inner: Double = radius * (isHour ? 0.83 : 0.90)
            let outer: Double = radius * 0.96
            let p1 = CGPoint(x: center.x + CGFloat(cos(a) * inner), y: center.y + CGFloat(sin(a) * inner))
            let p2 = CGPoint(x: center.x + CGFloat(cos(a) * outer), y: center.y + CGFloat(sin(a) * outer))
            var tick = Path(); tick.move(to: p1); tick.addLine(to: p2)
            ctx.stroke(tick, with: .color(color.color.opacity(isHour ? 0.9 : 0.4)),
                       lineWidth: CGFloat(isHour ? lw : 1))
        }

        // Hands.
        func hand(angle: Double, length: Double, width: Double, tint: Color) {
            let a: Double = angle - .pi / 2
            let end = CGPoint(x: center.x + CGFloat(cos(a) * length), y: center.y + CGFloat(sin(a) * length))
            let tail = CGPoint(x: center.x - CGFloat(cos(a) * length * 0.15), y: center.y - CGFloat(sin(a) * length * 0.15))
            var p = Path(); p.move(to: tail); p.addLine(to: end)
            ctx.stroke(p, with: .color(tint), style: StrokeStyle(lineWidth: CGFloat(width), lineCap: .round))
        }
        let hourAngle: Double = (hours.truncatingRemainder(dividingBy: 12) + minutes / 60) / 12 * 2 * .pi
        let minuteAngle: Double = (minutes + seconds / 60) / 60 * 2 * .pi
        let secondAngle: Double = seconds / 60 * 2 * .pi
        hand(angle: hourAngle, length: radius * 0.5, width: max(3, radius * 0.035), tint: color.color)
        hand(angle: minuteAngle, length: radius * 0.74, width: max(2, radius * 0.025), tint: color.color)
        hand(angle: secondAngle, length: radius * 0.84, width: max(1, radius * 0.012), tint: accent.color)

        let hubR = CGFloat(radius * 0.045)
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - hubR, y: center.y - hubR, width: hubR * 2, height: hubR * 2)),
                 with: .color(accent.color))
    }

    // A handful of shells launch at a relaxed cadence; roughly a quarter of them
    // are large multi-ring "grand" bursts.
    private static let fireworkShells = 5
    /// Multiplier on the fireworks clock; < 1 slows the whole cycle down.
    private static let fireworkSpeed: Double = 0.6

    /// Stylized 5-lobe maple-leaf outline, normalized to roughly [-1, 1]
    /// (y-down), tip up and stem at the bottom.
    private static let mapleUnit: [CGPoint] = [
        CGPoint(x: 0.00, y: -1.00), CGPoint(x: 0.16, y: -0.55), CGPoint(x: 0.55, y: -0.62),
        CGPoint(x: 0.34, y: -0.28), CGPoint(x: 0.95, y: -0.20), CGPoint(x: 0.52, y: 0.05),
        CGPoint(x: 0.62, y: 0.45), CGPoint(x: 0.22, y: 0.30), CGPoint(x: 0.16, y: 0.85),
        CGPoint(x: 0.00, y: 1.00), CGPoint(x: -0.16, y: 0.85), CGPoint(x: -0.22, y: 0.30),
        CGPoint(x: -0.62, y: 0.45), CGPoint(x: -0.52, y: 0.05), CGPoint(x: -0.95, y: -0.20),
        CGPoint(x: -0.34, y: -0.28), CGPoint(x: -0.55, y: -0.62), CGPoint(x: -0.16, y: -0.55),
    ]

    private static func mapleLeafPath(scale s: CGFloat) -> Path {
        var p = Path()
        let pts = mapleUnit
        p.move(to: CGPoint(x: pts[0].x * s, y: pts[0].y * s))
        for pt in pts.dropFirst() { p.addLine(to: CGPoint(x: pt.x * s, y: pt.y * s)) }
        p.closeSubpath()
        return p
    }

    private struct KaleidoMotif { var ang: Double; var r: Double; var s: CGFloat; var hue: Double; var core: Bool }

    /// A dense, rainbow kaleidoscope: one wedge packed with multi-hued motifs
    /// spanning the full radius, mirrored across every segment.
    private func drawKaleidoscope(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let segments = 12
        let wedge = 2 * Double.pi / Double(segments)
        let maxR = Double(min(size.width, size.height)) / 2
        var motifs: [KaleidoMotif] = []
        let n = 18
        for i in 0..<n {
            let fi = Double(i)
            let spread: Double = 0.2 + 0.8 * fract(sin(fi * 3.3) * 43758.5453)
            let ang: Double = 0.05 + (wedge - 0.1) * spread + sin(time * 0.4 + fi) * 0.05
            let r: Double = maxR * (0.08 + 0.9 * fi / Double(n)) * (0.82 + 0.18 * sin(time * 0.7 + fi * 1.1))
            let s: CGFloat = CGFloat(maxR * (0.045 + 0.085 * (0.5 + 0.5 * sin(time * 0.9 + fi * 2.1))))
            let hue: Double = fract(fi / Double(n) + time * 0.06)
            motifs.append(KaleidoMotif(ang: ang, r: r, s: s, hue: hue, core: i % 3 == 0))
        }
        for seg in 0..<segments {
            ctx.drawLayer { layer in
                layer.translateBy(x: center.x, y: center.y)
                layer.rotate(by: .radians(Double(seg) * wedge + time * 0.1))
                if seg % 2 == 1 { layer.scaleBy(x: -1, y: 1) }   // mirror alternate wedges
                for m in motifs {
                    let p = point(.zero, m.ang, m.r)
                    let col = Color(hue: m.hue, saturation: 0.9, brightness: 1)
                    layer.fill(Path(ellipseIn: CGRect(x: p.x - m.s, y: p.y - m.s, width: m.s * 2, height: m.s * 2)),
                               with: .color(col.opacity(0.85)))
                    if m.core {
                        let cs = m.s * 0.45
                        layer.fill(Path(ellipseIn: CGRect(x: p.x - cs, y: p.y - cs, width: cs * 2, height: cs * 2)),
                                   with: .color(.white.opacity(0.7)))
                    }
                }
            }
        }
    }

    private func drawFireworks(ctx: GraphicsContext, size: CGSize) {
        // Night sky.
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.02, green: 0.02, blue: 0.07), .black]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        // Additive with a soft bloom.
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.addFilter(.blur(radius: 3))
            for s in 0..<Self.fireworkShells { drawFireworkShell(&layer, shell: s, size: size) }
        }
    }

    private func drawFireworkShell(_ layer: inout GraphicsContext, shell s: Int, size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        let minDim = Double(min(size.width, size.height))
        let launchDur: Double = 1.2
        let burstDur: Double = 3.2
        let period: Double = launchDur + burstDur
        // Relaxed, evenly-staggered launches so a few bursts hang in the sky at once.
        let tt: Double = time * Self.fireworkSpeed + Double(s) * period / Double(Self.fireworkShells)
        let cycle: Double = floor(tt / period)
        let lt: Double = tt - cycle * period
        let seed: Int = Int(cycle) &* 131 &+ s &* 977
        let launchX: Double = (0.14 + Double(hash01(seed, 1)) * 0.72) * w
        let burstY: Double = (0.10 + Double(hash01(seed, 2)) * 0.30) * h
        let hue: Double = Double(hash01(seed, 3))
        let roll: Double = Double(hash01(seed, 9))
        let mega: Bool = roll > 0.90               // ~10% — rare, ~2× a grand burst
        let grand: Bool = roll > 0.64 && !mega     // ~26%

        if lt < launchDur {
            // Rising rocket with a flickering spark trail.
            let p: Double = lt / launchDur
            let ease: Double = 1 - (1 - p) * (1 - p)       // ease-out rise
            let y: Double = h + (burstY - h) * ease
            // Longer, brighter rising spark trail.
            let trailN: Int = mega ? 24 : 16
            let launchR: Double = mega ? 4.6 : (grand ? 3.4 : 2.6)
            for k in 0..<trailN {
                let ky: Double = y + Double(k) * 6
                let r: Double = launchR - Double(k) * 0.18
                if r <= 0 { continue }
                let a: Double = (1 - Double(k) / Double(trailN)) * (1 - p * 0.15) * (0.6 + 0.4 * Double(hash01(seed, k + 30)))
                let rect = CGRect(x: launchX - r, y: ky - r, width: r * 2, height: r * 2)
                layer.fill(Path(ellipseIn: rect),
                           with: .color(Color(red: 1, green: 0.85, blue: 0.5).opacity(a)))
            }
            return
        }

        // Burst: radial spray of spark streaks, expanding with air-drag and
        // drooping under gravity, fading out over the shell's life.
        let bt: Double = (lt - launchDur) / burstDur       // 0 … 1
        let dragPow: Double = 3                             // strong ease-out = air drag
        let expand: Double = 1 - pow(1 - bt, dragPow)
        let btPrev: Double = max(0, bt - (mega ? 0.18 : 0.12))   // longer look-back → longer visible trails
        let expandPrev: Double = 1 - pow(1 - btPrev, dragPow)
        let maxR: Double = minDim * (mega ? 0.80 : (grand ? 0.42 : 0.26))
        let gravity: Double = minDim * (mega ? 0.42 : (grand ? 0.32 : 0.22))
        let drop: Double = gravity * bt * bt
        let dropPrev: Double = gravity * btPrev * btPrev
        let fade: Double = pow(max(0, 1 - bt), mega ? 0.7 : (grand ? 0.85 : 1.05))   // slower fade → trails linger
        let particles = mega ? 240 : (grand ? 132 : 70)

        // Bright ignition flash.
        let flashDur: Double = 0.15
        if bt < flashDur {
            let ff: Double = 1 - bt / flashDur
            let fr: Double = maxR * (mega ? 0.7 : (grand ? 0.75 : 0.55)) * (0.25 + bt / flashDur)
            let rect = CGRect(x: launchX - fr, y: burstY - fr, width: fr * 2, height: fr * 2)
            layer.fill(Path(ellipseIn: rect),
                       with: .radialGradient(Gradient(colors: [Color.white.opacity(ff), .clear]),
                                             center: CGPoint(x: launchX, y: burstY), startRadius: 0, endRadius: fr))
        }

        for pI in 0..<particles {
            // Bigger tiers split into concentric rings with a hue offset per ring.
            let ring: Double
            let ringHue: Double
            if mega {
                switch pI % 3 {
                case 0: ring = 1.0;  ringHue = 0
                case 1: ring = 0.72; ringHue = 0.10
                default: ring = 0.48; ringHue = 0.20
                }
            } else if grand && pI % 2 == 0 {
                ring = 0.6; ringHue = 0.12
            } else {
                ring = 1.0; ringHue = 0
            }
            let ang: Double = Double(pI) / Double(particles) * 2 * .pi + Double(hash01(seed, pI + 10)) * 0.22
            // Wide speed spread → a filled, spherical burst rather than a thin ring.
            let spd: Double = (0.28 + Double(hash01(seed, pI + 50)) * 0.72) * ring
            let dist: Double = maxR * spd * expand
            let distPrev: Double = maxR * spd * expandPrev
            let px: Double = launchX + cos(ang) * dist
            let py: Double = burstY + sin(ang) * dist + drop
            let pxPrev: Double = launchX + cos(ang) * distPrev
            let pyPrev: Double = burstY + sin(ang) * distPrev + dropPrev
            let ph: Double = fract(hue + ringHue + (Double(hash01(seed, pI)) - 0.5) * 0.1)
            let twinkle: Double = 0.72 + 0.28 * sin(time * 40 + Double(pI) * 1.3)
            let alpha: Double = fade * twinkle
            let col = Color(hue: ph, saturation: 0.82, brightness: 1)
            let lwid: Double = (mega ? 3.6 : (grand ? 3.0 : 2.4)) * (0.5 + 0.5 * fade)
            // Motion-blur streak from the previous position to the current one.
            var streak = Path()
            streak.move(to: CGPoint(x: pxPrev, y: pyPrev))
            streak.addLine(to: CGPoint(x: px, y: py))
            layer.stroke(streak, with: .color(col.opacity(min(1, alpha * 1.15))),
                         style: StrokeStyle(lineWidth: lwid, lineCap: .round))
            // Bright head.
            let hr: Double = lwid * 0.95
            let rect = CGRect(x: px - hr, y: py - hr, width: hr * 2, height: hr * 2)
            layer.fill(Path(ellipseIn: rect), with: .color(col.opacity(alpha)))
            // Extra long, tapered comet tail for the grandest (mega) bursts.
            if mega {
                let btPrev2: Double = max(0, bt - 0.34)
                let expandPrev2: Double = 1 - pow(1 - btPrev2, dragPow)
                let dropPrev2: Double = gravity * btPrev2 * btPrev2
                let px2: Double = launchX + cos(ang) * maxR * spd * expandPrev2
                let py2: Double = burstY + sin(ang) * maxR * spd * expandPrev2 + dropPrev2
                var tail = Path()
                tail.move(to: CGPoint(x: px2, y: py2))
                tail.addLine(to: CGPoint(x: pxPrev, y: pyPrev))
                layer.stroke(tail, with: .color(col.opacity(min(1, alpha * 0.45))),
                             style: StrokeStyle(lineWidth: lwid * 0.6, lineCap: .round))
            }
        }
    }

    private func drawVoronoi(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        let siteCount = 20
        var sites: [(x: Double, y: Double, hue: Double)] = []
        sites.reserveCapacity(siteCount)
        for i in 0..<siteCount {
            let fi = Double(i)
            let baseX = fract(sin(fi * 12.9898) * 43758.5453)
            let baseY = fract(sin(fi * 78.233) * 43758.5453)
            let hue = fract(sin(fi * 45.164) * 43758.5453)
            let x = (baseX + sin(time * 0.4 + fi) * 0.1) * Double(size.width)
            let y = (baseY + cos(time * 0.5 + fi * 1.3) * 0.1) * Double(size.height)
            sites.append((x, y, hue))
        }
        // Build each cell as an exact convex polygon by clipping the canvas
        // rect against the perpendicular bisector with every other site
        // (O(sites²) — cheap — and crisp vector edges, no pixel sampling).
        for s in sites {
            var poly = [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
                        CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)]
            for o in sites {
                if o.x == s.x && o.y == s.y { continue }
                // Keep the half-plane closer to `s`: n·p <= c.
                let nx = o.x - s.x, ny = o.y - s.y
                let c = (o.x * o.x + o.y * o.y - s.x * s.x - s.y * s.y) / 2
                poly = Self.clipHalfPlane(poly, nx: nx, ny: ny, c: c)
                if poly.count < 3 { break }
            }
            guard poly.count >= 3 else { continue }
            var path = Path()
            path.addLines(poly)
            path.closeSubpath()
            let hue = fract(s.hue + time * 0.05)
            ctx.fill(path, with: .color(Color(hue: hue, saturation: 0.9, brightness: 1.0)))
            // Dark seam between cells for definition.
            ctx.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: 1.5)
        }
    }

    /// Sutherland–Hodgman clip of a convex polygon to the half-plane n·p ≤ c.
    private static func clipHalfPlane(_ poly: [CGPoint], nx: Double, ny: Double, c: Double) -> [CGPoint] {
        guard poly.count >= 3 else { return [] }
        var out: [CGPoint] = []
        out.reserveCapacity(poly.count + 1)
        for i in 0..<poly.count {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            let da = nx * Double(a.x) + ny * Double(a.y) - c
            let db = nx * Double(b.x) + ny * Double(b.y) - c
            let ain = da <= 0, bin = db <= 0
            if ain { out.append(a) }
            if ain != bin {
                let t = da / (da - db)
                out.append(CGPoint(x: a.x + CGFloat(t) * (b.x - a.x),
                                   y: a.y + CGFloat(t) * (b.y - a.y)))
            }
        }
        return out
    }

    private func drawMetaballs(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color))
        let minDim = Double(min(size.width, size.height))
        let w = Double(size.width), h = Double(size.height)
        var balls: [CGRect] = []
        balls.reserveCapacity(6)
        for i in 0..<6 {
            let fi = Double(i)
            let ox: Double = cos(time * (0.6 + fi * 0.1) + fi) * w * 0.35
            let oy: Double = sin(time * (0.5 + fi * 0.13) + fi * 1.3) * h * 0.35
            let bx: Double = w / 2 + ox
            let by: Double = h / 2 + oy
            let br: Double = minDim * (0.07 + fi * 0.012)
            balls.append(CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2))
        }
        // Classic "gooey" metaballs: draw soft circles, blur them, then
        // alpha-threshold so overlapping blobs merge with smooth vector edges —
        // no per-pixel sampling, so no pixelation and far cheaper.
        let blur = minDim * 0.06
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: blur))
            layer.addFilter(.alphaThreshold(min: 0.5, color: color.color))
            for b in balls { layer.fill(Path(ellipseIn: b), with: .color(color.color)) }
        }
        // Soft inner highlight: a smaller, brighter blurred pass on top.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: blur * 0.6))
            layer.addFilter(.alphaThreshold(min: 0.75, color: .white.opacity(0.22)))
            for b in balls {
                layer.fill(Path(ellipseIn: b.insetBy(dx: b.width * 0.12, dy: b.height * 0.12)), with: .color(.white))
            }
        }
    }

    private func drawHexGrid(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color))
        let hexSize = 34.0
        let hw = sqrt(3.0) * hexSize
        let hh = 1.5 * hexSize
        let w = Double(size.width), h = Double(size.height)
        var row = -1
        while Double(row) * hh < h + hh {
            var col = -1
            while Double(col) * hw < w + hw {
                let x = Double(col) * hw + (row % 2 != 0 ? hw / 2 : 0)
                let y = Double(row) * hh
                let dx = x - w / 2, dy = y - h / 2
                let dist = sqrt(dx * dx + dy * dy)
                let wave = sin(dist * 0.02 - time * 3)
                let s = hexSize * (0.6 + wave * 0.35)
                ctx.fill(hexPath(x: x, y: y, radius: s * 0.55), with: .color(hexColor(wave: wave)))
                col += 1
            }
            row += 1
        }
    }

    private func hexPath(x: Double, y: Double, radius: Double) -> Path {
        var path = Path()
        for i in 0..<6 {
            let a = Double(i) / 6 * 2 * .pi + .pi / 6
            let px = x + cos(a) * radius
            let py = y + sin(a) * radius
            if i == 0 { path.move(to: CGPoint(x: px, y: py)) } else { path.addLine(to: CGPoint(x: px, y: py)) }
        }
        path.closeSubpath()
        return path
    }

    private func hexColor(wave: Double) -> Color {
        let t = (wave + 1) / 2
        let r = accent.r + (color.r - accent.r) * t
        let g = accent.g + (color.g - accent.g) * t
        let b = accent.b + (color.b - accent.b) * t
        return Color(red: r, green: g, blue: b)
    }

    private func drawVectorGrid(ctx: GraphicsContext, size: CGSize) {
        let w = Double(size.width), h = Double(size.height)

        // Synthwave sky: deep purple → magenta band at mid-height → near-black lower half.
        ctx.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color(red: 0x1a / 255.0, green: 0.0, blue: 0x2a / 255.0), location: 0.0),
                    .init(color: Color(red: 1.0, green: 0x2a / 255.0, blue: 0x6d / 255.0), location: 0.5),
                    .init(color: Color(red: 0x05 / 255.0, green: 0.0, blue: 0x14 / 255.0), location: 0.51),
                    .init(color: Color(red: 0x05 / 255.0, green: 0.0, blue: 0x14 / 255.0), location: 1.0),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )

        // Sun disc.
        let sunRadius = min(w, h) * 0.15
        let sunCenter = CGPoint(x: w / 2, y: h * 0.5 - 40)
        ctx.fill(
            Path(ellipseIn: CGRect(x: sunCenter.x - sunRadius, y: sunCenter.y - sunRadius, width: sunRadius * 2, height: sunRadius * 2)),
            with: .color(Color(red: 1.0, green: 0xd1 / 255.0, blue: 0x66 / 255.0))
        )

        // Perspective grid.
        let horizon = h * 0.55
        let gridColor = Color(red: 0.0, green: 0xf0 / 255.0, blue: 1.0)

        for i in -24...24 {
            let fi = Double(i)
            var path = Path()
            path.move(to: CGPoint(x: w / 2, y: horizon))
            path.addLine(to: CGPoint(x: w / 2 + (fi / 24) * w * 3, y: h))
            ctx.stroke(path, with: .color(gridColor), lineWidth: 1.5)
        }

        for i in 0..<18 {
            let p = fract(Double(i) / 18 + time * 0.25)
            let y = horizon + p * p * (h - horizon)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: w, y: y))
            ctx.stroke(path, with: .color(gridColor.opacity(1 - p)), lineWidth: 1.5)
        }
    }

    private func drawParticleMesh(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hue: 0, saturation: 0, brightness: 0.02)))
        let w = Double(size.width), h = Double(size.height)
        let nodeCount = 80
        let maxD = 180.0

        var nodes: [CGPoint] = []
        nodes.reserveCapacity(nodeCount)
        for i in 0..<nodeCount {
            let fi = Double(i)
            let bx = fract(sin(fi * 127.1) * 43758.5453)
            let by = fract(sin(fi * 311.7) * 43758.5453)
            let x = bx * w + sin(time * 0.15 + fi) * (w * 0.05) + sin(time + bx * 10) * 20
            let y = by * h + cos(time * 0.15 + fi * 1.3) * (h * 0.05) + cos(time + by * 10) * 20
            nodes.append(CGPoint(x: x, y: y))
        }

        for i in 0..<nodeCount {
            for j in (i + 1)..<nodeCount {
                let dx = nodes[i].x - nodes[j].x, dy = nodes[i].y - nodes[j].y
                let d = sqrt(dx * dx + dy * dy)
                guard d < maxD else { continue }
                var path = Path()
                path.move(to: nodes[i])
                path.addLine(to: nodes[j])
                ctx.stroke(path, with: .color(accent.color.opacity((1 - d / maxD) * 0.6)), lineWidth: 1)
            }
        }

        let r: CGFloat = 2.2
        for n in nodes {
            ctx.fill(Path(ellipseIn: CGRect(x: n.x - r, y: n.y - r, width: r * 2, height: r * 2)), with: .color(color.color))
        }
    }

    // MARK: Ambient / illusion effects

    /// Multi-octave (fBm-ish) flow-field angle for Living Texture. Smooth and organic.
    private func livingFieldAngle(_ x: Double, _ y: Double) -> Double {
        (sin(x * 0.004 + time * 0.3)
            + sin(y * 0.005 - time * 0.23)
            + 0.5 * sin((x + y) * 0.003 + time * 0.4)) * .pi
    }

    /// Nebula palette: magenta → cyan → violet, cyclic. `p` wraps.
    private func nebulaColor(_ p: Double) -> Color {
        let stops: [(Double, Double, Double)] = [
            (1.00, 0.18, 0.58),   // magenta
            (0.13, 0.88, 1.00),   // cyan
            (0.54, 0.17, 0.89),   // violet
        ]
        let n = stops.count
        let x = fract(p) * Double(n)
        let i = Int(floor(x)) % n
        let j = (i + 1) % n
        let f = x - floor(x)
        let a = stops[i], b = stops[j]
        return Color(red: a.0 + (b.0 - a.0) * f,
                     green: a.1 + (b.1 - a.1) * f,
                     blue: a.2 + (b.2 - a.2) * f)
    }

    /// "Neon Life" — Conway's Life played from the pre-baked pattern (no live
    /// simulation), styled after the reference effect: a diagonal rainbow keyed
    /// to cell position that drifts over time, plus glowing trails built from a
    /// few previous baked generations so cells leave neon after-images. Loops
    /// (~2 min) and resets at the end.
    private func drawGameOfLife(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.03)))
        guard let pat = GameOfLifePattern.shared, pat.frameCount > 0 else { return }
        let cols = pat.cols, rows = pat.rows
        let fc = pat.frameCount
        let cw: CGFloat = size.width / CGFloat(cols)
        let ch: CGFloat = size.height / CGFloat(rows)

        let cfg = game ?? GameOfLifeConfig()
        let speed: Double = max(0.2, cfg.genPerSecond)
        let g: Int = Int(time * speed)

        // Diagonal rainbow keyed to position, drifting with time (neon look).
        func hueAt(_ x: Int, _ y: Int) -> Double { fract(Double(x + y) * 0.02 + time * 0.06) }

        // Glowing neon trails: draw a few previous generations, fading with age.
        let trailN = 5
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.addFilter(.blur(radius: min(cw, ch) * 0.5))
            for age in stride(from: trailN - 1, through: 0, by: -1) {
                let frame = ((g - age) % fc + fc) % fc
                let op = pow(0.55, Double(age))   // 1, 0.55, 0.30, 0.17, 0.09
                for y in 0..<rows {
                    for x in 0..<cols where pat.isLive(frame: frame, x: x, y: y) {
                        let col = Color(hue: hueAt(x, y), saturation: 1, brightness: 1)
                        let r = CGRect(x: CGFloat(x) * cw, y: CGFloat(y) * ch, width: cw, height: ch)
                        layer.fill(Path(ellipseIn: r.insetBy(dx: cw * 0.15, dy: ch * 0.15)),
                                   with: .color(col.opacity(0.5 * op)))
                    }
                }
            }
        }
        // Crisp bright current cells on top.
        let frame = g % fc
        for y in 0..<rows {
            for x in 0..<cols where pat.isLive(frame: frame, x: x, y: y) {
                let col = Color(hue: hueAt(x, y), saturation: 1, brightness: 1)
                let r = CGRect(x: CGFloat(x) * cw, y: CGFloat(y) * ch, width: cw, height: ch)
                ctx.fill(Path(roundedRect: r.insetBy(dx: cw * 0.14, dy: ch * 0.14), cornerRadius: cw * 0.25),
                         with: .color(col))
            }
        }
    }

    /// A real PCB layout (trace paths extracted from a circuit image and baked
    /// into circuit.json) progressively "traced out" along a continuous pen
    /// walk, with a glowing head, then held — looping. Trace = primary colour,
    /// board = accent tint.
    private func drawCircuit(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .color(Color(red: accent.r * 0.12, green: accent.g * 0.15, blue: accent.b * 0.12)))
        guard let pat = CircuitPattern.shared, !pat.paths.isEmpty else { return }
        let W = size.width, H = size.height
        let trace = color.color
        func P(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * W, y: p.y * H) }

        // Pixel length of each path + total (cheap to recompute; ~1.8k points).
        var pathLens: [Double] = []
        pathLens.reserveCapacity(pat.paths.count)
        var total = 0.0
        for pl in pat.paths {
            var l = 0.0
            for k in 1..<pl.count { l += Double(hypot((pl[k].x - pl[k - 1].x) * W, (pl[k].y - pl[k - 1].y) * H)) }
            pathLens.append(l); total += l
        }
        guard total > 0 else { return }

        let cycle = 20.0
        let ct = time.truncatingRemainder(dividingBy: cycle) / cycle
        let reveal = min(1.0, ct / 0.82)   // trace over 82% of the cycle, then hold
        let target = reveal * total

        // Dim full circuit so the whole board is visible while it traces in.
        var base = Path()
        for pl in pat.paths {
            base.move(to: P(pl[0]))
            for k in 1..<pl.count { base.addLine(to: P(pl[k])) }
        }
        ctx.stroke(base, with: .color(trace.opacity(0.12)), lineWidth: 1.2)

        // Bright revealed portion with glow + a head spark.
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.addFilter(.blur(radius: 1.5))
            var revealed = Path()
            var acc = 0.0
            var head = P(pat.paths[0][0])
            outer: for (pi, pl) in pat.paths.enumerated() {
                let plen = pathLens[pi]
                if acc + plen <= target {
                    revealed.move(to: P(pl[0]))
                    for k in 1..<pl.count { revealed.addLine(to: P(pl[k])) }
                    acc += plen
                    head = P(pl[pl.count - 1])
                } else {
                    revealed.move(to: P(pl[0]))
                    var a2 = acc
                    for k in 1..<pl.count {
                        let a = P(pl[k - 1]), b = P(pl[k])
                        let seg = Double(hypot(b.x - a.x, b.y - a.y))
                        if a2 + seg <= target {
                            revealed.addLine(to: b); a2 += seg; head = b
                        } else {
                            let t = seg > 0 ? CGFloat((target - a2) / seg) : 0
                            let hp = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                            revealed.addLine(to: hp); head = hp
                            break
                        }
                    }
                    break outer
                }
            }
            layer.stroke(revealed, with: .color(trace.opacity(0.95)),
                         style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            let hr: CGFloat = 5
            layer.fill(Path(ellipseIn: CGRect(x: head.x - hr, y: head.y - hr, width: hr * 2, height: hr * 2)),
                       with: .color(.white.opacity(0.95)))
        }
    }

    // MARK: - 3D effects (software projection)

    /// Shaded parametric surface: build an (nu×nv) quad mesh from `pt`, rotate,
    /// perspective-project, depth-sort (painter's), and fill each quad with a
    /// lambert-shaded, hued colour.
    private func render3DSurface(_ ctx: GraphicsContext, _ size: CGSize, nu: Int, nv: Int,
                                 ax: Double, ay: Double, scaleF: Double,
                                 pt: (Int, Int) -> (Vec3, Double)) {
        let scale = Double(min(size.width, size.height)) * scaleF
        let camDist = 5.0
        var rp = [[Vec3]](repeating: [Vec3](repeating: Vec3(), count: nv + 1), count: nu + 1)
        var hue = [[Double]](repeating: [Double](repeating: 0, count: nv + 1), count: nu + 1)
        for iu in 0...nu {
            for iv in 0...nv {
                let (p, h) = pt(iu, iv)
                rp[iu][iv] = rot3(p, ax, ay); hue[iu][iv] = h
            }
        }
        func proj(_ p: Vec3) -> CGPoint {
            let f = camDist / max(p.z + camDist, 0.1)
            return CGPoint(x: size.width / 2 + p.x * f * scale, y: size.height / 2 + p.y * f * scale)
        }
        let L = normalize3(Vec3(x: -0.35, y: -0.5, z: -0.8))
        struct Q { var pts: [CGPoint]; var depth: Double; var shade: Double; var hue: Double }
        var quads: [Q] = []
        quads.reserveCapacity(nu * nv)
        for iu in 0..<nu {
            for iv in 0..<nv {
                let a = rp[iu][iv], b = rp[iu + 1][iv], c = rp[iu + 1][iv + 1], d = rp[iu][iv + 1]
                let e1 = Vec3(x: b.x - a.x, y: b.y - a.y, z: b.z - a.z)
                let e2 = Vec3(x: d.x - a.x, y: d.y - a.y, z: d.z - a.z)
                var n = normalize3(Vec3(x: e1.y * e2.z - e1.z * e2.y,
                                        y: e1.z * e2.x - e1.x * e2.z,
                                        z: e1.x * e2.y - e1.y * e2.x))
                if n.z > 0 { n = Vec3(x: -n.x, y: -n.y, z: -n.z) }   // orient toward camera
                let lam = max(0.0, n.x * L.x + n.y * L.y + n.z * L.z)
                let depth = (a.z + b.z + c.z + d.z) / 4
                quads.append(Q(pts: [proj(a), proj(b), proj(c), proj(d)],
                               depth: depth, shade: 0.18 + 0.82 * lam, hue: hue[iu][iv]))
            }
        }
        quads.sort { $0.depth > $1.depth }   // far first (painter's)
        for q in quads {
            var p = Path(); p.move(to: q.pts[0])
            for i in 1..<4 { p.addLine(to: q.pts[i]) }
            p.closeSubpath()
            let col = Color(hue: q.hue, saturation: 0.85, brightness: q.shade)
            ctx.fill(p, with: .color(col))
            ctx.stroke(p, with: .color(col), lineWidth: 0.5)   // seal seams between quads
        }
    }

    private func drawTorus3D(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        let sp = three?.speed ?? 1.0
        let R = 1.4, r = 0.52, nu = 64, nv = 26
        render3DSurface(ctx, size, nu: nu, nv: nv, ax: time * 0.5 * sp, ay: time * 0.7 * sp, scaleF: 0.13) { iu, iv in
            let u = Double(iu) / Double(nu) * 2 * .pi
            let v = Double(iv) / Double(nv) * 2 * .pi
            return (Vec3(x: (R + r * cos(v)) * cos(u), y: (R + r * cos(v)) * sin(u), z: r * sin(v)),
                    fract(u / (2 * .pi) + time * 0.05))
        }
    }

    private func drawSphere3D(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        let sp = three?.speed ?? 1.0
        let nu = 52, nv = 30
        render3DSurface(ctx, size, nu: nu, nv: nv, ax: time * 0.3 * sp, ay: time * 0.6 * sp, scaleF: 0.16) { iu, iv in
            let u = Double(iu) / Double(nu) * 2 * .pi
            let v = Double(iv) / Double(nv) * .pi
            let rad = 1.5 + 0.18 * sin(v * 6 + time * 2 * sp)   // travelling ripple
            return (Vec3(x: rad * sin(v) * cos(u), y: rad * cos(v), z: rad * sin(v) * sin(u)),
                    fract(v / .pi + time * 0.04))
        }
    }

    private func drawPointCloud3D(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        let n = 1400
        let scale = Double(min(size.width, size.height)) * 0.30
        let camDist = 5.0
        let spd = three?.speed ?? 1.0
        let rainbow = three?.rainbow ?? true
        var pts: [(CGPoint, Double, Double)] = []
        pts.reserveCapacity(n)
        for i in 0..<n {
            let th = Double(hash01(i, 1)) * 2 * .pi
            let ph = acos(2 * Double(hash01(i, 2)) - 1)
            let rr = 1.4 + 0.5 * sin(time * 0.6 * spd + Double(i) * 0.05)   // pulsing = movement
            var p = Vec3(x: rr * sin(ph) * cos(th), y: rr * sin(ph) * sin(th), z: rr * cos(ph))
            p = rot3(p, time * 0.22 * spd, time * 0.4 * spd)
            let f = camDist / max(p.z + camDist, 0.1)
            let sp = CGPoint(x: size.width / 2 + p.x * f * scale, y: size.height / 2 + p.y * f * scale)
            pts.append((sp, f, fract(0.6 + Double(i) * 0.0007 + time * 0.03 * spd)))
        }
        pts.sort { $0.1 < $1.1 }
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            for (sp, f, hue) in pts {
                let rad = max(0.4, (f - 0.55) * 3.2)
                let col = rainbow ? Color(hue: hue, saturation: 0.8, brightness: 1) : color.color
                layer.fill(Path(ellipseIn: CGRect(x: sp.x - rad, y: sp.y - rad, width: rad * 2, height: rad * 2)),
                           with: .color(col.opacity(min(1, f * 0.85))))
            }
        }
    }

    // MARK: - Geometric morphing effects

    /// Rotating, mirrored kaleidoscope wedges whose motifs continuously morph.
    private func drawInfiniteKaleidoscope(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let segments = 10
        let wedge = 2 * Double.pi / Double(segments)
        let maxR = Double(min(size.width, size.height)) / 2
        let spin = time * 0.25
        let n = 10
        for seg in 0..<segments {
            ctx.drawLayer { layer in
                layer.translateBy(x: center.x, y: center.y)
                layer.rotate(by: .radians(Double(seg) * wedge + spin))
                if seg % 2 == 1 { layer.scaleBy(x: -1, y: 1) }
                layer.blendMode = .plusLighter
                for i in 0..<n {
                    let fi = Double(i)
                    let ang: Double = 0.1 + wedge * (0.15 + 0.7 * fi / Double(n)) + sin(time * 0.6 + fi) * 0.1
                    let r: Double = maxR * (0.1 + 0.85 * fi / Double(n)) * (0.7 + 0.3 * sin(time * 0.5 + fi * 1.3))
                    let s = CGFloat(maxR * (0.04 + 0.06 * (0.5 + 0.5 * sin(time + fi * 2))))
                    let hue = fract(fi / Double(n) + time * 0.05)
                    let p = CGPoint(x: cos(ang) * r, y: sin(ang) * r)
                    let col = Color(hue: hue, saturation: 0.95, brightness: 1)
                    var line = Path(); line.move(to: .zero); line.addLine(to: p)
                    layer.stroke(line, with: .color(col.opacity(0.22)), lineWidth: 1.5)
                    layer.fill(Path(ellipseIn: CGRect(x: p.x - s, y: p.y - s, width: s * 2, height: s * 2)),
                               with: .color(col.opacity(0.8)))
                }
            }
        }
    }

    /// Radial rings of petals that grow out from the centre, multiply (split),
    /// and fade/reform at the rim.
    private func drawMandala(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxR = Double(min(size.width, size.height)) / 2
        let rings = 6
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            for ringIdx in 0..<rings {
                let phase = fract(Double(ringIdx) / Double(rings) + time * 0.12)
                let r = phase * maxR
                let alpha = sin(phase * Double.pi)                 // 0 at centre & rim
                let petals = 6 + Int(phase * 18)                   // more petals as it expands
                let hue = fract(Double(ringIdx) / Double(rings) + time * 0.1)
                let col = Color(hue: hue, saturation: 0.9, brightness: 1)
                for p in 0..<petals {
                    let a: Double = Double(p) / Double(petals) * 2 * .pi + time * 0.2
                    let px = center.x + CGFloat(cos(a) * r)
                    let py = center.y + CGFloat(sin(a) * r)
                    let s = CGFloat(maxR * 0.03 * (0.6 + 0.8 * alpha))
                    layer.fill(Path(ellipseIn: CGRect(x: px - s, y: py - s, width: s * 2, height: s * 2)),
                               with: .color(col.opacity(0.7 * alpha)))
                }
            }
        }
    }

    /// Radius of a regular polygon (apothem 1) at angle `theta` for a
    /// continuous side count — morphs smoothly triangle→hexagon→circle.
    private func polyRadius(_ theta: Double, sides: Double) -> Double {
        let a = 2 * Double.pi / max(sides, 3)
        var m = theta.truncatingRemainder(dividingBy: a)
        if m < 0 { m += a }
        return cos(a / 2) / cos(m - a / 2)
    }

    /// Concentric outlines whose side count morphs between triangle, hexagon,
    /// and circle, rotating in alternating directions.
    private func drawSacredGeometry(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxR = Double(min(size.width, size.height)) / 2
        let sides = 3 + 4.5 * (1 + sin(time * 0.4))    // 3 … 12
        let layers = 5
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            for li in 0..<layers {
                let rr: Double = maxR * (0.2 + 0.16 * Double(li))
                let rot: Double = time * 0.15 * (li % 2 == 0 ? 1 : -1) + Double(li) * 0.3
                let hue = fract(Double(li) / Double(layers) + time * 0.06)
                let col = Color(hue: hue, saturation: 0.9, brightness: 1)
                var path = Path()
                let steps = 140
                for s in 0...steps {
                    let th: Double = Double(s) / Double(steps) * 2 * .pi
                    let r: Double = rr * polyRadius(th - rot, sides: sides)
                    let pt = CGPoint(x: center.x + CGFloat(cos(th) * r), y: center.y + CGFloat(sin(th) * r))
                    if s == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                layer.stroke(path, with: .color(col.opacity(0.85)), lineWidth: 2.5)
            }
        }
    }

    /// Nested rotating polygons scaled log-periodically so it appears to zoom
    /// into itself forever (self-similar).
    private func drawFractalZoom(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxR = Double(min(size.width, size.height)) / 2
        let factor = 1.7
        let zoom = pow(factor, fract(time * 0.15))     // cycles in [1, factor)
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            for k in 0..<16 {
                let scale = zoom * pow(factor, Double(k) - 7)
                let r = maxR * 1.5 * scale
                if r < 2 || r > maxR * 3 { continue }
                let rot = Double(k) * 0.5 + time * 0.12
                let hue = fract(Double(k) * 0.08 + time * 0.05)
                let col = Color(hue: hue, saturation: 0.9, brightness: 1)
                let fadeIn = min(1.0, r / (maxR * 0.2))
                let fadeOut = min(1.0, (maxR * 3 - r) / (maxR * 1.2))
                let alpha = max(0.0, min(fadeIn, fadeOut))
                let path = polygonPath(center: center, radius: CGFloat(r), sides: 6, rotation: rot)
                layer.stroke(path, with: .color(col.opacity(0.9 * alpha)),
                             style: StrokeStyle(lineWidth: max(1, CGFloat(2 * scale)), lineJoin: .round))
            }
        }
    }

    /// A grid of squares that rotate and pulse in a travelling wave, coloured by
    /// position + time — a tessellation that smoothly morphs shape and colour.
    private func drawTessellation(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.03)))
        let cell = max(28.0, Double(min(size.width, size.height)) / 12)
        let cols = Int(Double(size.width) / cell) + 1
        let rows = Int(Double(size.height) / cell) + 1
        for gy in 0..<rows {
            for gx in 0..<cols {
                let cx = (Double(gx) + 0.5) * cell
                let cy = (Double(gy) + 0.5) * cell
                let wave = Double(gx + gy) * 0.5
                let rot = time * 0.6 + wave
                let scale = 0.45 + 0.4 * (0.5 + 0.5 * sin(time * 1.2 + wave))
                let hue = fract(Double(gx + gy) * 0.05 + time * 0.08)
                let col = Color(hue: hue, saturation: 0.85, brightness: 1)
                let half = CGFloat(cell * 0.5 * scale)
                ctx.drawLayer { layer in
                    layer.translateBy(x: CGFloat(cx), y: CGFloat(cy))
                    layer.rotate(by: .radians(rot))
                    layer.fill(Path(CGRect(x: -half, y: -half, width: half * 2, height: half * 2)),
                               with: .color(col.opacity(0.85)))
                }
            }
        }
    }

    /// Flowing plasma: rainbow radial-gradient blobs drifting on Lissajous
    /// paths, blended additively into a smooth, colourful field.
    private func drawFlowingPlasma(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
        let w = Double(size.width), h = Double(size.height)
        let minDim = min(w, h)
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            let n = 6
            for i in 0..<n {
                let fi = Double(i)
                let hue: Double = fract(fi / Double(n) + time * 0.05)
                let cx: Double = w * 0.5 + cos(time * (0.3 + fi * 0.07) + fi * 1.3) * w * 0.42
                let cy: Double = h * 0.5 + sin(time * (0.25 + fi * 0.09) + fi * 2.1) * h * 0.42
                let r: Double = minDim * (0.5 + 0.2 * sin(time * 0.4 + fi))
                let col = Color(hue: hue, saturation: 0.9, brightness: 1)
                layer.fill(Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)),
                           with: .radialGradient(Gradient(colors: [col.opacity(0.6), .clear]),
                                                 center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: r))
            }
        }
    }

    /// Drifting nebula: soft coloured clouds (primary/accent) slowly drifting,
    /// with a field of twinkling stars.
    private func drawDriftingNebula(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .color(Color(red: 0.02, green: 0.02, blue: 0.06)))
        let w = Double(size.width), h = Double(size.height)
        let minDim = min(w, h)
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.addFilter(.blur(radius: minDim * 0.05))
            let n = 14
            for i in 0..<n {
                let fi = Double(i)
                let drift: Double = time * 0.015 * (0.5 + Double(hash01(i, 7)))
                let px: Double = fract(Double(hash01(i, 1)) + drift) * w
                let py: Double = (Double(hash01(i, 2)) * 0.8 + 0.1) * h + sin(time * 0.1 + fi) * h * 0.03
                let r: Double = minDim * (0.16 + 0.26 * Double(hash01(i, 3)))
                let col = i % 2 == 0 ? color.color : accent.color
                layer.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)),
                           with: .radialGradient(Gradient(colors: [col.opacity(0.28), .clear]),
                                                 center: CGPoint(x: px, y: py), startRadius: 0, endRadius: r))
            }
        }
        // Stars.
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            for i in 0..<90 {
                let sx = Double(hash01(i, 11)) * w
                let sy = Double(hash01(i, 13)) * h
                let tw = 0.4 + 0.6 * (0.5 + 0.5 * sin(time * 2.0 + Double(i) * 1.7))
                let sr = 0.6 + 1.4 * Double(hash01(i, 17))
                layer.fill(Path(ellipseIn: CGRect(x: sx - sr, y: sy - sr, width: sr * 2, height: sr * 2)),
                           with: .color(.white.opacity(tw)))
            }
        }
    }

    /// Cheap pseudo-Perlin flow angle at a scaled coordinate + time.
    private func flowAngle(_ x: Double, _ y: Double, _ t: Double) -> Double {
        let n = sin(x * 1.7 + t) + sin(y * 1.3 - t * 0.8)
            + sin((x + y) * 0.9 + t * 0.5) + sin((x - y) * 1.1 - t * 0.3)
        return n * 0.9
    }

    /// Perlin-style flow field: a grid of short streaks oriented by an animated
    /// noise field, coloured primary→accent along the field angle.
    private func drawPerlinFlow(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.04)))
        let spacing: CGFloat = 26
        let len: CGFloat = spacing * 0.7
        let t = time * 0.25
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            var gy = spacing / 2
            while gy < size.height {
                var gx = spacing / 2
                while gx < size.width {
                    let ang = flowAngle(Double(gx) * 0.012, Double(gy) * 0.012, t)
                    let dx = CGFloat(cos(ang)) * len, dy = CGFloat(sin(ang)) * len
                    let a = CGPoint(x: gx - dx / 2, y: gy - dy / 2)
                    let b = CGPoint(x: gx + dx / 2, y: gy + dy / 2)
                    var streak = Path(); streak.move(to: a); streak.addLine(to: b)
                    layer.stroke(streak, with: .linearGradient(
                        Gradient(colors: [color.color.opacity(0.15), accent.color.opacity(0.95)]),
                        startPoint: a, endPoint: b), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    // bright head
                    layer.fill(Path(ellipseIn: CGRect(x: b.x - 1.6, y: b.y - 1.6, width: 3.2, height: 3.2)),
                               with: .color(accent.color.opacity(0.9)))
                    gx += spacing
                }
                gy += spacing
            }
        }
    }

    private func drawLivingTexture(ctx: GraphicsContext, size: CGSize) {
        let w = Double(size.width), h = Double(size.height)
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .color(Color(red: 0.03, green: 0.0, blue: 0.06)))

        let ribbonCount = 90
        let steps = 40
        let stepLen = 5.0

        var ribbons: [(path: Path, color: Color)] = []
        ribbons.reserveCapacity(ribbonCount)
        for k in 0..<ribbonCount {
            let fk = Double(k)
            var x = fract(sin(fk * 12.9898) * 43758.5453) * w
            var y = fract(sin(fk * 78.233) * 43758.5453) * h
            let colorPhase = fract(sin(fk * 45.164) * 43758.5453)
            // Advance the seed along the field so ribbons drift and recycle (stateless).
            let warm = Int(fract(time * 0.05 + colorPhase) * 40)
            for _ in 0..<warm {
                let ang = livingFieldAngle(x, y)
                x += cos(ang) * stepLen; y += sin(ang) * stepLen
                if x < 0 { x += w } else if x > w { x -= w }
                if y < 0 { y += h } else if y > h { y -= h }
            }
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            for _ in 0..<steps {
                let ang = livingFieldAngle(x, y)
                x += cos(ang) * stepLen; y += sin(ang) * stepLen
                path.addLine(to: CGPoint(x: x, y: y))
            }
            ribbons.append((path, nebulaColor(colorPhase + time * 0.03)))
        }

        // Soft glow pass: fat, blurred, additive.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.blendMode = .plusLighter
            for r in ribbons {
                layer.stroke(r.path, with: .color(r.color.opacity(0.35)),
                             style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            }
        }
        // Bright core pass: thin, additive.
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            for r in ribbons {
                layer.stroke(r.path, with: .color(r.color.opacity(0.9)),
                             style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
    private func polygonPath(center: CGPoint, radius: CGFloat, sides: Int, rotation: Double) -> Path {
        var path = Path()
        for i in 0...sides {
            let angle = rotation + Double(i) / Double(sides) * 2 * .pi
            let pt = point(center, angle, Double(radius))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        return path
    }

    private func unitPoint(_ radians: Double) -> UnitPoint {
        UnitPoint(x: 0.5 + 0.5 * cos(radians), y: 0.5 + 0.5 * sin(radians))
    }

    private func point(_ c: CGPoint, _ angle: Double, _ radius: Double) -> CGPoint {
        CGPoint(x: c.x + CGFloat(cos(angle) * radius), y: c.y + CGFloat(sin(angle) * radius))
    }

    private func fract(_ v: Double) -> Double { v - floor(v) }

    private func animatedCenter(_ t: Double, _ phase: Double) -> UnitPoint {
        UnitPoint(x: 0.5 + 0.3 * cos(t * 0.8 + phase), y: 0.5 + 0.3 * sin(t * 0.6 + phase))
    }

    private func hash01(_ i: Int, _ salt: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return CGFloat(v - floor(v))
    }
}

/// Wraps an audio-reactive effect: retains the mic only while visible AND the
/// toggle is on, and hands the current levels to its content. When off/denied,
/// passes `.silent` so the effect renders its idle (time-driven) path.
///
/// The injected `audio` defaults to the shared microphone manager; the offscreen
/// verify script substitutes a scripted `AudioLevelsProviding`, mirroring
/// `ParticleSwarmView`.
private struct AudioReactiveEffect<Content: View>: View {
    let active: Bool
    var audio: AudioLevelsProviding = AudioInputManager.shared
    @ViewBuilder let content: (AudioLevels) -> Content

    // Tracks whether THIS wrapper instance currently holds a mic retain, held as
    // a reference type (like `EqualizerAudioState`/`SwarmRenderState`) so the
    // lifecycle closures reconcile the same token rather than a captured copy.
    @State private var retainToken = AudioRetainToken()

    /// Keeps the shared mic retain in sync with `active`: retain once when the
    /// effect becomes active, release once when it stops — exactly balanced
    /// across any ordering of mount/unmount and toggle.
    private func reconcile() {
        if active && !retainToken.retained {
            audio.retain()
            retainToken.retained = true
        } else if !active && retainToken.retained {
            audio.release()
            retainToken.retained = false
        }
    }

    var body: some View {
        content((active && !audio.isDenied) ? audio.currentLevels : .silent)
            .onAppear { reconcile() }
            .onChange(of: active) { reconcile() }
            .onDisappear {
                if retainToken.retained {
                    audio.release()
                    retainToken.retained = false
                }
            }
    }
}

/// Reference-type retain flag for `AudioReactiveEffect`, held in `@State` so the
/// lifecycle closures mutate a stable instance instead of a captured value.
private final class AudioRetainToken {
    var retained = false
}

/// The Equalizer effect. When `levels.spectrum` is non-empty (audio active) it
/// drives 16 bars from the FFT bins with slow-falling peak-hold caps; otherwise
/// it renders the original time-driven randomized bars, unchanged. Peak-hold
/// state lives in a reference-type object so it survives `Canvas` redraws, like
/// `SwarmRenderState`.
private struct EqualizerView: View {
    let color: RGBAColor
    let accent: RGBAColor
    let time: Double
    let levels: AudioLevels

    @State private var state = EqualizerAudioState()

    private let count = 16

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            let gap: CGFloat = 5
            let barWidth = (size.width - gap * CGFloat(count + 1)) / CGFloat(count)
            let audioActive = !levels.spectrum.isEmpty

            // dt from the shared clock, for peak-hold decay (audio path only).
            let dt: Double = state.lastTime.map { max(0, time - $0) } ?? (1.0 / 60)
            if audioActive { state.lastTime = time }

            // Shared kick that all bars react to, like a beat (idle path only).
            let beat = pow(max(0, sin(time * 3.0)), 4)
            for i in 0..<count {
                let level: Double
                if audioActive {
                    let bin = i < levels.spectrum.count ? levels.spectrum[i] : 0
                    level = min(1.0, max(0.04, bin))
                } else {
                    // Layer three per-bar random frequencies so bars bounce
                    // unpredictably instead of marching in a visible wave.
                    let s1: Double = Double(eqHash01(i, 7))
                    let s2: Double = Double(eqHash01(i, 17))
                    let s3: Double = Double(eqHash01(i, 41))
                    let a: Double = sin(time * (2.3 + s1 * 4.0) + s1 * 6.283)
                    let b: Double = sin(time * (5.1 + s2 * 6.0) + s2 * 6.283)
                    let c: Double = sin(time * (9.7 + s3 * 8.0) + s3 * 6.283)
                    let mix: Double = 0.5 + 0.5 * (0.6 * a + 0.3 * b + 0.1 * c)
                    let kick: Double = 0.30 * beat * (0.4 + 0.6 * s2)
                    level = min(1.0, max(0.05, 0.12 + 0.66 * mix + kick))
                }
                let h = size.height * CGFloat(level)
                let x = gap + CGFloat(i) * (barWidth + gap)
                let rect = CGRect(x: x, y: size.height - h, width: barWidth, height: h)
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [color.color, accent.color]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                )
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: shading)

                // Slow-falling peak-hold cap, drawn as a thin line (audio only).
                if audioActive {
                    let peak = max(level, state.peaks[i] - 0.9 * dt)
                    state.peaks[i] = peak
                    let py = size.height - size.height * CGFloat(peak)
                    var cap = Path()
                    cap.move(to: CGPoint(x: x, y: py))
                    cap.addLine(to: CGPoint(x: x + barWidth, y: py))
                    ctx.stroke(cap, with: .color(color.color.opacity(0.9)), lineWidth: 2)
                }
            }
        }
    }

    private func eqHash01(_ i: Int, _ salt: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return CGFloat(v - floor(v))
    }
}

/// Per-view peak-hold state for `EqualizerView`, held as a reference type so it
/// persists across `Canvas` redraws without value invalidation.
final class EqualizerAudioState {
    var peaks = [Double](repeating: 0, count: 16)
    var lastTime: Double?
}

/// The Strobe effect. Idle (no spectrum): the original `Int(time*3) % 2` flash
/// between `color` and `accent`. Audio active: rests on `accent` and flashes to
/// `color` for a short decay window each time `levels.beatCount` increases, with
/// flash opacity scaled by `levels.beatStrength`.
private struct StrobeView: View {
    let color: RGBAColor
    let accent: RGBAColor
    let time: Double
    let levels: AudioLevels

    @State private var state = StrobeAudioState()

    /// Seconds a beat flash takes to fade out.
    private let flashDecay = 0.14

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            if levels.spectrum.isEmpty {
                // Idle: byte-for-byte the original alternating flash.
                let c = Int(time * 3) % 2 == 0 ? color.color : accent.color
                ctx.fill(Path(rect), with: .color(c))
                return
            }
            // Audio: latch a new flash whenever the beat count advances.
            if levels.beatCount > state.lastBeatCount {
                state.lastBeatCount = levels.beatCount
                state.flashTime = time
                state.flashStrength = levels.beatStrength
            }
            var intensity = 0.0
            if let ft = state.flashTime {
                let e = time - ft
                if e >= 0, e < flashDecay {
                    intensity = (1 - e / flashDecay) * state.flashStrength
                }
            }
            ctx.fill(Path(rect), with: .color(accent.color))
            if intensity > 0 {
                ctx.fill(Path(rect), with: .color(color.color.opacity(min(1, intensity))))
            }
        }
    }
}

/// Per-view flash state for `StrobeView`, a reference type so the last-seen beat
/// and flash timing survive `Canvas` redraws.
final class StrobeAudioState {
    var lastBeatCount = 0
    var flashTime: Double?
    var flashStrength = 0.0
}

/// Clips media to a polygon (given as local, box-relative points) or to an
/// ellipse inscribed in the media's bounding box.
private struct SurfaceMask: Shape {
    let localPoints: [CGPoint]
    let isEllipse: Bool

    func path(in rect: CGRect) -> Path {
        if isEllipse { return Path(ellipseIn: rect) }
        var p = Path()
        guard let first = localPoints.first else { return p }
        p.move(to: first)
        for pt in localPoints.dropFirst() { p.addLine(to: pt) }
        p.closeSubpath()
        return p
    }
}

/// A still image loaded from disk, scaled to fill the surface.
private struct ImageContent: View {
    let url: URL

    var body: some View {
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color(white: 0.2)
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.white)
            }
        }
    }
}

/// One detected edge sample in normalized coords (origin top-left, y down),
/// with edge brightness.
private struct LaserEdgePoint {
    let x: CGFloat
    let y: CGFloat
    let b: CGFloat
}

/// Runs `CIEdges` on the source image once (off the main thread) and caches the
/// resulting normalized edge points. The animated `LaserTraceContent` only reads
/// this cached point set per frame — no per-frame image work.
private final class LaserTraceModel: ObservableObject {
    @Published var points: [LaserEdgePoint] = []
    private var loadedURL: URL?

    // Process-wide cache so edges survive view churn / repeated selection.
    private static var cache: [URL: [LaserEdgePoint]] = [:]
    private static let cacheQueue = DispatchQueue(label: "lumora.laserTrace.cache")

    func load(_ url: URL) {
        guard url != loadedURL else { return }
        loadedURL = url
        if let cached = Self.cacheQueue.sync(execute: { Self.cache[url] }) {
            points = cached
            return
        }
        points = []
        DispatchQueue.global(qos: .userInitiated).async {
            let pts = Self.extractEdges(from: url)
            Self.cacheQueue.sync { Self.cache[url] = pts }
            DispatchQueue.main.async {
                if self.loadedURL == url { self.points = pts }
            }
        }
    }

    private static func extractEdges(from url: URL) -> [LaserEdgePoint] {
        guard let nsImage = NSImage(contentsOf: url),
              let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return [] }

        // GPU edge-detect, once.
        let ci = CIImage(cgImage: cg)
        let edges = ci.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 6.0])
        let ciContext = CIContext(options: nil)
        guard let edgeCG = ciContext.createCGImage(edges, from: ci.extent) else { return [] }

        // Downsample into a bitmap we can read pixel-by-pixel. The context CTM is
        // flipped so buffer row 0 is the TOP of the image (top-left origin).
        let targetW = 480
        let scale = Double(targetW) / Double(max(edgeCG.width, 1))
        let w = targetW
        let h = max(1, Int(Double(edgeCG.height) * scale))
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let bmp = CGContext(
            data: &buffer, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [] }
        bmp.translateBy(x: 0, y: CGFloat(h))
        bmp.scaleBy(x: 1, y: -1)
        bmp.draw(edgeCG, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Collect bright pixels; stride up if edges are very dense so the point
        // count stays bounded.
        let threshold = 0.16
        let maxPoints = 6000
        var stride = 1
        while true {
            var pts: [LaserEdgePoint] = []
            pts.reserveCapacity(maxPoints)
            var overflow = false
            var yy = 0
            rows: while yy < h {
                var xx = 0
                while xx < w {
                    let i = (yy * w + xx) * 4
                    let lum = (0.299 * Double(buffer[i]) + 0.587 * Double(buffer[i + 1]) + 0.114 * Double(buffer[i + 2])) / 255.0
                    if lum > threshold {
                        pts.append(LaserEdgePoint(
                            x: CGFloat(xx) / CGFloat(w - 1),
                            y: 1 - CGFloat(yy) / CGFloat(max(h - 1, 1)),   // 0 = top (buffer rows are bottom-up)
                            b: CGFloat(min(1.0, lum))))
                        if pts.count > maxPoints { overflow = true; break rows }
                    }
                    xx += stride
                }
                yy += stride
            }
            if overflow { stride += 1; continue }
            return pts
        }
    }
}

/// Laser edge-trace: a bright bar sweeps bottom→top; edges light up in the laser
/// color as it passes and persist, forming the full outline, which then holds and
/// fades before the sweep repeats. A `Canvas` so it warps with the surface.
private struct LaserTraceContent: View {
    let url: URL
    let color: RGBAColor
    let speed: Double
    let time: Double

    @StateObject private var model = LaserTraceModel()

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.02)))
            let pts = model.points
            guard !pts.isEmpty else { return }

            let sweepDur = 6.0 / max(speed, 0.02), holdDur = 1.5, fadeDur = 1.5
            let period = sweepDur + holdDur + fadeDur
            let localT = time.truncatingRemainder(dividingBy: period)
            let sweepP = min(localT / sweepDur, 1)
            let scan = CGFloat(1 - sweepP)                 // 1 (bottom) → 0 (top)
            ctx.opacity = localT < sweepDur + holdDur
                ? 1
                : max(0, 1 - (localT - (sweepDur + holdDur)) / fadeDur)

            let laser = color.color
            let w = size.width, h = size.height
            let r: CGFloat = 1.1
            let hotBand: CGFloat = 0.02

            var traced = Path()
            var hot = Path()
            for p in pts where p.y >= scan {                // already passed by the bar
                let rect = CGRect(x: p.x * w - r, y: p.y * h - r, width: 2 * r, height: 2 * r)
                if p.y - scan < hotBand { hot.addEllipse(in: rect) } else { traced.addEllipse(in: rect) }
            }

            // Traced edges: soft glow + solid core.
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.fill(traced, with: .color(laser.opacity(0.55)))
            }
            ctx.fill(traced, with: .color(laser))

            // Edges under the beam right now: white-hot, stronger glow.
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 4))
                layer.fill(hot, with: .color(.white.opacity(0.9)))
            }
            ctx.fill(hot, with: .color(.white))

            // The sweeping laser bar.
            if sweepP < 1 {
                let y = scan * h
                var bar = Path()
                bar.move(to: CGPoint(x: 0, y: y))
                bar.addLine(to: CGPoint(x: w, y: y))
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 6))
                    layer.stroke(bar, with: .color(laser.opacity(0.8)), lineWidth: 4)
                }
                ctx.stroke(bar, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
            }
        }
        .task(id: url) { model.load(url) }
    }
}

/// One detected contour as an ordered, closed polyline in normalized coords
/// (origin top-left), with cumulative arc length for pen-position lookup.
private struct ContourPolyline {
    let points: [CGPoint]
    let lengths: [CGFloat]        // lengths[0] == 0, lengths[i] = arc length to points[i]
    var total: CGFloat { lengths.last ?? 0 }
}

/// Extracts image contours once (via Vision `VNDetectContoursRequest`), ordered
/// bottom→top, and caches them. `ContourTraceContent` animates a single pen along
/// the cached polylines — no per-frame vision work.
private final class ContourTraceModel: ObservableObject {
    @Published var contours: [ContourPolyline] = []
    @Published var totalLength: CGFloat = 0
    /// Reference-date timestamp when the current contours became available, so
    /// the sweep starts from load (needed for the "always on" one-shot).
    @Published var readyAt: Double = 0
    private var loadedURLs: [URL] = []

    private static var cache: [URL: [ContourPolyline]] = [:]
    private static let cacheQueue = DispatchQueue(label: "lumora.contourTrace.cache")

    /// Load one or more images and concatenate their ordered contour walks in
    /// array order, so the pen traces image 1 fully, then image 2, etc. — each
    /// overlaying the previous.
    func load(_ urls: [URL]) {
        guard urls != loadedURLs else { return }
        loadedURLs = urls
        contours = []; totalLength = 0
        let work = urls
        DispatchQueue.global(qos: .userInitiated).async {
            var all: [ContourPolyline] = []
            for url in work {
                let cached = Self.cacheQueue.sync { Self.cache[url] }
                let c = cached ?? Self.extractContours(from: url)
                if cached == nil { Self.cacheQueue.sync { Self.cache[url] = c } }
                all.append(contentsOf: c)   // per-image walk, kept in image order
            }
            DispatchQueue.main.async {
                if self.loadedURLs == work { self.apply(all) }
            }
        }
    }

    private func apply(_ c: [ContourPolyline]) {
        contours = c
        totalLength = c.reduce(0) { $0 + $1.total }
        readyAt = Date.timeIntervalSinceReferenceDate
    }

    private static func extractContours(from url: URL) -> [ContourPolyline] {
        guard let nsImage = NSImage(contentsOf: url),
              let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return [] }

        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 2.0
        request.detectsDarkOnLight = true
        request.maximumImageDimension = 512

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        guard let obs = request.results?.first as? VNContoursObservation else { return [] }

        var polylines: [ContourPolyline] = []
        for i in 0..<obs.contourCount {
            guard let contour = try? obs.contour(at: i) else { continue }
            // Simplify each contour to a polygon: sheds pixel-noise jitter and
            // tightens the traced line.
            let simplified = (try? contour.polygonApproximation(epsilon: 0.003)) ?? contour
            let raw = simplified.normalizedPoints            // origin bottom-left, 0…1
            if raw.count < 2 { continue }
            var pts: [CGPoint] = []
            pts.reserveCapacity(raw.count + 1)
            for p in raw { pts.append(CGPoint(x: CGFloat(p.x), y: 1 - CGFloat(p.y))) }  // flip y → top-left
            if let first = pts.first { pts.append(first) }   // close the loop

            var lens: [CGFloat] = [0]
            var acc: CGFloat = 0
            for k in 1..<pts.count {
                acc += hypot(pts[k].x - pts[k - 1].x, pts[k].y - pts[k - 1].y)
                lens.append(acc)
            }
            if acc < 0.03 { continue }                       // drop small / noise contours
            polylines.append(ContourPolyline(points: pts, lengths: lens))
        }
        return orderAsWalk(dedupe(polylines))
    }

    /// Drops near-duplicate contours — e.g. the inner + outer boundary Vision
    /// returns for a thin shape, which otherwise trace as doubled parallel lines.
    private static func dedupe(_ contours: [ContourPolyline]) -> [ContourPolyline] {
        func centroid(_ c: ContourPolyline) -> CGPoint {
            var sx: CGFloat = 0, sy: CGFloat = 0
            for p in c.points { sx += p.x; sy += p.y }
            let n = CGFloat(max(c.points.count, 1))
            return CGPoint(x: sx / n, y: sy / n)
        }
        var kept: [ContourPolyline] = []
        var cents: [CGPoint] = []
        for c in contours {
            let cc = centroid(c)
            var dup = false
            for (i, k) in kept.enumerated() {
                if abs(k.total - c.total) < 0.05 * max(k.total, c.total),
                   hypot(cents[i].x - cc.x, cents[i].y - cc.y) < 0.012 {
                    dup = true; break
                }
            }
            if !dup { kept.append(c); cents.append(cc) }
        }
        return kept
    }

    /// Orders contours into a continuous pen walk: start at the bottom-most
    /// contour, then always hop to the nearest remaining one (proximity, not
    /// height), so the pen navigates across the edges.
    private static func orderAsWalk(_ contours: [ContourPolyline]) -> [ContourPolyline] {
        guard !contours.isEmpty else { return [] }
        var remaining = contours
        var startIdx = 0
        var bestY: CGFloat = -1
        for (i, c) in remaining.enumerated() {
            let my = c.points.map(\.y).max() ?? 0
            if my > bestY { bestY = my; startIdx = i }
        }
        var ordered: [ContourPolyline] = []
        var current = remaining.remove(at: startIdx)
        ordered.append(current)
        var pen = current.points.last ?? current.points[0]
        while !remaining.isEmpty {
            var bi = 0
            var bd = CGFloat.greatestFiniteMagnitude
            for (i, c) in remaining.enumerated() {
                var dmin = CGFloat.greatestFiniteMagnitude
                for p in c.points {
                    let d = hypot(p.x - pen.x, p.y - pen.y)
                    if d < dmin { dmin = d }
                }
                if dmin < bd { bd = dmin; bi = i }
            }
            current = remaining.remove(at: bi)
            ordered.append(current)
            pen = current.points.last ?? current.points[0]
        }
        return ordered
    }
}

/// Contour trace: a single glowing pen tip draws detected contours one at a time
/// (bottom→top); drawn strokes persist into the full outline, which holds and
/// fades before repeating. A `Canvas` so it warps with the surface.
/// Live Gray–Scott reaction–diffusion. Persists its grids across frames via
/// `@StateObject`; the view redraws every frame because `time` changes.
private final class ReactionDiffusionModel: ObservableObject {
    private(set) var cols = 0
    private(set) var rows = 0
    private var u: [Double] = []
    private var v: [Double] = []
    private var started = false

    var field: [Double] { v }

    func ensure(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        if cols == self.cols, rows == self.rows, !u.isEmpty { return }
        self.cols = cols; self.rows = rows
        let count = cols * rows
        u = [Double](repeating: 1, count: count)
        v = [Double](repeating: 0, count: count)
        var seed: UInt64 = 88172645463325252
        func rnd() -> Double { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return Double(seed % 100000) / 100000 }
        for _ in 0..<18 {
            let cx = Int(rnd() * Double(cols)), cy = Int(rnd() * Double(rows))
            for dy in -3...3 { for dx in -3...3 {
                let x = (cx + dx + cols) % cols, y = (cy + dy + rows) % rows
                v[y * cols + x] = 1
            } }
        }
        started = true
    }

    func advance() {
        guard started else { return }
        step(iterations: 10)
    }

    private func step(iterations: Int) {
        let du = 0.16, dv = 0.08, f = 0.06, k = 0.062
        let c = cols, r = rows
        guard c > 0, r > 0, u.count == c * r else { return }
        for _ in 0..<iterations {
            var nu = u, nv = v
            for y in 0..<r {
                let cur = y * c, up = ((y - 1 + r) % r) * c, dn = ((y + 1) % r) * c
                for x in 0..<c {
                    let l = (x - 1 + c) % c, rt = (x + 1) % c
                    let i = cur + x
                    let uu = u[i], vv = v[i]
                    let lapU: Double = 0.2 * (u[cur + l] + u[cur + rt] + u[up + x] + u[dn + x])
                        + 0.05 * (u[up + l] + u[up + rt] + u[dn + l] + u[dn + rt]) - uu
                    let lapV: Double = 0.2 * (v[cur + l] + v[cur + rt] + v[up + x] + v[dn + x])
                        + 0.05 * (v[up + l] + v[up + rt] + v[dn + l] + v[dn + rt]) - vv
                    let uvv = uu * vv * vv
                    nu[i] = uu + (du * lapU - uvv + f * (1 - uu))
                    nv[i] = vv + (dv * lapV + uvv - (f + k) * vv)
                }
            }
            u = nu; v = nv
        }
    }
}

private struct ReactionDiffusionContent: View {
    let color: RGBAColor
    let accent: RGBAColor
    let time: Double
    @StateObject private var model = ReactionDiffusionModel()

    var body: some View {
        Canvas { ctx, size in
            let cell = max(8.0, Double(min(size.width, size.height)) / 64)
            let cols = min(110, max(8, Int(Double(size.width) / cell)))
            let rows = min(70, max(8, Int(Double(size.height) / cell)))
            model.ensure(cols: cols, rows: rows)
            let cw = size.width / CGFloat(cols), ch = size.height / CGFloat(rows)
            let v = model.field
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(red: accent.r * 0.25, green: accent.g * 0.25, blue: accent.b * 0.25)))
            guard v.count == cols * rows else { return }
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: cw * 0.6))
                for y in 0..<rows {
                    for x in 0..<cols {
                        let val = v[y * cols + x]
                        if val > 0.12 {
                            let cx = (Double(x) + 0.5) * Double(cw), cy = (Double(y) + 0.5) * Double(ch)
                            let rr = Double(cw) * 0.8
                            let col = Color(red: accent.r + (color.r - accent.r) * val,
                                            green: accent.g + (color.g - accent.g) * val,
                                            blue: accent.b + (color.b - accent.b) * val)
                            layer.fill(Path(ellipseIn: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2)),
                                       with: .color(col.opacity(min(1, val * 1.5))))
                        }
                    }
                }
            }
        }
        .onChange(of: time) { _, _ in model.advance() }
    }
}

private struct ContourTraceContent: View {
    let config: ContourTraceConfig
    let time: Double

    @StateObject private var model = ContourTraceModel()

    private func bandColor(_ bi: Int) -> Color {
        Color(hue: ContourTrace.hue(forBand: bi), saturation: 0.95, brightness: 1)
    }

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.02)))
            let contours = model.contours
            let total = model.totalLength
            guard !contours.isEmpty, total > 0 else { return }

            let rainbow = config.rainbow
            // ~6s per image, so more images take proportionally longer.
            let sweepDur = 6.0 * Double(max(1, config.images.count)) / max(config.speed, 0.02)
            // Elapsed since the contours loaded, so the sweep starts at load.
            let elapsed = max(0, time - model.readyAt)
            let sweepP: CGFloat
            if config.alwaysOn {
                // Trace once, then stay on permanently.
                sweepP = CGFloat(min(elapsed / sweepDur, 1))
                ctx.opacity = 1
            } else {
                let holdDur = max(0, config.holdSeconds), fadeDur = 1.5
                let period = sweepDur + holdDur + fadeDur
                let localT = elapsed.truncatingRemainder(dividingBy: period)
                sweepP = CGFloat(min(localT / sweepDur, 1))
                ctx.opacity = localT < sweepDur + holdDur
                    ? 1
                    : max(0, 1 - (localT - (sweepDur + holdDur)) / fadeDur)
            }

            let laser = config.penColor.color
            let w = size.width, h = size.height
            let drawn = sweepP * total
            let phase = time * 0.03
            func sp(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * w, y: p.y * h) }
            func band(_ midLen: CGFloat) -> Int { ContourTrace.rainbowBand(length: midLen, total: total, phase: phase) }

            var acc: CGFloat = 0
            var full = Path()          // fully-drawn contours (single-color mode)
            var partial = Path()       // the contour currently under the pen
            var bands = rainbow ? [Path](repeating: Path(), count: ContourTrace.rainbowBandCount) : []
            var penTip: CGPoint?

            for c in contours {
                if drawn >= acc + c.total {
                    if rainbow {
                        for k in 1..<c.points.count {
                            let bi = band(acc + (c.lengths[k - 1] + c.lengths[k]) / 2)
                            bands[bi].move(to: sp(c.points[k - 1])); bands[bi].addLine(to: sp(c.points[k]))
                        }
                    } else {
                        full.move(to: sp(c.points[0]))
                        for k in 1..<c.points.count { full.addLine(to: sp(c.points[k])) }
                    }
                    acc += c.total
                } else if drawn > acc {
                    let target = drawn - acc
                    var tip = c.points[0]
                    if !rainbow { partial.move(to: sp(c.points[0])) }
                    for k in 1..<c.points.count {
                        if c.lengths[k] <= target {
                            if rainbow {
                                let bi = band(acc + (c.lengths[k - 1] + c.lengths[k]) / 2)
                                bands[bi].move(to: sp(c.points[k - 1])); bands[bi].addLine(to: sp(c.points[k]))
                            } else {
                                partial.addLine(to: sp(c.points[k]))
                            }
                            tip = c.points[k]
                        } else {
                            let seg = max(c.lengths[k] - c.lengths[k - 1], 0.0001)
                            let f = (target - c.lengths[k - 1]) / seg
                            let a = c.points[k - 1], b = c.points[k]
                            tip = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
                            if rainbow {
                                let bi = band(acc + (c.lengths[k - 1] + target) / 2)
                                bands[bi].move(to: sp(a)); bands[bi].addLine(to: sp(tip))
                            } else {
                                partial.addLine(to: sp(tip))
                            }
                            break
                        }
                    }
                    penTip = sp(tip)
                    break
                } else {
                    break
                }
            }

            // Glow underlay + solid core.
            if rainbow {
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 3))
                    for bi in bands.indices where !bands[bi].isEmpty {
                        layer.stroke(bands[bi], with: .color(bandColor(bi).opacity(0.5)), lineWidth: 2.6)
                    }
                }
                for bi in bands.indices where !bands[bi].isEmpty {
                    ctx.stroke(bands[bi], with: .color(bandColor(bi)), lineWidth: 1.6)
                }
            } else {
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 3))
                    layer.stroke(full, with: .color(laser.opacity(0.5)), lineWidth: 2.6)
                    layer.stroke(partial, with: .color(laser.opacity(0.5)), lineWidth: 2.6)
                }
                ctx.stroke(full, with: .color(laser), lineWidth: 1.6)
                ctx.stroke(partial, with: .color(laser), lineWidth: 1.6)
            }

            // The bright pen tip (only while still drawing).
            if let tip = penTip, sweepP < 1 {
                let glow = rainbow ? bandColor(band(drawn)) : Color.white
                let r: CGFloat = 4
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 5))
                    layer.fill(Path(ellipseIn: CGRect(x: tip.x - r, y: tip.y - r, width: 2 * r, height: 2 * r)),
                               with: .color(glow.opacity(0.9)))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 2, y: tip.y - 2, width: 4, height: 4)), with: .color(.white))
            }
        }
        .task(id: config.images) { model.load(config.images) }
    }
}

// MARK: - 3D math (software projection helpers)

/// A 3-D point / vector used by the 3D effects.
private struct Vec3 { var x = 0.0, y = 0.0, z = 0.0 }

/// Rotate `p` by `ax` about X then `ay` about Y.
private func rot3(_ p: Vec3, _ ax: Double, _ ay: Double) -> Vec3 {
    let cx = cos(ax), sx = sin(ax)
    let y1 = p.y * cx - p.z * sx
    let z1 = p.y * sx + p.z * cx
    let cy = cos(ay), sy = sin(ay)
    return Vec3(x: p.x * cy + z1 * sy, y: y1, z: -p.x * sy + z1 * cy)
}

private func normalize3(_ v: Vec3) -> Vec3 {
    let l = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()
    return l < 1e-9 ? v : Vec3(x: v.x / l, y: v.y / l, z: v.z / l)
}
