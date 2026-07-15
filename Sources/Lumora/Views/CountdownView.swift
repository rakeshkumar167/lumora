import SwiftUI
import LumoraKit

/// Countdown Timer: big styled digits counting down to a configurable target
/// date/time, with a self-contained fireworks finale at zero. Like the other
/// clock effects it reconstructs "now" from the shared animation clock
/// (`Date(timeIntervalSinceReferenceDate: time)`) rather than calling `Date()`
/// directly, so the display stays locked to the render timeline.
///
/// The digit format adapts to how much time is left (days → hours → minutes →
/// a pulsing giant seconds countdown). At/after zero it shows "00:00:00" and
/// the caption; if `config.finale` is on, a burst of fireworks plays for the
/// first ~20s past zero behind the text. The fireworks here are a private,
/// deterministic particle burst — NOT the shipping Fireworks effect — so this
/// view can't regress it.
struct CountdownView: View {
    let color: RGBAColor
    let accent: RGBAColor
    let time: Double
    var config: CountdownConfig? = nil

    /// Seconds after zero during which the finale plays.
    private let finaleWindow: Double = 20

    var body: some View {
        let cfg = config ?? CountdownConfig()
        let now = Date(timeIntervalSinceReferenceDate: time)
        let remaining = cfg.target.timeIntervalSince(now)   // may be negative past zero
        let clamped = max(0, remaining)
        let sinceZero = -remaining                          // >0 once past target

        GeometryReader { geo in
            let base = min(geo.size.width, geo.size.height)
            ZStack {
                Color.black
                // Finale fireworks behind the text.
                if cfg.finale && sinceZero >= 0 && sinceZero <= finaleWindow {
                    Canvas { ctx, size in
                        drawFinale(ctx: ctx, size: size, sinceZero: sinceZero)
                    }
                }
                VStack(spacing: base * 0.05) {
                    digits(remaining: clamped, base: base)
                    if !cfg.label.isEmpty {
                        Text(cfg.label)
                            .font(.system(size: base * 0.08, weight: .semibold, design: .rounded))
                            .foregroundStyle(accent.color)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .background(Color.black)
    }

    // MARK: - Digits

    @ViewBuilder
    private func digits(remaining: Double, base: CGFloat) -> some View {
        let total = Int(remaining)          // whole seconds remaining
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60

        if remaining <= 0 {
            // At/after zero.
            Text("00:00:00")
                .font(.system(size: base * 0.17, weight: .heavy, design: .monospaced))
                .foregroundStyle(color.color)
        } else if remaining > 86_400 {
            // More than a day away.
            Text(String(format: "%dd %02dh %02dm %02ds", days, hours, minutes, secs))
                .font(.system(size: base * 0.13, weight: .bold, design: .monospaced))
                .foregroundStyle(color.color)
        } else if remaining >= 3_600 {
            // 1h … 24h.
            Text(String(format: "%d:%02d:%02d", hours, minutes, secs))
                .font(.system(size: base * 0.19, weight: .bold, design: .monospaced))
                .foregroundStyle(color.color)
        } else if remaining >= 600 {
            // 10min … 1h.
            Text(String(format: "%02d:%02d", minutes, secs))
                .font(.system(size: base * 0.28, weight: .bold, design: .monospaced))
                .foregroundStyle(color.color)
        } else if remaining >= 10 {
            // < 10min: big M:SS.
            Text(String(format: "%d:%02d", minutes, secs))
                .font(.system(size: base * 0.34, weight: .heavy, design: .monospaced))
                .foregroundStyle(color.color)
        } else {
            // < 10s: giant whole seconds that pulse on each new second.
            // `frac` runs 1 → 0 across each second (largest right after a tick).
            let frac = remaining - floor(remaining)
            let shown = Int(ceil(remaining))          // 10,9,…,1
            let pulse = 1.0 + 0.35 * frac
            Text("\(max(1, shown))")
                .font(.system(size: base * 0.6, weight: .black, design: .rounded))
                .foregroundStyle(color.color)
                .scaleEffect(pulse)
                .shadow(color: accent.color.opacity(0.7), radius: base * 0.04)
        }
    }

    // MARK: - Self-contained fireworks finale

    /// Deterministic pseudo-random in 0…1 from an integer seed + salt.
    private func hash01(_ seed: Int, _ salt: Int) -> Double {
        let v = sin(Double(seed) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return v - floor(v)
    }

    /// Draws celebratory fireworks bursts across the finale window. Bursts are
    /// spawned on a rough cadence; each expands radially with gravity + fade.
    /// Entirely local to this view (does not touch the shipping Fireworks).
    private func drawFinale(ctx: GraphicsContext, size: CGSize, sinceZero: Double) {
        let minDim = min(size.width, size.height)
        let burstLife = 1.7               // seconds a burst stays visible
        let cadence = 0.55                // avg seconds between burst launches
        // How many bursts could have launched by now (a few overlap at once).
        let launched = Int(sinceZero / cadence) + 1

        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.addFilter(.blur(radius: 1.5))
            for b in 0..<launched {
                let launchT = Double(b) * cadence + (hash01(b, 1) - 0.5) * cadence * 0.6
                let age = sinceZero - launchT
                guard age >= 0, age <= burstLife else { continue }

                // Burst center: spread across the upper ~65% of the frame.
                let cx = (0.12 + 0.76 * hash01(b, 2)) * size.width
                let cy = (0.10 + 0.55 * hash01(b, 3)) * size.height
                let hue = hash01(b, 4)
                let sparkColor = Color(hue: hue, saturation: 0.85, brightness: 1)

                let count = 22 + Int(hash01(b, 5) * 12)
                let reach = minDim * (0.18 + 0.12 * hash01(b, 6))
                let lifeFrac = age / burstLife
                let fade = (1 - lifeFrac) * (1 - lifeFrac)
                // Ease-out radial expansion.
                let spread = reach * (1 - pow(1 - lifeFrac, 2.2))
                let gravity = minDim * 0.5 * lifeFrac * lifeFrac

                for p in 0..<count {
                    let ang = Double(p) / Double(count) * 2 * .pi + hash01(b, 7) * 2 * .pi
                    let jitter = 0.6 + 0.4 * hash01(b &* 31 &+ p, 8)
                    let r = spread * jitter
                    let x = cx + cos(ang) * r
                    let y = cy + sin(ang) * r + gravity
                    let dotR = minDim * 0.012 * (0.6 + 0.6 * fade)
                    guard fade > 0.02 else { continue }
                    layer.fill(
                        Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)),
                        with: .color(sparkColor.opacity(fade))
                    )
                }
                // Bright flash core early in the burst.
                if lifeFrac < 0.25 {
                    let fr = minDim * 0.03 * (1 - lifeFrac / 0.25)
                    layer.fill(
                        Path(ellipseIn: CGRect(x: cx - fr, y: cy - fr, width: fr * 2, height: fr * 2)),
                        with: .color(.white.opacity(0.8 * (1 - lifeFrac / 0.25)))
                    )
                }
            }
        }
    }
}
