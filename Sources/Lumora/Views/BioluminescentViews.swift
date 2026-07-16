import LumoraKit
import SwiftUI

/// Fixed "Avatar/Pandora night jungle" palette shared by all four
/// Bioluminescent effects so the set reads as one world out of the box. None of
/// the effects expose color pickers (see `EffectKind.usesColor`).
enum BioPalette {
    static let night = Color(red: 0.008, green: 0.024, blue: 0.039)   // #02060A
    static let waterDeep = Color(red: 0.012, green: 0.075, blue: 0.094) // #031318
    static let waterMid = Color(red: 0.020, green: 0.196, blue: 0.227)  // #05323A
    static let glowCyan = Color(red: 0.157, green: 0.902, blue: 0.824)  // #28E6D2
    static let glowAqua = Color(red: 0.361, green: 0.949, blue: 1.0)    // #5CF2FF
    static let glowTeal = Color(red: 0.071, green: 0.718, blue: 0.659)  // #12B7A8
    static let accentMagenta = Color(red: 0.725, green: 0.294, blue: 0.878) // #B94BE0
    static let accentViolet = Color(red: 0.478, green: 0.294, blue: 1.0)    // #7A4BFF
    static let moon = Color(red: 0.749, green: 0.914, blue: 1.0)        // #BFE9FF
    static let mist = Color(red: 0.055, green: 0.165, blue: 0.200)      // #0E2A33

    /// Deterministic hash in `0…1` from an integer index + salt (matches the
    /// `hash01` idiom used across the effect renderers).
    static func hash01(_ i: Int, _ salt: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return CGFloat(v - floor(v))
    }
}

// MARK: - Effect 1: Misty Peaks

/// **Misty Peaks** — a stateless, time-driven backdrop: a moonlit night sky with
/// twinkling stars, several parallax mountain-silhouette ridges drifting at their
/// own speeds, and translucent mist bands sliding across between them. Fully
/// deterministic from `time` (no `@State`); draws back-to-front.
struct MistyPeaksView: View {
    let time: Double

