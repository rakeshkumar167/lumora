// Run: swift scripts/verify_aquarium.swift
// Renders the Aquarium effect (schooling fish + swaying kelp + rising bubbles
// over a deep-water gradient) at three `time` values, mirroring the layered
// drawing in Sources/Lumora/Views/AquariumView.swift with a fixed stub swarm
// (standalone scripts can't import the app module's private views, so this
// isn't the real ParticleSwarmSystem — the goal is a non-blank + color-variance
// + motion check, not sim fidelity). Writes PNGs to /tmp and asserts each frame
// is non-blank, has non-trivial color variance (water + kelp + fish present),
// and that frames change over time (fish swim / bubbles rise / kelp sways).
import AppKit
import SwiftUI

// MARK: - Stub swarm (fixed positions/velocities/seeds, no field stepping)

struct Fish { let x: Double; let y: Double; let vx: Double; let vy: Double; let seed: Double }

func stubSwarm(count: Int) -> [Fish] {
    var rng = UInt64(0x9E37) | 1
    func next() -> Double {
        rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(rng >> 11) / Double(1 << 53)
    }
    var out: [Fish] = []
    for _ in 0..<count {
        let x = next(), y = next()
        let angle = next() * .pi * 2
        let speed = 0.08 + next() * 0.12
        out.append(Fish(x: x, y: y, vx: cos(angle) * speed, vy: sin(angle) * speed, seed: next()))
    }
    return out
}

let swarm = stubSwarm(count: 55)
let kelpX: [Double] = [0.16, 0.5, 0.83]
let bubbleX: [Double] = [0.27, 0.6, 0.88]

func hash01(_ i: Int, _ salt: Int) -> Double {
    let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
    return v - floor(v)
}

// MARK: - Scene drawing (mirrors AquariumView layers)

struct AquariumFrame: View {
    let time: Double
    var body: some View {
        Canvas { ctx, size in
            drawWater(ctx, size)
            drawKelp(ctx, size)
            drawFish(ctx, size)
            drawBubbles(ctx, size)
        }
        .frame(width: 640, height: 440)
    }

    func drawWater(_ ctx: GraphicsContext, _ size: CGSize) {
        let grad = Gradient(colors: [
            Color(red: 0.06, green: 0.30, blue: 0.40),
            Color(red: 0.02, green: 0.12, blue: 0.24),
            Color(red: 0.01, green: 0.03, blue: 0.10),
        ])
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(grad, startPoint: CGPoint(x: size.width / 2, y: 0),
                                       endPoint: CGPoint(x: size.width / 2, y: size.height)))
    }

    func drawKelp(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        for (k, bx) in kelpX.enumerated() {
            let phase = Double(k) * 2.1
            let strandH = h * (0.62 + 0.16 * hash01(k, 11))
            let baseW = min(w, h) * (0.03 + 0.012 * hash01(k, 12))
            let swaySpeed = 0.7 + 0.25 * hash01(k, 13)
            let swayAmp = min(w, h) * 0.05
            let segs = 22
            func centerline(_ t: Double) -> CGPoint {
                let y = h - CGFloat(t) * strandH
                let sway = sin(time * swaySpeed + t * 3.0 + phase) * swayAmp * CGFloat(t)
                return CGPoint(x: CGFloat(bx) * w + sway, y: y)
            }
            func width(_ t: Double) -> CGFloat { baseW * CGFloat(1 - t * 0.85) }
            var ribbon = Path()
            var pts: [CGPoint] = []
            for s in 0...segs { pts.append(centerline(Double(s) / Double(segs))) }
            for (i, p) in pts.enumerated() {
                let t = Double(i) / Double(segs)
                let pt = CGPoint(x: p.x - width(t), y: p.y)
                if i == 0 { ribbon.move(to: pt) } else { ribbon.addLine(to: pt) }
            }
            for i in stride(from: pts.count - 1, through: 0, by: -1) {
                let t = Double(i) / Double(segs)
                ribbon.addLine(to: CGPoint(x: pts[i].x + width(t), y: pts[i].y))
            }
            ribbon.closeSubpath()
            let kelpColor = Color(red: 0.05 + 0.05 * hash01(k, 14),
                                  green: 0.35 + 0.12 * hash01(k, 15), blue: 0.12)
            ctx.fill(ribbon, with: .color(kelpColor.opacity(0.9)))
        }
    }

    func drawFish(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let minDim = min(w, h)
        for f in swarm {
            let px = CGFloat(f.x) * w, py = CGFloat(f.y) * h
            let vlen = (f.vx * f.vx + f.vy * f.vy).squareRoot()
            let heading = vlen > 1e-6 ? atan2(f.vy, f.vx) : f.seed * .pi * 2
            let tier = min(2, Int(f.seed * 3))
            let scale = minDim / 640 * (0.85 + f.seed * 0.7)
            let wag = sin(time * (7.0 + f.seed * 3.0) + f.seed * 6.283)
            drawOneFish(ctx, at: CGPoint(x: px, y: py), heading: heading, scale: scale, wag: wag, tier: tier)
        }
    }

    func fishColors(_ tier: Int) -> (Color, Color, Color) {
        switch tier {
        case 0: return (Color(red: 1.0, green: 0.48, blue: 0.12), Color(red: 1.0, green: 0.78, blue: 0.5), Color(red: 1.0, green: 0.95, blue: 0.9))
        case 1: return (Color(red: 0.13, green: 0.45, blue: 0.92), Color(red: 0.45, green: 0.72, blue: 1.0), Color(red: 1.0, green: 0.85, blue: 0.2))
        default: return (Color(red: 0.74, green: 0.80, blue: 0.86), Color(red: 0.92, green: 0.95, blue: 0.98), Color(red: 0.6, green: 0.66, blue: 0.72))
        }
    }

    func drawOneFish(_ ctx: GraphicsContext, at center: CGPoint, heading: Double, scale: CGFloat, wag: Double, tier: Int) {
        let (body, belly, fin) = fishColors(tier)
        let L = 26 * scale, H = 12 * scale
        var ctx = ctx
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: Angle(radians: heading))
        let tailBase = CGPoint(x: -L * 0.5, y: 0)
        let tailLen = L * 0.5, tailSpread = H * 0.62
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
        let nose = CGPoint(x: L * 0.55, y: 0)
        var bodyPath = Path()
        bodyPath.move(to: nose)
        bodyPath.addCurve(to: tailBase, control1: CGPoint(x: L * 0.2, y: -H * 0.62), control2: CGPoint(x: -L * 0.25, y: -H * 0.5))
        bodyPath.addCurve(to: nose, control1: CGPoint(x: -L * 0.25, y: H * 0.5), control2: CGPoint(x: L * 0.2, y: H * 0.62))
        bodyPath.closeSubpath()
        ctx.fill(bodyPath, with: .linearGradient(Gradient(colors: [belly, body]),
                                                 startPoint: CGPoint(x: 0, y: H * 0.6), endPoint: CGPoint(x: 0, y: -H * 0.6)))
        let eye = CGPoint(x: L * 0.3, y: -H * 0.12)
        let eyeR = max(1.2, H * 0.14)
        ctx.fill(Path(ellipseIn: CGRect(x: eye.x - eyeR, y: eye.y - eyeR, width: eyeR * 2, height: eyeR * 2)), with: .color(.white))
    }

    func drawBubbles(_ ctx: GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let minDim = min(w, h)
        for (col, bx) in bubbleX.enumerated() {
            let perCol = 6
            let riseSpeed = 0.10 + 0.03 * hash01(col, 21)
            let wobRate = 1.5 + hash01(col, 22)
            let wobble = minDim * 0.02
            for j in 0..<perCol {
                let offset = Double(j) / Double(perCol) + hash01(col * 7 + j, 23)
                let prog = (time * riseSpeed + offset).truncatingRemainder(dividingBy: 1.0)
                let y = h * (1 - CGFloat(prog))
                let wob = sin(time * wobRate + Double(j) * 1.7 + Double(col)) * wobble
                let x = CGFloat(bx) * w + CGFloat(wob)
                let r = minDim * (0.006 + 0.012 * hash01(col * 13 + j, 24)) * (0.5 + CGFloat(prog) * 0.7)
                let alpha = 0.5 * min(1, prog * 4) * (1 - prog * 0.35)
                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.85 * alpha)), lineWidth: max(0.6, r * 0.14))
            }
        }
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

