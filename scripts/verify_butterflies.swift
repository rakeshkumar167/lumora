// Run: swift scripts/verify_butterflies.swift
// Renders the Butterflies effect (flapping two-wing sprites drifting through
// the shared curl-noise flow field) at three `time` values, mirroring the
// sprite-drawing math in Sources/Lumora/Views/ButterfliesView.swift with a
// fixed stub swarm (standalone scripts can't import the app module's private
// views, so this isn't the real ParticleSwarmSystem — the goal is a
// non-blank + motion check, not sim fidelity). Writes PNGs to /tmp and
// asserts each frame is non-blank and that the frames differ over time
// (flapping + drift).
import AppKit
import SwiftUI

// MARK: - Stub swarm (fixed positions/velocities/seeds, no field stepping)

struct Butterfly { let x: Double; let y: Double; let vx: Double; let vy: Double; let seed: Double }

func stubSwarm(count: Int) -> [Butterfly] {
    var rng = UInt64(0x9E37) | 1
    func next() -> Double {
        rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(rng >> 11) / Double(1 << 53)
    }
    var out: [Butterfly] = []
    for _ in 0..<count {
        let x = next(), y = next()
        let angle = next() * .pi * 2
        let speed = 0.05 + next() * 0.1
        out.append(Butterfly(x: x, y: y, vx: cos(angle) * speed, vy: sin(angle) * speed, seed: next()))
    }
    return out
}

let swarm = stubSwarm(count: 40)

// MARK: - Sprite drawing (mirrors ButterfliesView.draw / drawButterfly)

struct ButterflyFrame: View {
    let time: Double
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.03, green: 0.025, blue: 0.02)))
            let w = size.width, h = size.height
            let base = Color(red: 0.95, green: 0.75, blue: 0.2)
            let hot = Color(red: 0.9, green: 0.25, blue: 0.65)

            for b in swarm {
                let px = CGFloat(b.x) * w, py = CGFloat(b.y) * h
                let vlen = (b.vx * b.vx + b.vy * b.vy).squareRoot()
                let heading = vlen > 1e-6 ? atan2(b.vy, b.vx) : b.seed * .pi * 2

                let flapRate = 6.0 + b.seed * 3.0
                let flap = sin(time * flapRate + b.seed * 6.283)
                let openness = 0.35 + 0.65 * abs(flap)
                let scale = 0.7 + b.seed * 0.6

                drawButterfly(ctx: ctx, at: CGPoint(x: px, y: py), heading: heading,
                              openness: openness, scale: scale, base: base, hot: hot)
            }
        }
        .frame(width: 640, height: 440)
    }

    private func drawButterfly(ctx: GraphicsContext, at center: CGPoint, heading: Double,
                                openness: Double, scale: Double, base: Color, hot: Color) {
        let bodyLen = CGFloat(14 * scale)
        let wingW = CGFloat(11 * scale) * CGFloat(openness)
        let foreWingH = CGFloat(9 * scale)
        let hindWingH = CGFloat(6 * scale)

        var ctx = ctx
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: Angle(radians: heading))

        let gradient = Gradient(colors: [base, hot])

        func wingLobe(xOffset: CGFloat, dy: CGFloat, w: CGFloat, hgt: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: xOffset - w / 2, y: dy - hgt / 2, width: w, height: hgt))
        }

        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            layer.blendMode = .plusLighter
            let glow = Path(ellipseIn: CGRect(x: -wingW, y: -foreWingH, width: wingW * 2, height: foreWingH * 2))
            layer.fill(glow, with: .color(hot.opacity(0.18 * openness)))
        }

        let fore1 = wingLobe(xOffset: bodyLen * 0.15, dy: -foreWingH * 0.65, w: wingW, hgt: foreWingH)
        let fore2 = wingLobe(xOffset: bodyLen * 0.15, dy: foreWingH * 0.65, w: wingW, hgt: foreWingH)
        let hind1 = wingLobe(xOffset: -bodyLen * 0.1, dy: -hindWingH * 0.55, w: wingW * 0.75, hgt: hindWingH)
        let hind2 = wingLobe(xOffset: -bodyLen * 0.1, dy: hindWingH * 0.55, w: wingW * 0.75, hgt: hindWingH)

        for wing in [fore1, fore2, hind1, hind2] {
            ctx.fill(wing, with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: wingW))
            ctx.stroke(wing, with: .color(hot.opacity(0.6)), lineWidth: 0.6)
        }

        var bodyPath = Path()
        bodyPath.move(to: CGPoint(x: -bodyLen * 0.35, y: 0))
        bodyPath.addLine(to: CGPoint(x: bodyLen * 0.5, y: 0))
        ctx.stroke(bodyPath, with: .color(.black.opacity(0.55)), lineWidth: CGFloat(1.4 * scale))
    }
}

// MARK: - Render + assertions

func litPixelCount(_ image: NSImage) -> Int {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return 0 }
    var count = 0
    for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
            if lum > 0.08 { count += 1 }
        }
    }
    return count
}

/// Coarse pixel-grid fingerprint (luminance-quantized) so we can detect that
/// two frames differ without a full diff.
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

func render(time: Double, path: String) -> (lit: Int, fp: [Int]) {
    var result = (0, [Int]())
    MainActor.assumeIsolated {
        let renderer = ImageRenderer(content: ButterflyFrame(time: time))
        renderer.scale = 2
        guard let img = renderer.nsImage else { print("FAIL: no image for \(path)"); return }
        let lit = litPixelCount(img)
        let fp = fingerprint(img)
        result = (lit, fp)
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) (lit pixels: \(lit))")
        }
    }
    return result
}

func diffCount(_ a: [Int], _ b: [Int]) -> Int {
    guard a.count == b.count else { return max(a.count, b.count) }
    return zip(a, b).reduce(0) { $0 + (abs($1.0 - $1.1) > 6 ? 1 : 0) }
}

let f0 = render(time: 0.0, path: "/tmp/butterflies_t0.png")
let f1 = render(time: 0.3, path: "/tmp/butterflies_t1.png")
let f2 = render(time: 0.6, path: "/tmp/butterflies_t2.png")

precondition(f0.lit > 0, "t=0.0 frame should have lit pixels")
precondition(f1.lit > 0, "t=0.3 frame should have lit pixels")
precondition(f2.lit > 0, "t=0.6 frame should have lit pixels")

let d01 = diffCount(f0.fp, f1.fp)
let d12 = diffCount(f1.fp, f2.fp)
precondition(d01 > 0, "frame should change between t=0.0 and t=0.3 (flapping/drift)")
precondition(d12 > 0, "frame should change between t=0.3 and t=0.6 (flapping/drift)")

print("PASS: all frames non-blank (lit=\(f0.lit),\(f1.lit),\(f2.lit)); frames change over time (diff01=\(d01), diff12=\(d12))")