    var body: some View {
        Canvas { ctx, size in draw(ctx: ctx, size: size) }
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height

        // 1. Sky gradient: near-black at the bottom lifting to a deep blue-teal up top.
        let skyTop = Color(red: 0.02, green: 0.06, blue: 0.10)
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [skyTop, BioPalette.night]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

        // 2. Moon glow: a soft radial bloom high and slightly off-center, breathing.
        let moonBreathe = 0.85 + 0.15 * sin(time * 0.25)
        let moonC = CGPoint(x: w * 0.68, y: h * 0.22)
        let moonR = min(w, h) * 0.28
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 30))
            l.blendMode = .plusLighter
            l.fill(Path(ellipseIn: CGRect(x: moonC.x - moonR, y: moonC.y - moonR,
                                          width: moonR * 2, height: moonR * 2)),
                   with: .radialGradient(Gradient(colors: [BioPalette.moon.opacity(0.55 * moonBreathe), .clear]),
                                         center: moonC, startRadius: 0, endRadius: moonR))
        }
        // Crisp moon disk.
        let discR = min(w, h) * 0.05
        ctx.fill(Path(ellipseIn: CGRect(x: moonC.x - discR, y: moonC.y - discR,
                                        width: discR * 2, height: discR * 2)),
                 with: .color(BioPalette.moon.opacity(0.9 * moonBreathe)))

        // 3. Stars: faint hashed points, twinkling, kept in the upper ~60%.
        for i in 0..<60 {
            let sx = BioPalette.hash01(i, 1) * w
            let sy = BioPalette.hash01(i, 2) * h * 0.6
            let tw = 0.3 + 0.7 * (0.5 + 0.5 * sin(time * 1.3 + Double(i) * 1.7))
            let s = 0.8 + 1.4 * BioPalette.hash01(i, 3)
            ctx.fill(Path(ellipseIn: CGRect(x: sx, y: sy, width: s, height: s)),
                     with: .color(BioPalette.moon.opacity(0.7 * tw)))
        }

        // 4. Parallax ridges: farthest (lighter/bluer, slower) to nearest (darker).
        let ridgeCount = 4
        for r in 0..<ridgeCount {
            let depth = Double(r) / Double(ridgeCount - 1)   // 0 far … 1 near
            // Far ridges sit higher and are lighter/bluer; near ridges fill lower.
            let baseY = h * CGFloat(0.42 + 0.14 * depth)
            let amp = h * CGFloat(0.06 + 0.10 * depth)
            let drift = CGFloat(time * (0.6 + Double(r) * 1.4)) * (1 + CGFloat(depth))
            let tint = Color(red: 0.03 + 0.05 * (1 - depth),
                             green: 0.08 + 0.10 * (1 - depth),
                             blue: 0.12 + 0.14 * (1 - depth))

            var ridge = Path()
            ridge.move(to: CGPoint(x: 0, y: h))
            let steps = 40
            for s in 0...steps {
                let fx = CGFloat(s) / CGFloat(steps)
                let x = fx * w
                // Layered hashed jags scrolling horizontally give a mountain profile.
                let n1 = sin(Double(fx) * 6.0 + Double(drift) * 0.03 + Double(r) * 2.0)
                let n2 = sin(Double(fx) * 15.0 + Double(drift) * 0.05 + Double(r) * 5.0) * 0.4
                let jag = Double(BioPalette.hash01(s + r * 100, r + 1)) * 0.5
                let y = baseY - amp * CGFloat(n1 + n2 + jag - 0.4)
                ridge.addLine(to: CGPoint(x: x, y: y))
            }
            ridge.addLine(to: CGPoint(x: w, y: h))
            ridge.closeSubpath()
            ctx.fill(ridge, with: .color(tint))
        }

        // 5. Mist bands: translucent blurred horizontal bands drifting sideways.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 26))
            l.blendMode = .plusLighter
            for b in 0..<3 {
                let by = h * CGFloat(0.45 + 0.16 * Double(b))
                let bh = h * 0.10
                let phase = time * (0.03 + 0.02 * Double(b)) + Double(b)
                let ox = CGFloat(sin(phase) * Double(w) * 0.15)
                let band = Path(roundedRect: CGRect(x: -w * 0.2 + ox, y: by - bh / 2,
                                                    width: w * 1.4, height: bh),
                                cornerRadius: bh / 2)
                l.fill(band, with: .color(BioPalette.mist.opacity(0.22)))
            }
        }
    }
}

// MARK: - Effect 2: Drifting Spores

/// **Drifting Spores** — an ambient overlay of ~65 soft glowing woodsprite motes
/// rising gently through the frame. Reuses the shared `ParticleSwarmSystem` +
/// `CurlNoiseField` exactly like `ButterfliesView` (calm `idle` drivers), with an
/// upward `nudgeY` rise so spores drift up and wrap bottom→top. Near-black base so
/// it overlays other surfaces. Fixed palette; no config.
struct DriftingSporesView: View {
    let time: Double

    @State private var state = DriftingSporesState()

    private let field = CurlNoiseField(frequency: 2.2, timeScale: 0.10)
    /// Normalized units/second the motes gently rise.
    private let riseRate = 0.018

    var body: some View {
        Canvas { ctx, size in
            step(now: time)
            draw(ctx: ctx, size: size)
        }
    }

    private func step(now: Double) {
        // Skip repeat draws at the same clock value (sizing pass) — don't double-step.
        guard now != state.lastTime else { return }
        let dt = state.lastTime == nil ? 1.0 / 60 : now - state.lastTime!
        state.lastTime = now

        let sys = state.system
        // Calm ambient drift (SwarmDrivers.idle-style): low speed, gentle turbulence.
        let drivers = SwarmDrivers(
            speed: 0.32 + 0.08 * sin(now * 0.07),
            turbulence: 0.28,
            cohesion: 0.1,
            energy: 0.15,
            colorMix: 0.5,
            brightness: 0.9)
        sys.step(rawDt: dt, drivers: drivers, field: field, time: now)
        for i in 0..<sys.count { sys.nudgeY(i, by: -riseRate * dt) }
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(BioPalette.night))
        let sys = state.system
        let w = size.width, h = size.height
        let minDim = min(w, h)

