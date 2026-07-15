import LumoraKit
import SwiftUI

/// **Aquarium**: a fish tank. ~55 fish school through the shared curl-noise flow
/// field over a deep-water gradient, with swaying kelp anchored to the bottom
/// and rising bubble columns in front. FIXED palette (no primary/accent color).
///
/// The fish reuse `ParticleSwarmSystem` exactly like `ParticleSwarmView` — same
/// reference-type `@State` render state, same `dt`-from-shared-`time` pattern
/// with the sizing-pass skip (so the sim never double-steps on a repeat draw at
/// the same clock value), same `CurlNoiseField`. Drivers are calm and cohesive
/// (fish cruise and school, they don't dart). Kelp and bubbles are simple
/// deterministic time-driven layers, not part of the stepped sim.
///
/// Layers are drawn back-to-front: deep-water gradient → kelp → fish → bubbles.
struct AquariumView: View {
    let time: Double

    @State private var state = AquariumRenderState()

    private let field = CurlNoiseField(frequency: 2.4, timeScale: 0.10)

    // Fixed layer geometry (normalized x positions).
    private let kelpX: [Double] = [0.16, 0.5, 0.83]
    private let bubbleX: [Double] = [0.27, 0.6, 0.88]

    var body: some View {
        Canvas { ctx, size in
            step(now: time)
            draw(ctx: ctx, size: size)
        }
    }

    // MARK: - Simulation

    private func step(now: Double) {
        // Skip if this is a repeat draw at the same clock value (sizing pass) —
        // stepping again here would double-advance the sim.
        guard now != state.lastTime else { return }
        let dt = state.lastTime == nil ? 1.0 / 60 : now - state.lastTime!
        state.lastTime = now

        // Calm, cohesive cruise: fish school together and glide, not dart.
        let drivers = SwarmDrivers(
            speed: 0.42 + 0.10 * sin(now * 0.08),
            turbulence: 0.06,
            cohesion: 0.55 + 0.1 * sin(now * 0.05),
            energy: 0.2,
            colorMix: 0,
            brightness: 1)
        state.system.step(rawDt: dt, drivers: drivers, field: field, time: now)
    }

    // MARK: - Rendering

    private func draw(ctx: GraphicsContext, size: CGSize) {
        drawWater(ctx: ctx, size: size)
        drawKelp(ctx: ctx, size: size)
        drawFish(ctx: ctx, size: size)
        drawBubbles(ctx: ctx, size: size)
    }

    // MARK: Layer 1 — deep-water gradient

