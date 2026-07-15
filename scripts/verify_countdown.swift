// Run: swift scripts/verify_countdown.swift
// Renders the Countdown Timer effect at three regimes — (a) hours away,
// (b) ~5s away (pulsing giant seconds), and (c) past zero with the fireworks
// finale — mirroring CountdownView in CountdownView.swift (standalone scripts
// can't import the app module's internal views, so the renderer is mirrored
// inline). Writes PNGs to /tmp and asserts each frame is non-blank and that the
// three frames differ (different text / finale). "Now" is reconstructed from
// the shared clock via Date(timeIntervalSinceReferenceDate:), exactly like the
// app — the target is set relative to the chosen `time` so `remaining` lands in
// each regime.
import AppKit
import SwiftUI

// MARK: - Mirror of CountdownView (color/accent as SwiftUI Color)

struct CountdownFrame: View {
    let time: Double
    let target: Date
    let label: String
    let finale: Bool
    let color: Color
    let accent: Color

    private let finaleWindow: Double = 20

    var body: some View {
        let now = Date(timeIntervalSinceReferenceDate: time)
        let remaining = target.timeIntervalSince(now)
        let clamped = max(0, remaining)
        let sinceZero = -remaining

        GeometryReader { geo in
            let base = min(geo.size.width, geo.size.height)
            ZStack {
                Color.black
                if finale && sinceZero >= 0 && sinceZero <= finaleWindow {
                    Canvas { ctx, size in
                        drawFinale(ctx: ctx, size: size, sinceZero: sinceZero)
                    }
                }
                VStack(spacing: base * 0.05) {
                    digits(remaining: clamped, base: base)
                    if !label.isEmpty {
                        Text(label)
                            .font(.system(size: base * 0.08, weight: .semibold, design: .rounded))
                            .foregroundStyle(accent)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .frame(width: 640, height: 400)
    }

    @ViewBuilder
    private func digits(remaining: Double, base: CGFloat) -> some View {
        let total = Int(remaining)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        if remaining <= 0 {
            Text("00:00:00")
                .font(.system(size: base * 0.17, weight: .heavy, design: .monospaced))
                .foregroundStyle(color)
        } else if remaining > 86_400 {
            Text(String(format: "%dd %02dh %02dm %02ds", days, hours, minutes, secs))
                .font(.system(size: base * 0.13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        } else if remaining >= 3_600 {
            Text(String(format: "%d:%02d:%02d", hours, minutes, secs))
                .font(.system(size: base * 0.19, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        } else if remaining >= 600 {
            Text(String(format: "%02d:%02d", minutes, secs))
                .font(.system(size: base * 0.28, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        } else if remaining >= 10 {
            Text(String(format: "%d:%02d", minutes, secs))
                .font(.system(size: base * 0.34, weight: .heavy, design: .monospaced))
                .foregroundStyle(color)
        } else {
            let frac = remaining - floor(remaining)
            let shown = Int(ceil(remaining))
            let pulse = 1.0 + 0.35 * frac
            Text("\(max(1, shown))")
                .font(.system(size: base * 0.6, weight: .black, design: .rounded))
                .foregroundStyle(color)
                .scaleEffect(pulse)
        }
    }

    private func hash01(_ seed: Int, _ salt: Int) -> Double {
        let v = sin(Double(seed) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return v - floor(v)
    }

    private func drawFinale(ctx: GraphicsContext, size: CGSize, sinceZero: Double) {
        let minDim = min(size.width, size.height)
        let burstLife = 1.7
        let cadence = 0.55
        let launched = Int(sinceZero / cadence) + 1
        ctx.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.addFilter(.blur(radius: 1.5))
            for b in 0..<launched {
                let launchT = Double(b) * cadence + (hash01(b, 1) - 0.5) * cadence * 0.6
                let age = sinceZero - launchT
                guard age >= 0, age <= burstLife else { continue }
                let cx = (0.12 + 0.76 * hash01(b, 2)) * size.width
                let cy = (0.10 + 0.55 * hash01(b, 3)) * size.height
                let hue = hash01(b, 4)
                let sparkColor = Color(hue: hue, saturation: 0.85, brightness: 1)
                let count = 22 + Int(hash01(b, 5) * 12)
                let reach = minDim * (0.18 + 0.12 * hash01(b, 6))
                let lifeFrac = age / burstLife
                let fade = (1 - lifeFrac) * (1 - lifeFrac)
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

// MARK: - Harness

func stats(_ image: NSImage) -> (lit: Int, signature: [Int]) {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return (0, []) }
    var lit = 0
    var sig = [Int](repeating: 0, count: 16)   // coarse 4x4 luminance buckets
    let cols = 4, rows = 4
    for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
            if lum > 0.08 {
                lit += 1
                let bx = min(cols - 1, x * cols / rep.pixelsWide)
                let by = min(rows - 1, y * rows / rep.pixelsHigh)
                sig[by * cols + bx] += 1
            }
        }
    }
    return (lit, sig)
}

func render(time: Double, target: Date, label: String, finale: Bool, path: String) -> (lit: Int, signature: [Int]) {
    var out: (Int, [Int]) = (0, [])
    MainActor.assumeIsolated {
        let view = CountdownFrame(time: time, target: target, label: label, finale: finale,
                                  color: Color(red: 0.2, green: 0.9, blue: 1.0),
                                  accent: Color(red: 1.0, green: 0.8, blue: 0.2))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage else { print("FAIL: no image for \(path)"); return }
        out = stats(img)
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) (lit pixels: \(out.0))")
        }
    }
    return out
}

// Chosen render clock (arbitrary wall-clock seconds since reference date).
let t: Double = 780_000_000

// (a) hours away: target = now + 3h15m20s  → "3:15:20"
let hoursAway = render(time: t, target: Date(timeIntervalSinceReferenceDate: t + 3 * 3600 + 15 * 60 + 20),
                       label: "New Year", finale: true, path: "/tmp/countdown_hours.png")
// (b) ~5s away: giant pulsing seconds.
let secondsAway = render(time: t, target: Date(timeIntervalSinceReferenceDate: t + 5.4),
                         label: "New Year", finale: true, path: "/tmp/countdown_5s.png")
// (c) past zero: 3s into the finale window.
let pastZero = render(time: t, target: Date(timeIntervalSinceReferenceDate: t - 3.0),
                      label: "Happy New Year!", finale: true, path: "/tmp/countdown_finale.png")

precondition(hoursAway.lit > 0, "hours-away frame should be non-blank")
precondition(secondsAway.lit > 0, "~5s frame should be non-blank")
precondition(pastZero.lit > 0, "past-zero finale frame should be non-blank")

func differ(_ a: [Int], _ b: [Int]) -> Bool {
    guard a.count == b.count, !a.isEmpty else { return true }
    var diff = 0
    for i in a.indices { diff += abs(a[i] - b[i]) }
    let total = a.reduce(0, +) + b.reduce(0, +)
    return total == 0 ? false : Double(diff) / Double(total) > 0.05
}

precondition(differ(hoursAway.signature, secondsAway.signature), "hours-away and ~5s frames should differ")
precondition(differ(secondsAway.signature, pastZero.signature), "~5s and finale frames should differ")
precondition(differ(hoursAway.signature, pastZero.signature), "hours-away and finale frames should differ")

print("PASS: three regimes render non-blank and differ (hours=\(hoursAway.lit), 5s=\(secondsAway.lit), finale=\(pastZero.lit))")