        // Soft glowing halos (one batched blurred additive layer).
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.blendMode = .plusLighter
            for i in 0..<sys.count {
                let p = sys.positions[i]
                let seed = sys.seeds[i]
                let px = CGFloat(p.x) * w, py = CGFloat(p.y) * h
                let twinkle = 0.4 + 0.6 * (0.5 + 0.5 * sin(time * (0.8 + seed * 1.4) + seed * 6.283))
                let r = (minDim * 0.012) * (0.7 + seed * 0.9)
                // Rare violet motes; most are aqua/cyan.
                let rare = seed > 0.9
                let halo = rare ? BioPalette.accentViolet : (seed > 0.5 ? BioPalette.glowAqua : BioPalette.glowCyan)
                layer.fill(Path(ellipseIn: CGRect(x: px - r * 2.2, y: py - r * 2.2,
                                                  width: r * 4.4, height: r * 4.4)),
                           with: .color(halo.opacity(0.5 * twinkle)))
            }
        }

        // Crisp bright cores + faint radiating tendrils for a woodsprite feel.
        for i in 0..<sys.count {
            let p = sys.positions[i]
            let seed = sys.seeds[i]
            let px = CGFloat(p.x) * w, py = CGFloat(p.y) * h
            let twinkle = 0.4 + 0.6 * (0.5 + 0.5 * sin(time * (0.8 + seed * 1.4) + seed * 6.283))
            let r = (minDim * 0.006) * (0.7 + seed * 0.9)
            let rare = seed > 0.9
            let core = rare ? BioPalette.accentViolet : BioPalette.glowAqua

            // A few short radiating spokes (subtle).
            let spokes = 5
            let tR = r * 3.2
            var tendrils = Path()
            for s in 0..<spokes {
                let a = Double(s) / Double(spokes) * 2 * .pi + time * 0.3 + seed * 6.283
                tendrils.move(to: CGPoint(x: px, y: py))
                tendrils.addLine(to: CGPoint(x: px + CGFloat(cos(a)) * tR,
                                             y: py + CGFloat(sin(a)) * tR))
            }
            ctx.stroke(tendrils, with: .color(core.opacity(0.18 * twinkle)), lineWidth: 0.6)

            ctx.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)),
                     with: .color(.white.opacity(0.85 * twinkle)))
        }
    }
}

/// Reference-type render state for `DriftingSporesView` so the swarm survives
/// view-body redraws without `@State` value invalidation.
final class DriftingSporesState {
    let system = ParticleSwarmSystem(count: 65)
    var lastTime: Double?
}

// MARK: - Effect 3: Glowing Flora

/// **Glowing Flora** — bioluminescent plants rooted along the bottom edge that
/// grow upward, bloom glowing flower-pods, then gently sway and pulse before
/// fading and regrowing (re-seeded each cycle). Mirrors `GrowingIvyView`'s
/// grow → hold → fade cycle anchored to a per-view `startRef` (the effect clock
/// is global, so `time % period` would snap), and reuses its glow-stroke idiom;
/// but the growth paths are open upward stem curves, not the closed outline loop.
/// Fixed palette; no config.
struct GlowingFloraView: View {
    let time: Double

    @State private var startRef: Double?

    private let growDur = 12.0
    private let holdDur = 6.0
    private let fadeDur = 2.5
    private var period: Double { growDur + holdDur + fadeDur }

    // Per-cycle precomputed plant layout, rebuilt only when the cycle index (or
    // canvas size) changes — not every frame.
    private final class Layout {
        var cycleIndex: Int = .min
        var size: CGSize = .zero
        var plants: [Plant] = []
    }
    private struct Branch {
        var startArc: CGFloat       // arc length up the stem where this branch departs
        var points: [CGPoint]       // absolute polyline for the branch
        var lengths: (cum: [CGFloat], total: CGFloat)
        var podSize: CGFloat
        var useMagenta: Bool
    }
    private struct Frond {
        var arc: CGFloat            // arc length up the stem where it sprouts
        var dir: CGVector
        var size: CGFloat
    }
    private struct Plant {
        var stem: [CGPoint]
        var stemLengths: (cum: [CGFloat], total: CGFloat)
        var branches: [Branch]
        var fronds: [Frond]
        var swayPhase: Double
    }
    @State private var layout = Layout()

    var body: some View {
        Canvas { ctx, size in
            let elapsed = startRef.map { max(0, time - $0) } ?? 0
            draw(ctx: ctx, size: size, elapsed: elapsed)
        }
        .onAppear { if startRef == nil { startRef = Date().timeIntervalSinceReferenceDate } }
    }

