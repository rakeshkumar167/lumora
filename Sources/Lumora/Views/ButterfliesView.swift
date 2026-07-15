import LumoraKit
import SwiftUI

/// **Butterflies**: ~40 flapping two-wing sprites drifting through the shared
/// curl-noise flow field, with a gentle upward-biased drift layered on top so
/// the flock slowly rises (wrapping from top back to bottom).
///
/// Reuses `ParticleSwarmSystem` exactly like `ParticleSwarmView` — same
/// reference-type `@State` render state, same `dt`-from-shared-`time` pattern
/// with the sizing-pass skip, same `SwarmDrivers.idle(time:)` + `CurlNoiseField`.
/// Only the driver gains are calmer (flutter, not school) and the sprite is a
/// two-wing butterfly instead of a fish streak.
struct ButterfliesView: View {
    let color: RGBAColor
    let accent: RGBAColor
    let time: Double

    @State private var state = ButterflyRenderState()

    private let field = CurlNoiseField()

    /// Normalized units/second the flock gently rises. Small enough to read as
    /// a lazy drift, not a launch.
    private let riseRate = 0.012

    var body: some View {
        Canvas { ctx, size in
            step(now: time)
            draw(ctx: ctx, size: size)
        }
    }

    // MARK: - Simulation

    private func step(now: Double) {
        // Skip if this is a repeat draw at the same clock value (sizing pass).
        guard now != state.lastTime else { return }
        let dt = state.lastTime == nil ? 1.0 / 60 : now - state.lastTime!
        state.lastTime = now

        let sys = state.system
        // Calmer than the fish/particle swarm: butterflies flutter, not school.
        let drivers = SwarmDrivers(
            speed: 0.5 + 0.12 * sin(now * 0.09),
            turbulence: 0.22,
            cohesion: 0.15,
            energy: 0.2,
            colorMix: 0.5 + 0.5 * sin(now * 0.04),
            brightness: 0.9)
        sys.step(rawDt: dt, drivers: drivers, field: field, time: now)
        applyRise(dt: dt)
    }

    /// Nudge each particle upward each frame, wrapping from top back to
    /// bottom, layered on top of the flow-field motion so the flock gently
    /// rises overall.
    private func applyRise(dt: Double) {
        let sys = state.system
        for i in 0..<sys.count {
            sys.nudgeY(i, by: -riseRate * dt)
        }
    }

    // MARK: - Rendering

    private func draw(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.03, green: 0.025, blue: 0.02)))
        let sys = state.system
        let w = size.width, h = size.height
        let base = color.color, hot = accent.color

        for i in 0..<sys.count {
            let p = sys.positions[i]
            let v = sys.velocities[i]
            let seed = sys.seeds[i]
            let px = CGFloat(p.x) * w, py = CGFloat(p.y) * h

            let vlen = (Double(v.dx) * Double(v.dx) + Double(v.dy) * Double(v.dy)).squareRoot()
            let heading = vlen > 1e-6 ? atan2(Double(v.dy), Double(v.dx)) : seed * .pi * 2

            let flapRate = 6.0 + seed * 3.0
            let flap = sin(time * flapRate + seed * 6.283)
            let openness = 0.35 + 0.65 * abs(flap)

            let scale = 0.7 + seed * 0.6
            drawButterfly(ctx: ctx, at: CGPoint(x: px, y: py), heading: heading,
                          openness: openness, scale: scale, base: base, hot: hot)
        }
    }

    private func drawButterfly(ctx: GraphicsContext, at center: CGPoint, heading: Double,
                                openness: Double, scale: Double, base: Color, hot: Color) {
        let bodyLen = CGFloat(14 * scale)
        let wingW = CGFloat(11 * scale) * CGFloat(openness)
        let foreWingH = CGFloat(9 * scale)
        let hindWingH = CGFloat(6 * scale)

        // Build the sprite in body-local space (facing +x = heading), then
        // rotate/translate into place via a transformed GraphicsContext.
        var ctx = ctx
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: Angle(radians: heading))

        let gradient = Gradient(colors: [base, hot])

        // Wing shape: an ellipse lobe offset from the body axis (local x) and
        // along the wing axis (local y), so forewing/hindwing pairs sit fore
        // and aft, above and below the body line.
        func wingLobe(xOffset: CGFloat, dy: CGFloat, w: CGFloat, h: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: xOffset - w / 2, y: dy - h / 2, width: w, height: h))
        }

        // Soft glow underlayer for a dreamy look.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            layer.blendMode = .plusLighter
            let glow = Path(ellipseIn: CGRect(x: -wingW, y: -foreWingH, width: wingW * 2, height: foreWingH * 2))
            layer.fill(glow, with: .color(hot.opacity(0.18 * openness)))
        }

        // Forewings (front, larger) — one per side, offset along the wing axis
        // (perpendicular to heading, i.e. local y).
        let fore1 = wingLobe(xOffset: bodyLen * 0.15, dy: -foreWingH * 0.65, w: wingW, h: foreWingH)
        let fore2 = wingLobe(xOffset: bodyLen * 0.15, dy: foreWingH * 0.65, w: wingW, h: foreWingH)
        // Hindwings (back, smaller).
        let hind1 = wingLobe(xOffset: -bodyLen * 0.1, dy: -hindWingH * 0.55, w: wingW * 0.75, h: hindWingH)
        let hind2 = wingLobe(xOffset: -bodyLen * 0.1, dy: hindWingH * 0.55, w: wingW * 0.75, h: hindWingH)

        for wing in [fore1, fore2, hind1, hind2] {
            ctx.fill(wing, with: .radialGradient(gradient, center: .zero,
                                                   startRadius: 0, endRadius: wingW))
            ctx.stroke(wing, with: .color(hot.opacity(0.6)), lineWidth: 0.6)
        }

        // Thin dark body line down the middle (local x axis).
        var bodyPath = Path()
        bodyPath.move(to: CGPoint(x: -bodyLen * 0.35, y: 0))
        bodyPath.addLine(to: CGPoint(x: bodyLen * 0.5, y: 0))
        ctx.stroke(bodyPath, with: .color(.black.opacity(0.55)), lineWidth: CGFloat(1.4 * scale))
    }
}

/// Reference-type render state so the simulation survives view-body redraws
/// without `@State` value invalidation. Created once per `ButterfliesView`
/// instance (each window gets its own).
final class ButterflyRenderState {
    let system = ParticleSwarmSystem(count: 40)
    var lastTime: Double?
}
