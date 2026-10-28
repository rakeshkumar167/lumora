import LumoraKit
import SwiftUI

/// A ball dropped from the top edge that bounces on the bottom edge, losing
/// speed with every bounce until it comes to rest, then fades and drops again.
///
/// Stateless and analytic (driven by the global clock): the fall takes `fall`
/// seconds, each bounce keeps `restitution` of the impact speed, so bounce `i`
/// lasts `2 * fall * e^i` and reaches `e^(2i)` of the drop height. The ball
/// squashes on impact, casts a contact shadow and leaves a faint motion trail.
struct BouncingBallView: View {
    let time: Double
    let color: RGBAColor

    private let fall = 1.1           // seconds for the initial drop
    private let restitution = 0.72   // speed kept per bounce
    private let bounces = 12         // after this the ball is at rest
    private let rest = 1.4           // seconds resting before the fade
    private let fade = 0.5           // seconds fading out / in

    /// Seconds from release until the ball settles.
    private var settle: Double {
        var t = fall
        for i in 1...bounces { t += 2 * fall * pow(restitution, Double(i)) }
        return t
    }

    /// Height above the floor as a fraction of the drop height (1 = top edge),
    /// plus impact squash (0…1) at local time `t` since release.
    private func state(at t: Double) -> (height: Double, squash: Double) {
        if t <= 0 { return (1, 0) }
        if t < fall {
            let u = t / fall
            return (1 - u * u, squashNear(t, impact: fall, speed: 1))
        }
        var start = fall
        for i in 1...bounces {
            let v = pow(restitution, Double(i))          // launch speed / impact speed of drop
            let dur = 2 * fall * v
            if t < start + dur {
                let u = (t - start) / fall                    // time in units of the drop
                let h = 2 * v * u - u * u                     // ballistic arc, peak v²
                let s = max(squashNear(t, impact: start, speed: v), squashNear(t, impact: start + dur, speed: v * restitution))
                return (max(0, h), s)
            }
            start += dur
        }
        return (0, 0)
    }

    private func squashNear(_ t: Double, impact: Double, speed: Double) -> Double {
        let window = 0.07
        let d = abs(t - impact)
        return d < window ? (1 - d / window) * speed : 0
    }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            // Backdrop: deep gradient with a soft floor.
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(
                Gradient(colors: [Color(red: 0.03, green: 0.04, blue: 0.09), Color(red: 0.08, green: 0.09, blue: 0.16)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            let floorY = h - max(4, h * 0.02)
            ctx.fill(Path(CGRect(x: 0, y: floorY, width: w, height: h - floorY)),
                     with: .color(Color.white.opacity(0.06)))
            ctx.fill(Path(CGRect(x: 0, y: floorY, width: w, height: 1.5)), with: .color(Color.white.opacity(0.18)))

            let r = max(6, min(w, h) * 0.075)
            let drop = floorY - 2 * r                       // ball centre travels from r to floorY - r
            guard drop > 0 else { return }
            let cycle = settle + rest + fade * 2
            let phase = time.truncatingRemainder(dividingBy: cycle)
            let t = phase - fade                             // fade in above the top edge first
            let alpha: Double = phase < fade ? phase / fade
                : (phase > cycle - fade ? (cycle - phase) / fade : 1)
            let cx = w / 2
            let base = color.color

            // Motion trail: faded copies a few milliseconds back while moving fast.
            for k in stride(from: 4, through: 1, by: -1) {
                let past = state(at: t - Double(k) * 0.018)
                let now = state(at: t)
                guard abs(now.height - past.height) * drop > r * 0.25 else { continue }
                let y = floorY - r - past.height * drop
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: y - r, width: 2 * r, height: 2 * r)),
                         with: .color(base.opacity(alpha * 0.10 * Double(5 - k) / 4)))
            }

            let s = state(at: t)
            let squash = s.squash * 0.32
            let sy = 1 - squash, sx = 1 + squash * 0.75
            let cy = floorY - r * sy - s.height * drop

            // Contact shadow: tighter and darker as the ball nears the floor.
            let near = 1 - s.height
            let shW = r * 2 * (0.55 + 0.6 * near) * sx
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: r * 0.25))
                l.fill(Path(ellipseIn: CGRect(x: cx - shW / 2, y: floorY - r * 0.12, width: shW, height: r * 0.3)),
                       with: .color(Color.black.opacity(alpha * (0.15 + 0.5 * near))))
            }
            // The ball's colour glowing on the floor (reads on a dark projection).
            let glowW = r * 2 * (0.9 + 1.4 * near)
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: r * 0.45))
                l.blendMode = .plusLighter
                l.fill(Path(ellipseIn: CGRect(x: cx - glowW / 2, y: floorY - r * 0.18, width: glowW, height: r * 0.42)),
                       with: .color(base.opacity(alpha * (0.08 + 0.45 * near * near))))
            }

            // The ball: shaded sphere with rim darkening and a specular highlight.
            let rect = CGRect(x: cx - r * sx, y: cy - r * sy, width: 2 * r * sx, height: 2 * r * sy)
            let ball = Path(ellipseIn: rect)
            ctx.opacity = alpha
            ctx.fill(ball, with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color.white.opacity(0.95), location: 0),
                    .init(color: base, location: 0.35),
                    .init(color: base.opacity(0.85), location: 0.75),
                    .init(color: Color.black.opacity(0.85), location: 1.0),
                ]),
                center: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.minY + rect.height * 0.32),
                startRadius: 0, endRadius: r * 1.9))
            // Soft bounce light from the floor on the underside.
            ctx.fill(ball, with: .linearGradient(
                Gradient(colors: [.clear, base.opacity(0.25)]),
                startPoint: CGPoint(x: cx, y: rect.midY), endPoint: CGPoint(x: cx, y: rect.maxY)))
            let hl = CGRect(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.16,
                            width: rect.width * 0.22, height: rect.height * 0.14)
            ctx.fill(Path(ellipseIn: hl), with: .color(Color.white.opacity(0.7)))
        }
    }
}