    private func draw(ctx baseCtx: GraphicsContext, size: CGSize, elapsed: Double) {
        var ctx = baseCtx
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(BioPalette.night))
        guard size.width > 1, size.height > 1 else { return }

        let cycleIndex = Int(elapsed / period)
        let localT = elapsed.truncatingRemainder(dividingBy: period)
        rebuildIfNeeded(cycleIndex: cycleIndex, size: size)

        // Phase timing.
        let growFrac = min(localT / growDur, 1.0)                 // 0…1 stem reveal
        let inFade = localT >= growDur + holdDur
        let fadeT = inFade ? (localT - growDur - holdDur) / fadeDur : 0
        let alpha = 1 - fadeT                                     // whole-plant fade at cycle end
        guard alpha > 0.001 else { return }

        let stemC = BioPalette.glowTeal
        let leafC = BioPalette.glowCyan

        for plant in layout.plants {
            let litLen = CGFloat(growFrac) * plant.stemLengths.total
            let sway = growFrac >= 1.0 ? CGFloat(sin(time * 0.8 + plant.swayPhase)) * 0.012 * size.width : 0

            // --- Stem (revealed up to litLen), swaying more toward the tip. ------
            let stemPath = revealedPath(plant.stem, plant.stemLengths, upTo: litLen, sway: sway)

            // --- Branches: only extend after the stem tip passes their base. -----
            var branchPath = Path()
            struct PodDraw { var center: CGPoint; var size: CGFloat; var bloom: CGFloat; var magenta: Bool }
            var pods: [PodDraw] = []
            for b in plant.branches {
                let bloom = max(0, min(1, (litLen - b.startArc) / 60))
                if bloom <= 0.001 { continue }
                let bp = revealedPath(b.points, b.lengths, upTo: b.lengths.total * bloom, sway: sway)
                branchPath.addPath(bp)
                // Flower-pod at the branch tip, blooming (scale+brighten) as it completes.
                if let last = b.points.last {
                    let center = CGPoint(x: last.x + sway, y: last.y)
                    pods.append(PodDraw(center: center, size: b.podSize, bloom: bloom, magenta: b.useMagenta))
                }
            }

            // --- Fronds (small fern leaf-pairs) along the revealed stem. ---------
            var frondPath = Path()
            for f in plant.fronds where f.arc <= litLen {
                let base = pointAtArc(plant.stem, plant.stemLengths, arc: f.arc)
                let bx = base.x + sway
                for side in [CGFloat(1), CGFloat(-1)] {
                    let tip = CGPoint(x: bx + (f.dir.dx * side) * f.size,
                                      y: base.y + f.dir.dy * f.size)
                    frondPath.move(to: CGPoint(x: bx, y: base.y))
                    frondPath.addLine(to: tip)
                }
            }

            ctx.opacity = alpha

            // Soft under-glow for stems + branches + fronds (one blurred layer).
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 8))
                layer.blendMode = .plusLighter
                layer.stroke(stemPath, with: .color(stemC.opacity(0.5)),
                             style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                layer.stroke(branchPath, with: .color(stemC.opacity(0.45)),
                             style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                layer.stroke(frondPath, with: .color(leafC.opacity(0.4)),
                             style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            // Crisp stems/branches/fronds.
            ctx.stroke(stemPath, with: .color(stemC.opacity(0.95)),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            ctx.stroke(branchPath, with: .color(stemC.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            ctx.stroke(frondPath, with: .color(leafC.opacity(0.7)),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))

            // Flower-pods: cyan halo + magenta/violet core, pulsing when grown.
            for pod in pods {
                let pulse = growFrac >= 1.0 ? (0.8 + 0.2 * sin(time * 1.6 + Double(pod.center.x))) : 1.0
                let r = pod.size * pod.bloom
                let coreC = pod.magenta ? BioPalette.accentMagenta : BioPalette.accentViolet
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 7))
                    layer.blendMode = .plusLighter
                    layer.fill(Path(ellipseIn: CGRect(x: pod.center.x - r * 1.8, y: pod.center.y - r * 1.8,
                                                      width: r * 3.6, height: r * 3.6)),
                               with: .color(BioPalette.glowCyan.opacity(0.5 * pulse)))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: pod.center.x - r, y: pod.center.y - r,
                                                width: r * 2, height: r * 2)),
                         with: .color(coreC.opacity(0.95 * pulse)))
                ctx.fill(Path(ellipseIn: CGRect(x: pod.center.x - r * 0.4, y: pod.center.y - r * 0.4,
                                                width: r * 0.8, height: r * 0.8)),
                         with: .color(.white.opacity(0.8 * pulse)))
            }

            // Bright growing tip (glow-head) while the stem is still extending.
            if growFrac < 1.0 {
                let head = pointAtArc(plant.stem, plant.stemLengths, arc: litLen)
                let hx = head.x + sway
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 6))
                    layer.blendMode = .plusLighter
                    layer.fill(Path(ellipseIn: CGRect(x: hx - 6, y: head.y - 6, width: 12, height: 12)),
                               with: .color(BioPalette.glowAqua))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: hx - 2.5, y: head.y - 2.5, width: 5, height: 5)),
                         with: .color(.white))
            }
            ctx.opacity = 1
        }
    }

    /// A path along `pts` from the start up to arc length `length`, adding a
    /// tip-weighted horizontal `sway` (0 at the root, full at the tip).
    private func revealedPath(_ pts: [CGPoint], _ lengths: (cum: [CGFloat], total: CGFloat),
                              upTo length: CGFloat, sway: CGFloat) -> Path {
        var path = Path()
        guard let first = pts.first, lengths.total > 0 else { return path }
        path.move(to: first)
        for i in 0..<(pts.count - 1) {
            let segEnd = lengths.cum[i + 1]
            let a = pts[i], b = pts[i + 1]
            let swayA = sway * (lengths.cum[i] / lengths.total)
            if segEnd <= length {
                let swayB = sway * (segEnd / lengths.total)
                if i == 0 { path.move(to: CGPoint(x: a.x + swayA, y: a.y)) }
                path.addLine(to: CGPoint(x: b.x + swayB, y: b.y))
            } else {
                let segStart = lengths.cum[i]
                let segLen = segEnd - segStart
                let f = segLen > 0 ? (length - segStart) / segLen : 0
                let px = a.x + (b.x - a.x) * f, py = a.y + (b.y - a.y) * f
                let swayP = sway * (length / lengths.total)
                if i == 0 { path.move(to: CGPoint(x: a.x + swayA, y: a.y)) }
                path.addLine(to: CGPoint(x: px + swayP, y: py))
                break
            }
        }
        return path
    }

    private func pointAtArc(_ pts: [CGPoint], _ lengths: (cum: [CGFloat], total: CGFloat),
                            arc: CGFloat) -> CGPoint {
        guard let first = pts.first else { return .zero }
        for i in 0..<(pts.count - 1) {
            let segEnd = lengths.cum[i + 1]
            if segEnd >= arc {
                let a = pts[i], b = pts[i + 1]
                let segStart = lengths.cum[i]
                let segLen = segEnd - segStart
                let f = segLen > 0 ? (arc - segStart) / segLen : 0
                return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
            }
        }
        return pts.last ?? first
    }

    private static func polylineLengths(_ pts: [CGPoint]) -> (cum: [CGFloat], total: CGFloat) {
        var cum: [CGFloat] = [0]
        var total: CGFloat = 0
        for i in 0..<max(0, pts.count - 1) {
            total += hypot(pts[i + 1].x - pts[i].x, pts[i + 1].y - pts[i].y)
            cum.append(total)
        }
        return (cum, total)
    }

    /// Precompute this cycle's plants (stems, branches, pods, fronds) once.
    private func rebuildIfNeeded(cycleIndex: Int, size: CGSize) {
        if layout.cycleIndex == cycleIndex && layout.size == size { return }
        layout.cycleIndex = cycleIndex
        layout.size = size
        let w = size.width, h = size.height
        func hh(_ i: Int, _ s: Int) -> CGFloat { BioPalette.hash01(cycleIndex &* 977 &+ i, s) }

        let plantCount = 3 + Int(hh(0, 1) * 3.99)                 // 3…6
        var plants: [Plant] = []
        for p in 0..<plantCount {
            // Root x spread across the width with jitter; grow upward.
            let rootX = w * (CGFloat(p) + 0.5 + (hh(p, 2) - 0.5) * 0.6) / CGFloat(plantCount)
            let rootY = h
            let stemH = h * (0.5 + 0.35 * hh(p, 3))
            let curveDir: CGFloat = hh(p, 4) > 0.5 ? 1 : -1
            let curveAmt = w * 0.06 * (0.5 + hh(p, 5))

            // Build the stem as an upward curve (bottom → top) polyline.
            let stemSteps = 14
            var stem: [CGPoint] = []
            for s in 0...stemSteps {
                let t = CGFloat(s) / CGFloat(stemSteps)
                let y = rootY - stemH * t
                let x = rootX + curveDir * curveAmt * sin(Double(t) * .pi * 0.8)
                stem.append(CGPoint(x: x, y: y))
            }
            let stemLengths = Self.polylineLengths(stem)

            // Branches depart from the upper-middle of the stem, angling outward-up.
            let branchCount = 2 + Int(hh(p, 6) * 2.99)            // 2…4
            var branches: [Branch] = []
            for b in 0..<branchCount {
                let along = 0.4 + 0.5 * CGFloat(b) / CGFloat(max(1, branchCount))
                let baseArc = stemLengths.total * along
                let base = pointAtArc(stem, stemLengths, arc: baseArc)
                let side: CGFloat = (b % 2 == 0) ? 1 : -1
                let bl = stemH * (0.22 + 0.16 * hh(p * 7 + b, 7))
                let ang = (-0.9 - 0.5 * Double(hh(p * 7 + b, 8))) // up-and-out (negative y is up)
                let dx = CGFloat(cos(ang)) * side, dy = CGFloat(sin(ang))
                let bsteps = 6
                var bpts: [CGPoint] = []
                for s in 0...bsteps {
                    let t = CGFloat(s) / CGFloat(bsteps)
                    let curl = CGFloat(sin(Double(t) * .pi)) * bl * 0.15 * side
                    bpts.append(CGPoint(x: base.x + dx * bl * t + curl,
                                        y: base.y + dy * bl * t))
                }
                branches.append(Branch(startArc: baseArc, points: bpts,
                                       lengths: Self.polylineLengths(bpts),
                                       podSize: min(w, h) * (0.012 + 0.010 * hh(p * 7 + b, 9)),
                                       useMagenta: hh(p * 7 + b, 10) > 0.5))
            }

            // Fronds: small leaf-pairs along the lower/mid stem.
            var fronds: [Frond] = []
            let frondCount = 3 + Int(hh(p, 11) * 3.99)
            for f in 0..<frondCount {
                let along = 0.15 + 0.6 * CGFloat(f) / CGFloat(max(1, frondCount))
                fronds.append(Frond(arc: stemLengths.total * along,
                                    dir: CGVector(dx: 0.8, dy: -0.5),
                                    size: min(w, h) * (0.03 + 0.02 * hh(p * 13 + f, 12))))
            }

            plants.append(Plant(stem: stem, stemLengths: stemLengths, branches: branches,
                                 fronds: fronds, swayPhase: Double(hh(p, 13)) * 6.283))
        }
        layout.plants = plants
    }
}

