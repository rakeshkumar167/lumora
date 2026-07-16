// Run: swift scripts/verify_bio_river.swift
// Renders the Bioluminescent River effect (glowing motes advected by a
// directional current + meander, drawn as velocity-aligned streaks over a water
// gradient) at three `time` values, mirroring the flow/draw math in
// Sources/Lumora/Views/BioluminescentViews.swift with a self-contained
// sine-field stand-in for CurlNoiseField (standalone scripts can't import the
// app module's internal views). Writes PNGs to /tmp and asserts each frame is
// non-blank, has color variance, and changes over time (the current flows).
import AppKit
import SwiftUI

enum P {
    static let waterDeep = Color(red: 0.012, green: 0.075, blue: 0.094)
    static let waterMid = Color(red: 0.020, green: 0.196, blue: 0.227)
    static let glowCyan = Color(red: 0.157, green: 0.902, blue: 0.824)
    static let glowAqua = Color(red: 0.361, green: 0.949, blue: 1.0)
    static let glowTeal = Color(red: 0.071, green: 0.718, blue: 0.659)
    static let accentViolet = Color(red: 0.478, green: 0.294, blue: 1.0)
    static func hash(_ seed: Int, _ salt: Int) -> Double {
        let v = sin(Double(seed) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return v - floor(v)
    }
}

struct Mote { var x: Double; var y: Double; var vx: Double; var vy: Double; let seed: Int }

let current = (dx: 0.06, dy: 0.14)
let meander = 0.09

// Stand-in "curl" field: smooth divergence-y sine field (not the real
// CurlNoiseField, but enough to make the flow meander deterministically).
func fieldFlow(_ x: Double, _ y: Double, _ t: Double) -> (Double, Double) {
    let dx = sin(y * 6.0 + t * 0.3) * cos(x * 4.0)
    let dy = cos(x * 6.0 - t * 0.2) * sin(y * 4.0)
    return (dx, dy)
}

func simulate(count: Int, to time: Double) -> [Mote] {
    var motes: [Mote] = []
    for i in 0..<count { motes.append(Mote(x: P.hash(i, 1), y: P.hash(i, 2), vx: 0, vy: 0, seed: i)) }
    var reseed = 0
    let dt = 1.0 / 60.0
    var t = 0.0
    while t < time {
        for i in motes.indices {
            let m = motes[i]
            let f = fieldFlow(m.x, m.y, t)
            let vx = current.dx + f.0 * meander
            let vy = current.dy + f.1 * meander
            var nx = m.x + vx * dt, ny = m.y + vy * dt
            var respawned = false
            if ny > 1.08 { ny -= 1.16; nx = P.hash(m.seed, reseed); respawned = true }
            if nx > 1.08 { nx -= 1.16; respawned = true }
            if nx < -0.08 { nx += 1.16 }
            if respawned { reseed += 1 }
            motes[i].x = nx; motes[i].y = ny; motes[i].vx = vx; motes[i].vy = vy
        }
        t += dt
    }
    return motes
}

struct RiverFrame: View {
    let time: Double
    var body: some View {
        Canvas { ctx, size in drawRiver(ctx: ctx, size: size, motes: simulate(count: 120, to: time), time: time) }
        .frame(width: 640, height: 440)
    }
}
func drawRiver(ctx: GraphicsContext, size: CGSize, motes: [Mote], time: Double) {
    let w = size.width, h = size.height
    ctx.fill(Path(CGRect(origin: .zero, size: size)),
             with: .linearGradient(Gradient(colors: [P.waterMid, P.waterDeep]),
                                   startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
    ctx.drawLayer { l in
        l.addFilter(.blur(radius: 22)); l.blendMode = .plusLighter
        for b in 0..<3 {
            let phase = time * 0.12 + Double(b) * 0.4
            let y = (phase.truncatingRemainder(dividingBy: 1.3) - 0.15) * Double(h)
            let band = Path(roundedRect: CGRect(x: -w*0.1, y: CGFloat(y), width: w*1.2, height: h*0.06), cornerRadius: h*0.03)
            l.fill(band, with: .color(P.glowTeal.opacity(0.10)))
        }
    }
    ctx.drawLayer { l in
        l.addFilter(.blur(radius: 4)); l.blendMode = .plusLighter
        for m in motes {
            let px = CGFloat(m.x) * w, py = CGFloat(m.y) * h
            let vlen = (m.vx*m.vx + m.vy*m.vy).squareRoot()
            guard vlen > 1e-6 else { continue }
            let tail = CGFloat(24) * CGFloat(vlen / 0.2)
            let ux = CGFloat(m.vx / vlen), uy = CGFloat(m.vy / vlen)
            var streak = Path(); streak.move(to: CGPoint(x: px - ux*tail, y: py - uy*tail)); streak.addLine(to: CGPoint(x: px, y: py))
            let rare = m.seed % 17 == 0
            let c = rare ? P.accentViolet : (m.seed % 2 == 0 ? P.glowAqua : P.glowCyan)
            l.stroke(streak, with: .color(c.opacity(0.55)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        }
    }
    for m in motes {
        let px = CGFloat(m.x) * w, py = CGFloat(m.y) * h
        let rare = m.seed % 17 == 0
        let r: CGFloat = rare ? 2.6 : 1.6
        let c = rare ? P.accentViolet : Color.white
        ctx.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r*2, height: r*2)), with: .color(c.opacity(0.9)))
    }
}

func litPixelCount(_ image: NSImage) -> Int {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return 0 }
    var count = 0
    for y in stride(from: 0, to: rep.pixelsHigh, by: 4) { for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
        guard let c = rep.colorAt(x: x, y: y) else { continue }
        if 0.299*c.redComponent + 0.587*c.greenComponent + 0.114*c.blueComponent > 0.12 { count += 1 } } }
    return count
}
func fingerprint(_ image: NSImage) -> [Int] {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return [] }
    var out: [Int] = []
    for y in stride(from: 0, to: rep.pixelsHigh, by: 4) { for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
        guard let c = rep.colorAt(x: x, y: y) else { continue }
        out.append(Int((0.299*c.redComponent + 0.587*c.greenComponent + 0.114*c.blueComponent) * 255)) } }
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
        let renderer = ImageRenderer(content: RiverFrame(time: time)); renderer.scale = 2
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
let f0 = render(time: 1.0, path: "/tmp/bio_river_t0.png")
let f1 = render(time: 2.5, path: "/tmp/bio_river_t1.png")
let f2 = render(time: 4.0, path: "/tmp/bio_river_t2.png")
precondition(f0.lit > 0 && f1.lit > 0 && f2.lit > 0, "frames should be non-blank")
precondition(f0.varr > 5, "frame should have color variance (glowing motes on water)")
let d01 = diffCount(f0.fp, f1.fp), d12 = diffCount(f1.fp, f2.fp)
precondition(d01 > 0 && d12 > 0, "frames should change over time (the current flows)")
print("PASS: non-blank (lit=\(f0.lit),\(f1.lit),\(f2.lit)); variance=\(Int(f0.varr)); flow over time (d01=\(d01), d12=\(d12))")
