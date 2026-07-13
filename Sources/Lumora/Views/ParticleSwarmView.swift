import LumoraKit
import SwiftUI

/// Renders both particle effects: **Particle Swarm** (curl-noise driven) and
/// **Audio Reactive Particles** (mic-FFT driven). One shared `ParticleSwarmSystem`
/// stepped each frame; the only difference is where `SwarmDrivers` come from.
///
/// Stateful like `OutlineGlowView`: it reuses the upstream global `time`,
/// computing `dt` from the last frame, and mutates a reference-type render state
/// held in `@State` (so the sim persists across redraws without triggering
/// invalidation). The upstream `TimelineView(.animation)` drives the redraws.
struct ParticleSwarmView: View {
    enum Mode { case swarm, audio }

    let mode: Mode
    let color: RGBAColor
    let accent: RGBAColor
    let time: Double
    /// Injected for audio mode; defaults to the shared microphone manager.
    var audio: AudioLevelsProviding = AudioInputManager.shared

    @State private var state = SwarmRenderState()

    private let field = CurlNoiseField()

    var body: some View {
        Canvas { ctx, size in
            step(now: time)
            draw(ctx: ctx, size: size)
        }
        .onAppear { if mode == .audio { audio.retain() } }
        .onDisappear { if mode == .audio { audio.release() } }
    }

    // MARK: - Simulation

    private func drivers() -> SwarmDrivers {
        switch mode {
        case .swarm:
            return .idle(time: time)
        case .audio:
            return audio.isDenied ? .idle(time: time) : SwarmDrivers(from: audio.currentLevels)
        }
    }

    private func step(now: Double) {
        let sys = state.system
        // Skip if this is a repeat draw at the same clock value (sizing pass).
        guard now != state.lastTime else { return }
        let dt = state.lastTime == nil ? 1.0 / 60 : now - state.lastTime!
        state.lastTime = now
        sys.step(rawDt: dt, drivers: drivers(), field: field, time: now)
    }

    // MARK: - Rendering

    private func draw(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.03)))
        let d = drivers()
        let sys = state.system
        let w = size.width, h = size.height
        let base = color.color, hot = accent.color

        // Two brightness tiers batched into one Path each, filled once — drawing
        // thousands of particles individually would be far too slow.
        var dim = Path()
        var bright = Path()
        var brightPts: [(CGPoint, CGFloat, CGVector)] = []

        for i in 0..<sys.count {
            let p = sys.positions[i]
            let v = sys.velocities[i]
            let px = p.x * w, py = p.y * h
            let seed = sys.seeds[i]
            let sz = CGFloat(1.1 + seed * 1.8 + d.energy * 2.2)
            // Velocity-aligned streak (fish body).
            let vlen = CGFloat((Double(v.dx) * Double(v.dx) + Double(v.dy) * Double(v.dy)).squareRoot())
            let streak = min(CGFloat(6 + d.energy * 10), vlen * 60)
            let dir = vlen > 1e-6 ? CGVector(dx: v.dx / CGFloat(vlen), dy: v.dy / CGFloat(vlen)) : CGVector(dx: 1, dy: 0)
            let tail = CGPoint(x: px - dir.dx * streak, y: py - dir.dy * streak)

            let isBright = seed > 0.82
            if isBright {
                brightPts.append((CGPoint(x: px, y: py), sz, CGVector(dx: tail.x, dy: tail.y)))
                bright.move(to: tail)
                bright.addLine(to: CGPoint(x: px, y: py))
            } else {
                dim.addEllipse(in: CGRect(x: px - sz / 2, y: py - sz / 2, width: sz, height: sz))
                if streak > 2 {
                    dim.move(to: tail)
                    dim.addLine(to: CGPoint(x: px, y: py))
                }
            }
        }

        let mix = d.colorMix
        let particleColor = base.opacity(0.85 * d.brightness)
        ctx.stroke(dim, with: .color(particleColor), lineWidth: 1.4)
        ctx.fill(dim, with: .color(particleColor))

        // Bright tier: additive glow using the accent, blended by colorMix.
        let glowColor = blend(base, hot, mix)
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 4))
            layer.blendMode = .plusLighter
            layer.stroke(bright, with: .color(glowColor.opacity(0.9 * d.brightness)),
                         style: StrokeStyle(lineWidth: 3, lineCap: .round))
            for (c, sz, _) in brightPts {
                let r = sz + 1.5
                layer.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                           with: .color(glowColor.opacity(0.9 * d.brightness)))
            }
        }
    }

    private func blend(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let an = NSColor(a).usingColorSpace(.deviceRGB) ?? .white
        let bn = NSColor(b).usingColorSpace(.deviceRGB) ?? .white
        let f = CGFloat(min(max(t, 0), 1))
        return Color(red: Double(an.redComponent + (bn.redComponent - an.redComponent) * f),
                     green: Double(an.greenComponent + (bn.greenComponent - an.greenComponent) * f),
                     blue: Double(an.blueComponent + (bn.blueComponent - an.blueComponent) * f))
    }
}

/// Reference-type render state so the simulation survives view-body redraws
/// without `@State` value invalidation. Created once per `ParticleSwarmView`
/// instance (each window gets its own).
final class SwarmRenderState {
    let system = ParticleSwarmSystem(count: 1500)
    var lastTime: Double?
}