// MARK: - Effect 4: Bioluminescent River

/// **Bioluminescent River** — a directional glowing current. ~120 motes are
/// advected by a base flow velocity plus a `CurlNoiseField` meander (so it reads
/// as a river, not a random swarm), drawn as velocity-aligned glowing streaks
/// that pool into eddies under additive blur; they wrap back to the inflow edge
/// on exit. STATEFUL like `InkFlowView`: the mote buffer lives in a reference-type
/// `@State`, `dt` from the shared `time` with the same-time skip. Fixed palette.
struct BioRiverView: View {
    let time: Double

    @State private var state = BioRiverState()

    private let field = CurlNoiseField(frequency: 2.0, timeScale: 0.15)
    /// Base current direction (normalized units/sec): flows down and slightly right.
    private let current = CGVector(dx: 0.06, dy: 0.14)
    private let meander = 0.09          // curl contribution to velocity
    private let maxMotes = 120

    var body: some View {
        Canvas { ctx, size in
            step(now: time)
            draw(ctx: ctx, size: size)
        }
    }

    private func step(now: Double) {
        guard now != state.lastTime else { return }
        let dt = state.lastTime == nil ? 1.0 / 60 : min(max(now - state.lastTime!, 0), 0.05)
        state.lastTime = now
        guard dt > 0 else { return }

        if state.motes.isEmpty { state.seed(count: maxMotes) }

        for i in state.motes.indices {
            let m = state.motes[i]
            let f = field.flow(x: m.x, y: m.y, t: now)
            let vx = Double(current.dx) + Double(f.dx) * meander
            let vy = Double(current.dy) + Double(f.dy) * meander
            var nx = m.x + vx * dt
            var ny = m.y + vy * dt
            // Wrap around the flow: exiting the bottom/right re-enters the top/left.
            var respawned = false
            if ny > 1.08 { ny -= 1.16; nx = Double(BioRiverState.hash(m.seed, state.reseed)); respawned = true }
            if nx > 1.08 { nx -= 1.16; respawned = true }
            if nx < -0.08 { nx += 1.16 }
            if respawned { state.reseed += 1 }
            state.motes[i].x = nx
            state.motes[i].y = ny
            state.motes[i].vx = vx
            state.motes[i].vy = vy
        }
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height

        // Water base: darker deep at the bottom lifting toward waterMid up top.
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [BioPalette.waterMid, BioPalette.waterDeep]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

        // Ripple highlight bands drifting with the current (subtle shimmer).
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 22))
            l.blendMode = .plusLighter
            for b in 0..<3 {
                let phase = time * 0.12 + Double(b) * 0.4
                let y = (phase.truncatingRemainder(dividingBy: 1.3) - 0.15) * Double(h)
                let band = Path(roundedRect: CGRect(x: -w * 0.1, y: CGFloat(y), width: w * 1.2, height: h * 0.06),
                                cornerRadius: h * 0.03)
                l.fill(band, with: .color(BioPalette.glowTeal.opacity(0.10)))
            }
        }

        // Motes as velocity-aligned streaks, batched into one blurred additive
        // layer so dense areas pool into glowing eddies.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 4))
            l.blendMode = .plusLighter
            for m in state.motes {
                let px = CGFloat(m.x) * w, py = CGFloat(m.y) * h
                let vlen = (m.vx * m.vx + m.vy * m.vy).squareRoot()
                guard vlen > 1e-6 else { continue }
                let tail = CGFloat(24) * CGFloat(vlen / 0.2)
                let ux = CGFloat(m.vx / vlen), uy = CGFloat(m.vy / vlen)
                var streak = Path()
                streak.move(to: CGPoint(x: px - ux * tail, y: py - uy * tail))
                streak.addLine(to: CGPoint(x: px, y: py))
                let rare = m.seed % 17 == 0
                let c = rare ? BioPalette.accentViolet : (m.seed % 2 == 0 ? BioPalette.glowAqua : BioPalette.glowCyan)
                l.stroke(streak, with: .color(c.opacity(0.55)),
                         style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
            }
        }
        // Crisp bright heads.
        for m in state.motes {
            let px = CGFloat(m.x) * w, py = CGFloat(m.y) * h
            let rare = m.seed % 17 == 0
            let r: CGFloat = rare ? 2.6 : 1.6
            let c = rare ? BioPalette.accentViolet : Color.white
            ctx.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)),
                     with: .color(c.opacity(0.9)))
        }
    }
}

/// One river mote: normalized position, current velocity, and a stable seed
/// (drives color tier + respawn jitter).
struct BioMote {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var seed: Int
}

/// Reference-type render state for `BioRiverView` so the mote buffer survives
/// view-body redraws without `@State` value invalidation.
final class BioRiverState {
    var motes: [BioMote] = []
    var lastTime: Double?
    var reseed: Int = 0

    static func hash(_ seed: Int, _ salt: Int) -> Double {
        let v = sin(Double(seed) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return v - floor(v)
    }

    func seed(count: Int) {
        motes.reserveCapacity(count)
        for i in 0..<count {
            motes.append(BioMote(x: Self.hash(i, 1),
                                 y: Self.hash(i, 2),
                                 vx: 0, vy: 0, seed: i))
        }
    }
}
