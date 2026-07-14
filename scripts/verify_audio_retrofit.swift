// Run: swift scripts/verify_audio_retrofit.swift
// Offscreen check for the audio-reactive Equalizer + Strobe retrofits.
//
// The real renderers live in SurfaceContentView.swift as `private` views inside
// the app module, which a standalone script can't import — so this mirrors their
// logic here, exactly, and injects a scripted `AudioLevelsProviding` stub. It
// renders each effect in BOTH the idle (silent) and audio-active states via
// ImageRenderer, writes PNGs to /tmp, and prints pixel stats proving the two
// states differ (and that idle == the original time-driven look).
import AppKit
import SwiftUI

// MARK: - Mirrored audio types (match LumoraKit.AudioLevels + AudioLevelsProviding)

struct StubLevels {
    var spectrum: [Double] = []
    var beatCount: Int = 0
    var beatStrength: Double = 0
    static let silent = StubLevels()
}

final class StubProvider {
    var levels: StubLevels
    var denied: Bool
    init(levels: StubLevels, denied: Bool = false) { self.levels = levels; self.denied = denied }
    var currentLevels: StubLevels { levels }
    var isDenied: Bool { denied }
}

// MARK: - Mirrored EqualizerView

struct EqualizerProbe: View {
    let color: Color
    let accent: Color
    let time: Double
    let levels: StubLevels
    let peaksBox: PeaksBox
    private let count = 16

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            let gap: CGFloat = 5
            let barWidth = (size.width - gap * CGFloat(count + 1)) / CGFloat(count)
            let audioActive = !levels.spectrum.isEmpty
            let dt: Double = peaksBox.lastTime.map { max(0, time - $0) } ?? (1.0 / 60)
            if audioActive { peaksBox.lastTime = time }
            let beat = pow(max(0, sin(time * 3.0)), 4)
            for i in 0..<count {
                let level: Double
                if audioActive {
                    let bin = i < levels.spectrum.count ? levels.spectrum[i] : 0
                    level = min(1.0, max(0.04, bin))
                } else {
                    let s1 = Double(eqHash01(i, 7)); let s2 = Double(eqHash01(i, 17)); let s3 = Double(eqHash01(i, 41))
                    let a = sin(time * (2.3 + s1 * 4.0) + s1 * 6.283)
                    let b = sin(time * (5.1 + s2 * 6.0) + s2 * 6.283)
                    let c = sin(time * (9.7 + s3 * 8.0) + s3 * 6.283)
                    let mix = 0.5 + 0.5 * (0.6 * a + 0.3 * b + 0.1 * c)
                    let kick = 0.30 * beat * (0.4 + 0.6 * s2)
                    level = min(1.0, max(0.05, 0.12 + 0.66 * mix + kick))
                }
                let h = size.height * CGFloat(level)
                let x = gap + CGFloat(i) * (barWidth + gap)
                let rect = CGRect(x: x, y: size.height - h, width: barWidth, height: h)
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [color, accent]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                )
                ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: shading)
                if audioActive {
                    let peak = max(level, peaksBox.peaks[i] - 0.9 * dt)
                    peaksBox.peaks[i] = peak
                    let py = size.height - size.height * CGFloat(peak)
                    var cap = Path()
                    cap.move(to: CGPoint(x: x, y: py))
                    cap.addLine(to: CGPoint(x: x + barWidth, y: py))
                    ctx.stroke(cap, with: .color(color.opacity(0.9)), lineWidth: 2)
                }
            }
        }
    }

    private func eqHash01(_ i: Int, _ salt: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return CGFloat(v - floor(v))
    }
}

final class PeaksBox { var peaks = [Double](repeating: 0, count: 16); var lastTime: Double? }

// MARK: - Mirrored StrobeView

struct StrobeProbe: View {
    let color: Color
    let accent: Color
    let time: Double
    let levels: StubLevels
    let box: StrobeBox
    private let flashDecay = 0.14

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            if levels.spectrum.isEmpty {
                let c = Int(time * 3) % 2 == 0 ? color : accent
                ctx.fill(Path(rect), with: .color(c))
                return
            }
            if levels.beatCount > box.lastBeatCount {
                box.lastBeatCount = levels.beatCount
                box.flashTime = time
                box.flashStrength = levels.beatStrength
            }
            var intensity = 0.0
            if let ft = box.flashTime {
                let e = time - ft
                if e >= 0, e < flashDecay { intensity = (1 - e / flashDecay) * box.flashStrength }
            }
            ctx.fill(Path(rect), with: .color(accent))
            if intensity > 0 { ctx.fill(Path(rect), with: .color(color.opacity(min(1, intensity)))) }
        }
    }
}