    private func drawWater(ctx: GraphicsContext, size: CGSize) {
        let grad = Gradient(colors: [
            Color(red: 0.06, green: 0.30, blue: 0.40),   // lighter teal near surface
            Color(red: 0.02, green: 0.12, blue: 0.24),
            Color(red: 0.01, green: 0.03, blue: 0.10),   // dark navy at the floor
        ])
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(grad,
                                       startPoint: CGPoint(x: size.width / 2, y: 0),
                                       endPoint: CGPoint(x: size.width / 2, y: size.height)))
    }

    // MARK: Layer 2 — kelp

    private func drawKelp(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        for (k, bx) in kelpX.enumerated() {
            let phase = Double(k) * 2.1
            let strandH = h * (0.62 + 0.16 * hash01(k, 11))
            let baseW = min(w, h) * (0.03 + 0.012 * hash01(k, 12))
            let swaySpeed = 0.7 + 0.25 * hash01(k, 13)
            let swayAmp = min(w, h) * 0.05

            // Centerline sampled base→tip; sway grows toward the tip.
            let segs = 22
            func centerline(_ t: Double) -> CGPoint {
                let y = h - CGFloat(t) * strandH
                let sway = sin(time * swaySpeed + t * 3.0 + phase) * swayAmp * CGFloat(t)
                return CGPoint(x: CGFloat(bx) * w + sway, y: y)
            }
            func width(_ t: Double) -> CGFloat { baseW * CGFloat(1 - t * 0.85) }

            // Build a tapered ribbon polygon: up the left edge, down the right.
            var ribbon = Path()
            var pts: [CGPoint] = []
            for s in 0...segs { pts.append(centerline(Double(s) / Double(segs))) }
            for (i, p) in pts.enumerated() {
                let t = Double(i) / Double(segs)
                let ww = width(t)
                let pt = CGPoint(x: p.x - ww, y: p.y)
                if i == 0 { ribbon.move(to: pt) } else { ribbon.addLine(to: pt) }
            }
            for i in stride(from: pts.count - 1, through: 0, by: -1) {
                let t = Double(i) / Double(segs)
                let ww = width(t)
                ribbon.addLine(to: CGPoint(x: pts[i].x + ww, y: pts[i].y))
            }
            ribbon.closeSubpath()

            let kelpColor = Color(red: 0.05 + 0.05 * hash01(k, 14),
                                  green: 0.35 + 0.12 * hash01(k, 15),
                                  blue: 0.12)
            ctx.fill(ribbon, with: .color(kelpColor.opacity(0.9)))

            // A few leaf blades branching off, alternating sides, swaying too.
            for b in 0..<5 {
                let t = 0.25 + 0.16 * Double(b)
                guard t < 0.98 else { continue }
                let base = centerline(t)
                let side: CGFloat = (b % 2 == 0) ? 1 : -1
                let bladeLen = baseW * (2.4 - CGFloat(t) * 1.4)
                let flutter = sin(time * (swaySpeed + 0.4) + Double(b) + phase) * 0.3
                let ang = Double(side) * (0.7 + flutter)
                let sinA = CGFloat(sin(ang))
                let cosA = CGFloat(cos(abs(ang)))
                let tip = CGPoint(x: base.x + sinA * bladeLen,
                                  y: base.y - cosA * bladeLen * 0.5)
                let midX = base.x + sinA * bladeLen * 0.5 + side * bladeLen * 0.25
                let mid = CGPoint(x: midX, y: base.y - bladeLen * 0.15)
                let backCtrl = CGPoint(x: base.x + sinA * bladeLen * 0.5,
                                       y: base.y + bladeLen * 0.05)
                var blade = Path()
                blade.move(to: base)
                blade.addQuadCurve(to: tip, control: mid)
                blade.addQuadCurve(to: base, control: backCtrl)
                ctx.fill(blade, with: .color(kelpColor.opacity(0.8)))
            }
        }
    }

    // MARK: Layer 3 — fish

    private func drawFish(ctx: GraphicsContext, size: CGSize) {
        let sys = state.system
        let w = size.width, h = size.height
        let minDim = min(w, h)

        for i in 0..<sys.count {
            let p = sys.positions[i]
            let v = sys.velocities[i]
            let seed = sys.seeds[i]
            let px = CGFloat(p.x) * w, py = CGFloat(p.y) * h

            let vlen = (Double(v.dx) * Double(v.dx) + Double(v.dy) * Double(v.dy)).squareRoot()
            let heading = vlen > 1e-6 ? atan2(Double(v.dy), Double(v.dx)) : seed * .pi * 2

            let tier = min(2, Int(seed * 3))
            let scale = minDim / 640 * (0.85 + seed * 0.7)
            let wagRate = 7.0 + seed * 3.0
            let wag = sin(time * wagRate + seed * 6.283)

            drawOneFish(ctx: ctx, at: CGPoint(x: px, y: py), heading: heading,
                        scale: scale, wag: wag, tier: tier)
        }
    }

    /// Fixed palette per tier: 0 = clownfish (orange), 1 = blue tang, 2 = silver.
    private func fishColors(_ tier: Int) -> (body: Color, belly: Color, fin: Color) {
        switch tier {
        case 0:
            return (Color(red: 1.0, green: 0.48, blue: 0.12),
                    Color(red: 1.0, green: 0.78, blue: 0.5),
                    Color(red: 1.0, green: 0.95, blue: 0.9))
        case 1:
            return (Color(red: 0.13, green: 0.45, blue: 0.92),
                    Color(red: 0.45, green: 0.72, blue: 1.0),
                    Color(red: 1.0, green: 0.85, blue: 0.2))
        default:
            return (Color(red: 0.74, green: 0.80, blue: 0.86),
                    Color(red: 0.92, green: 0.95, blue: 0.98),
                    Color(red: 0.6, green: 0.66, blue: 0.72))
        }
    }

    private func drawOneFish(ctx: GraphicsContext, at center: CGPoint, heading: Double,
                             scale: CGFloat, wag: Double, tier: Int) {
        let (body, belly, fin) = fishColors(tier)
        let L = 26 * scale       // body length
        let H = 12 * scale       // body height

        // Build in body-local space (facing +x), then rotate/translate into place.
        var ctx = ctx
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: Angle(radians: heading))

        // Tail: a triangle hinged at the body's rear that swishes with `wag`.
        let tailBase = CGPoint(x: -L * 0.5, y: 0)
        let tailLen = L * 0.5
        let tailSpread = H * 0.62
        let wagAngle = CGFloat(wag) * 0.5
        func rot(_ p: CGPoint) -> CGPoint {
            let dx = p.x - tailBase.x, dy = p.y - tailBase.y
            return CGPoint(x: tailBase.x + dx * cos(wagAngle) - dy * sin(wagAngle),
                           y: tailBase.y + dx * sin(wagAngle) + dy * cos(wagAngle))
        }
        var tail = Path()
        tail.move(to: tailBase)
        tail.addLine(to: rot(CGPoint(x: -L * 0.5 - tailLen, y: -tailSpread)))
        tail.addLine(to: rot(CGPoint(x: -L * 0.5 - tailLen, y: tailSpread)))
        tail.closeSubpath()
        ctx.fill(tail, with: .color(fin.opacity(0.9)))

        // Dorsal + pelvic fins (small triangles top/bottom of the body).
        var dorsal = Path()
        dorsal.move(to: CGPoint(x: L * 0.05, y: -H * 0.42))
        dorsal.addLine(to: CGPoint(x: -L * 0.25, y: -H * 0.42))
        dorsal.addLine(to: CGPoint(x: -L * 0.1, y: -H * 0.95))
        dorsal.closeSubpath()
        ctx.fill(dorsal, with: .color(fin.opacity(0.75)))

        // Teardrop body: wider toward the head, tapering to the tail.
        let nose = CGPoint(x: L * 0.55, y: 0)
        var bodyPath = Path()
        bodyPath.move(to: nose)
        bodyPath.addCurve(to: tailBase,
                          control1: CGPoint(x: L * 0.2, y: -H * 0.62),
                          control2: CGPoint(x: -L * 0.25, y: -H * 0.5))
        bodyPath.addCurve(to: nose,
                          control1: CGPoint(x: -L * 0.25, y: H * 0.5),
                          control2: CGPoint(x: L * 0.2, y: H * 0.62))
        bodyPath.closeSubpath()

        // Soft glow underlayer (bounded blur) for a nice underwater sheen.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            layer.blendMode = .plusLighter
            layer.fill(bodyPath, with: .color(body.opacity(0.25)))
        }

        // Body with a belly gradient (lighter underside).
        ctx.fill(bodyPath, with: .linearGradient(Gradient(colors: [belly, body]),
                                                 startPoint: CGPoint(x: 0, y: H * 0.6),
                                                 endPoint: CGPoint(x: 0, y: -H * 0.6)))

        // A couple of banding stripes for clownfish/silver character.
        if tier != 1 {
            for sx in [L * 0.25, -L * 0.02] {
                var stripe = Path()
                stripe.move(to: CGPoint(x: sx, y: -H * 0.5))
                stripe.addLine(to: CGPoint(x: sx - L * 0.06, y: H * 0.5))
                ctx.stroke(stripe, with: .color(fin.opacity(0.5)), lineWidth: max(1, L * 0.05))
            }
        }

        // Eye: white dot with a dark pupil, near the head.
        let eye = CGPoint(x: L * 0.3, y: -H * 0.12)
        let eyeR = max(1.2, H * 0.14)
        ctx.fill(Path(ellipseIn: CGRect(x: eye.x - eyeR, y: eye.y - eyeR, width: eyeR * 2, height: eyeR * 2)),
                 with: .color(.white))
        let pupR = eyeR * 0.55
        ctx.fill(Path(ellipseIn: CGRect(x: eye.x - pupR, y: eye.y - pupR, width: pupR * 2, height: pupR * 2)),
                 with: .color(.black.opacity(0.85)))
    }

    // MARK: Layer 4 — rising bubbles

    private func drawBubbles(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let minDim = min(w, h)
        for (col, bx) in bubbleX.enumerated() {
            let perCol = 6
            let riseSpeed = 0.10 + 0.03 * hash01(col, 21)
            let wobRate = 1.5 + hash01(col, 22)
            let wobble = minDim * 0.02
            for j in 0..<perCol {
                // Each bubble rises from the floor to the surface, then respawns.
                let offset = Double(j) / Double(perCol) + hash01(col * 7 + j, 23)
                let prog = (time * riseSpeed + offset).truncatingRemainder(dividingBy: 1.0)
                let y = h * (1 - CGFloat(prog))
                let wob = sin(time * wobRate + Double(j) * 1.7 + Double(col)) * wobble
                let x = CGFloat(bx) * w + CGFloat(wob)
                let r = minDim * (0.006 + 0.012 * hash01(col * 13 + j, 24)) * (0.5 + CGFloat(prog) * 0.7)
                let alpha = 0.5 * min(1, prog * 4) * (1 - prog * 0.35)   // fade in low, fade near top

                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.10 * alpha)))
                ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.85 * alpha)),
                           lineWidth: max(0.6, r * 0.14))
                // Little highlight glint on the upper-left.
                let gr = r * 0.3
                ctx.fill(Path(ellipseIn: CGRect(x: x - r * 0.4 - gr, y: y - r * 0.4 - gr,
                                                width: gr * 2, height: gr * 2)),
                         with: .color(.white.opacity(0.9 * alpha)))
            }
        }
    }

    /// Deterministic hash → `0…1` for fixed per-strand / per-bubble variation.
    private func hash01(_ i: Int, _ salt: Int) -> Double {
        let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return v - floor(v)
    }
}

/// Reference-type render state so the fish simulation survives view-body redraws
/// without `@State` value invalidation. One per `AquariumView` instance.
final class AquariumRenderState {
    let system = ParticleSwarmSystem(count: 55)
    var lastTime: Double?
}