/// Count distinct coarse colors present — a proxy for color variance (a blank
/// or single-gradient frame would have very few distinct quantized colors).
func distinctColors(_ image: NSImage) -> Int {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return 0 }
    var set = Set<Int>()
    for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            let r = Int(c.redComponent * 7), g = Int(c.greenComponent * 7), b = Int(c.blueComponent * 7)
            set.insert(r << 6 | g << 3 | b)
        }
    }
    return set.count
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

func render(time: Double, path: String) -> (lit: Int, colors: Int, fp: [Int]) {
    var result = (0, 0, [Int]())
    MainActor.assumeIsolated {
        let renderer = ImageRenderer(content: AquariumFrame(time: time))
        renderer.scale = 2
        guard let img = renderer.nsImage else { print("FAIL: no image for \(path)"); return }
        let lit = litPixelCount(img)
        let colors = distinctColors(img)
        let fp = fingerprint(img)
        result = (lit, colors, fp)
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) (lit: \(lit), distinct colors: \(colors))")
        }
    }
    return result
}

func diffCount(_ a: [Int], _ b: [Int]) -> Int {
    guard a.count == b.count else { return max(a.count, b.count) }
    return zip(a, b).reduce(0) { $0 + (abs($1.0 - $1.1) > 6 ? 1 : 0) }
}

let f0 = render(time: 0.0, path: "/tmp/aquarium_t0.png")
let f1 = render(time: 0.6, path: "/tmp/aquarium_t1.png")
let f2 = render(time: 1.2, path: "/tmp/aquarium_t2.png")

precondition(f0.lit > 0, "t=0.0 frame should have lit pixels")
precondition(f1.lit > 0, "t=0.6 frame should have lit pixels")
precondition(f2.lit > 0, "t=1.2 frame should have lit pixels")

// Water gradient + kelp + multi-tier fish should yield plenty of distinct colors.
precondition(f0.colors > 12, "frame should have non-trivial color variance (got \(f0.colors))")

let d01 = diffCount(f0.fp, f1.fp)
let d12 = diffCount(f1.fp, f2.fp)
precondition(d01 > 0, "frame should change between t=0.0 and t=0.6 (fish swim / bubbles rise)")
precondition(d12 > 0, "frame should change between t=0.6 and t=1.2 (fish swim / bubbles rise)")

print("PASS: non-blank (lit=\(f0.lit),\(f1.lit),\(f2.lit)); color variance (\(f0.colors) distinct); frames change (diff01=\(d01), diff12=\(d12))")
