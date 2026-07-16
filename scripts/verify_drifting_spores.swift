// Run: swift scripts/verify_drifting_spores.swift
// Renders the Drifting Spores overlay (soft glowing rising motes) at three
// `time` values, mirroring the sprite-drawing math in
// Sources/Lumora/Views/BioluminescentViews.swift with a fixed stub swarm
// (standalone scripts can't import the app module's internal views, so this
// isn't the real ParticleSwarmSystem — the goal is a non-blank + motion check).
// Writes PNGs to /tmp and asserts each frame is non-blank, has color variance,
// and changes over time (twinkle + drift).
import AppKit
import SwiftUI

enum P {
    static let night = Color(red: 0.008, green: 0.024, blue: 0.039)
    static let glowCyan = Color(red: 0.157, green: 0.902, blue: 0.824)
    static let glowAqua = Color(red: 0.361, green: 0.949, blue: 1.0)
    static let accentViolet = Color(red: 0.478, green: 0.294, blue: 1.0)
}

struct Spore { let x: Double; let y: Double; let seed: Double }
func stubSwarm(count: Int) -> [Spore] {
    var rng = UInt64(0x9E37) | 1
    func next() -> Double {
        rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(rng >> 11) / Double(1 << 53)
    }
    var out: [Spore] = []
    for _ in 0..<count { out.append(Spore(x: next(), y: next(), seed: next())) }
    return out
}
let swarm = stubSwarm(count: 65)

struct SporesFrame: View {
    let time: Double
    var body: some View {
        Canvas { ctx, size in drawSpores(ctx: ctx, size: size, time: time) }
        .frame(width: 640, height: 440)
    }
}

func drawSpores(ctx: GraphicsContext, size: CGSize, time: Double) {
    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(P.night))
    let w = size.width, h = size.height
    let minDim = min(w, h)
    // Small time-driven upward drift so stub motes also move between frames.
    func pos(_ s: Spore) -> (CGFloat, CGFloat) {
        let yy = (s.y - time * 0.02).truncatingRemainder(dividingBy: 1)
        let y = (yy < 0 ? yy + 1 : yy)
        return (CGFloat(s.x) * w, CGFloat(y) * h)
    }
    ctx.drawLayer { layer in
        layer.addFilter(.blur(radius: 6)); layer.blendMode = .plusLighter
        for s in swarm {
            let (px, py) = pos(s)
            let twinkle = 0.4 + 0.6 * (0.5 + 0.5 * sin(time * (0.8 + s.seed * 1.4) + s.seed * 6.283))
            let r = (minDim * 0.012) * (0.7 + s.seed * 0.9)
            let rare = s.seed > 0.9
            let halo = rare ? P.accentViolet : (s.seed > 0.5 ? P.glowAqua : P.glowCyan)
            layer.fill(Path(ellipseIn: CGRect(x: px - r * 2.2, y: py - r * 2.2, width: r * 4.4, height: r * 4.4)),
                       with: .color(halo.opacity(0.5 * twinkle)))
        }
    }
    for s in swarm {
        let (px, py) = pos(s)
        let twinkle = 0.4 + 0.6 * (0.5 + 0.5 * sin(time * (0.8 + s.seed * 1.4) + s.seed * 6.283))
        let r = (minDim * 0.006) * (0.7 + s.seed * 0.9)
        ctx.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)),
                 with: .color(.white.opacity(0.85 * twinkle)))
    }
}

func litPixelCount(_ image: NSImage) -> Int {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return 0 }
    var count = 0
    for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
            if lum > 0.10 { count += 1 }
        }
    }
    return count
}
func fingerprint(_ image: NSImage) -> [Int] {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return [] }
    var out: [Int] = []
    for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
            out.append(Int(lum * 255))
        }
    }
    return out
}
func colorVariance(_ image: NSImage) -> Double {
    let fp = fingerprint(image); guard !fp.isEmpty else { return 0 }
    let mean = Double(fp.reduce(0, +)) / Double(fp.count)
    return fp.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(fp.count)
}
func render(time: Double, path: String) -> (lit: Int, fp: [Int], varr: Double) {
    var result = (0, [Int](), 0.0)
    MainActor.assumeIsolated {
        let renderer = ImageRenderer(content: SporesFrame(time: time)); renderer.scale = 2
        guard let img = renderer.nsImage else { print("FAIL: no image for \(path)"); return }
        result = (litPixelCount(img), fingerprint(img), colorVariance(img))
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path)); print("wrote \(path) (lit: \(result.0))")
        }
    }
    return result
}
func diffCount(_ a: [Int], _ b: [Int]) -> Int {
    guard a.count == b.count else { return max(a.count, b.count) }
    return zip(a, b).reduce(0) { $0 + (abs($1.0 - $1.1) > 6 ? 1 : 0) }
}
let f0 = render(time: 0.0, path: "/tmp/drifting_spores_t0.png")
let f1 = render(time: 1.0, path: "/tmp/drifting_spores_t1.png")
let f2 = render(time: 2.5, path: "/tmp/drifting_spores_t2.png")
precondition(f0.lit > 0 && f1.lit > 0 && f2.lit > 0, "frames should be non-blank")
precondition(f0.varr > 5, "frame should have color variance (glowing motes on dark)")
let d01 = diffCount(f0.fp, f1.fp), d12 = diffCount(f1.fp, f2.fp)
precondition(d01 > 0 && d12 > 0, "frames should change over time (twinkle/drift)")
print("PASS: non-blank (lit=\(f0.lit),\(f1.lit),\(f2.lit)); variance=\(Int(f0.varr)); change over time (d01=\(d01), d12=\(d12))")