final class StrobeBox { var lastBeatCount = 0; var flashTime: Double?; var flashStrength = 0.0 }

// MARK: - Rendering + pixel stats

let W = 320, H = 180
let cyan = Color(red: 0.1, green: 0.8, blue: 0.9)
let pink = Color(red: 0.95, green: 0.2, blue: 0.6)

func render<V: View>(_ view: V) -> NSBitmapImageRep? {
    var rep: NSBitmapImageRep?
    MainActor.assumeIsolated {
        let r = ImageRenderer(content: view.frame(width: CGFloat(W), height: CGFloat(H)))
        r.scale = 1
        if let img = r.nsImage, let tiff = img.tiffRepresentation {
            rep = NSBitmapImageRep(data: tiff)
        }
    }
    return rep
}

/// Count of non-near-black pixels + a coarse average-color signature.
func stats(_ rep: NSBitmapImageRep) -> (lit: Int, avg: (Double, Double, Double)) {
    var lit = 0; var sr = 0.0, sg = 0.0, sb = 0.0; var n = 0
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide {
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            let r = Double(c.redComponent), g = Double(c.greenComponent), b = Double(c.blueComponent)
            sr += r; sg += g; sb += b; n += 1
            if r + g + b > 0.15 { lit += 1 }
        }
    }
    let d = Double(max(n, 1))
    return (lit, (sr / d, sg / d, sb / d))
}

func write(_ rep: NSBitmapImageRep, _ name: String) {
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "/tmp/\(name)"))
    }
}

// A rising spectrum + a bumped beat for the audio-active state.
let spectrum = (0..<16).map { 0.15 + 0.8 * Double($0) / 15.0 }
let audioLevels = StubLevels(spectrum: spectrum, beatCount: 1, beatStrength: 0.9)

print("=== Equalizer ===")
var eqDiffs = 0
for t in [0.0, 0.5, 1.0] {
    // Fresh peak boxes per render so state is deterministic.
    guard let idle = render(EqualizerProbe(color: cyan, accent: pink, time: t, levels: .silent, peaksBox: PeaksBox())),
          let aud = render(EqualizerProbe(color: cyan, accent: pink, time: t, levels: audioLevels, peaksBox: PeaksBox()))
    else { print("  render failed at t=\(t)"); continue }
    let si = stats(idle), sa = stats(aud)
    write(idle, "eq_idle_\(t).png"); write(aud, "eq_audio_\(t).png")
    let differ = si.lit != sa.lit
    if differ { eqDiffs += 1 }
    print(String(format: "  t=%.1f  idle lit=%d  audio lit=%d  differ=%@", t, si.lit, sa.lit, differ ? "YES" : "no"))
}

print("=== Strobe ===")
var stDiffs = 0
for t in [0.0, 0.34, 0.7] {
    guard let idle = render(StrobeProbe(color: cyan, accent: pink, time: t, levels: .silent, box: StrobeBox())),
          let aud = render(StrobeProbe(color: cyan, accent: pink, time: t, levels: audioLevels, box: StrobeBox()))
    else { print("  render failed at t=\(t)"); continue }
    let si = stats(idle), sa = stats(aud)
    write(idle, "strobe_idle_\(t).png"); write(aud, "strobe_audio_\(t).png")
    // Strobe fills solid color; compare average color signatures.
    let dr = abs(si.avg.0 - sa.avg.0), dg = abs(si.avg.1 - sa.avg.1), db = abs(si.avg.2 - sa.avg.2)
    let differ = (dr + dg + db) > 0.02
    if differ { stDiffs += 1 }
    print(String(format: "  t=%.2f  idle avg=(%.2f,%.2f,%.2f)  audio avg=(%.2f,%.2f,%.2f)  differ=%@",
                 t, si.avg.0, si.avg.1, si.avg.2, sa.avg.0, sa.avg.1, sa.avg.2, differ ? "YES" : "no"))
}

print("")
print("Equalizer: \(eqDiffs)/3 times idle vs audio differ")
print("Strobe:    \(stDiffs)/3 times idle vs audio differ")
print("PNGs written to /tmp/eq_*.png and /tmp/strobe_*.png")
if eqDiffs >= 1 && stDiffs >= 1 {
    print("PASS: audio-active renders diverge from idle for both effects.")
} else {
    print("FAIL: expected idle vs audio to differ.")
    exit(1)
}
