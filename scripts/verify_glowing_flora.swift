// Run: swift scripts/verify_glowing_flora.swift
// Renders the Glowing Flora effect (bioluminescent plants rooted at the bottom
// growing upward, blooming glowing flower-pods) at three phase times, mirroring
// the layout + reveal math in Sources/Lumora/Views/BioluminescentViews.swift
// (standalone scripts can't import the app module's internal views). Writes PNGs
// to /tmp and asserts each frame is non-blank, has color variance, and changes
// over time (upward growth + bloom).
import AppKit
import SwiftUI

enum P {
    static let night = Color(red: 0.008, green: 0.024, blue: 0.039)
    static let glowCyan = Color(red: 0.157, green: 0.902, blue: 0.824)
    static let glowAqua = Color(red: 0.361, green: 0.949, blue: 1.0)
    static let glowTeal = Color(red: 0.071, green: 0.718, blue: 0.659)
    static let accentMagenta = Color(red: 0.725, green: 0.294, blue: 0.878)
    static let accentViolet = Color(red: 0.478, green: 0.294, blue: 1.0)
    static func hash01(_ i: Int, _ salt: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return CGFloat(v - floor(v))
    }
}

let growDur = 12.0, holdDur = 6.0, fadeDur = 2.5
let period = growDur + holdDur + fadeDur

func polylineLengths(_ pts: [CGPoint]) -> (cum: [CGFloat], total: CGFloat) {
    var cum: [CGFloat] = [0]; var total: CGFloat = 0
    for i in 0..<max(0, pts.count - 1) { total += hypot(pts[i+1].x - pts[i].x, pts[i+1].y - pts[i].y); cum.append(total) }
    return (cum, total)
}
func pointAtArc(_ pts: [CGPoint], _ lengths: (cum: [CGFloat], total: CGFloat), arc: CGFloat) -> CGPoint {
    guard let first = pts.first else { return .zero }
    for i in 0..<(pts.count - 1) {
        let segEnd = lengths.cum[i+1]
        if segEnd >= arc {
            let a = pts[i], b = pts[i+1]; let segStart = lengths.cum[i]; let segLen = segEnd - segStart
            let f = segLen > 0 ? (arc - segStart) / segLen : 0
            return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
        }
    }
    return pts.last ?? first
}
func revealedPath(_ pts: [CGPoint], _ lengths: (cum: [CGFloat], total: CGFloat), upTo length: CGFloat) -> Path {
    var path = Path(); guard let first = pts.first, lengths.total > 0 else { return path }
    path.move(to: first)
    for i in 0..<(pts.count - 1) {
        let segEnd = lengths.cum[i+1]; let a = pts[i], b = pts[i+1]
        if segEnd <= length { path.addLine(to: b) }
        else {
            let segStart = lengths.cum[i]; let segLen = segEnd - segStart
            let f = segLen > 0 ? (length - segStart) / segLen : 0
            path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)); break
        }
    }
    return path
}

struct Plant { let stem: [CGPoint]; let stemLengths: (cum: [CGFloat], total: CGFloat); let pods: [(CGPoint, CGFloat, Bool)] }

func buildPlants(size: CGSize) -> [Plant] {
    let w = size.width, h = size.height
    func hh(_ i: Int, _ s: Int) -> CGFloat { P.hash01(i, s) }
    let plantCount = 5
    var plants: [Plant] = []
    for p in 0..<plantCount {
        let rootX = w * (CGFloat(p) + 0.5 + (hh(p, 2) - 0.5) * 0.6) / CGFloat(plantCount)
        let stemH = h * (0.5 + 0.35 * hh(p, 3))
        let curveDir: CGFloat = hh(p, 4) > 0.5 ? 1 : -1
        let curveAmt = w * 0.06 * (0.5 + hh(p, 5))
        var stem: [CGPoint] = []
        for s in 0...14 {
            let t = CGFloat(s) / 14
            stem.append(CGPoint(x: rootX + curveDir * curveAmt * sin(Double(t) * .pi * 0.8), y: h - stemH * t))
        }
        let sl = polylineLengths(stem)
        var pods: [(CGPoint, CGFloat, Bool)] = []
        for b in 0..<3 {
            let along = 0.5 + 0.3 * CGFloat(b) / 3
            let base = pointAtArc(stem, sl, arc: sl.total * along)
            pods.append((CGPoint(x: base.x + (hh(p*7+b, 8) - 0.5) * stemH * 0.3, y: base.y - stemH * 0.2),
                         min(w, h) * 0.014, hh(p*7+b, 10) > 0.5))
        }
        plants.append(Plant(stem: stem, stemLengths: sl, pods: pods))
    }
    return plants
}

struct FloraFrame: View {
    let elapsed: Double
    var body: some View {
        Canvas { ctx, size in drawFlora(ctx: ctx, size: size, elapsed: elapsed) }
        .frame(width: 640, height: 440)
    }
}
func drawFlora(ctx: GraphicsContext, size: CGSize, elapsed: Double) {
    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(P.night))
    let localT = elapsed.truncatingRemainder(dividingBy: period)
    let growFrac = min(localT / growDur, 1.0)
    let plants = buildPlants(size: size)
    for plant in plants {
        let litLen = CGFloat(growFrac) * plant.stemLengths.total
        let stemPath = revealedPath(plant.stem, plant.stemLengths, upTo: litLen)
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 8)); l.blendMode = .plusLighter
            l.stroke(stemPath, with: .color(P.glowTeal.opacity(0.5)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
        }
        ctx.stroke(stemPath, with: .color(P.glowTeal.opacity(0.95)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        for pod in plant.pods {
            let podArc = plant.stemLengths.total * 0.55
            let bloom = max(0, min(1, (litLen - podArc) / 60))
            if bloom <= 0.01 { continue }
            let r = pod.1 * bloom
            let coreC = pod.2 ? P.accentMagenta : P.accentViolet
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 7)); l.blendMode = .plusLighter
                l.fill(Path(ellipseIn: CGRect(x: pod.0.x - r*1.8, y: pod.0.y - r*1.8, width: r*3.6, height: r*3.6)),
                       with: .color(P.glowCyan.opacity(0.5)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: pod.0.x - r, y: pod.0.y - r, width: r*2, height: r*2)), with: .color(coreC.opacity(0.95)))
        }
        if growFrac < 1.0 {
            let head = pointAtArc(plant.stem, plant.stemLengths, arc: litLen)
            ctx.fill(Path(ellipseIn: CGRect(x: head.x - 2.5, y: head.y - 2.5, width: 5, height: 5)), with: .color(.white))
        }
    }
}

func litPixelCount(_ image: NSImage) -> Int {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return 0 }
    var count = 0
    for y in stride(from: 0, to: rep.pixelsHigh, by: 4) { for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
        guard let c = rep.colorAt(x: x, y: y) else { continue }
        if 0.299*c.redComponent + 0.587*c.greenComponent + 0.114*c.blueComponent > 0.10 { count += 1 } } }
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
func render(elapsed: Double, path: String) -> (lit: Int, fp: [Int], varr: Double) {
    var result = (0, [Int](), 0.0)
    MainActor.assumeIsolated {
        let renderer = ImageRenderer(content: FloraFrame(elapsed: elapsed)); renderer.scale = 2
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
let f0 = render(elapsed: 3.0, path: "/tmp/glowing_flora_t0.png")   // early grow
let f1 = render(elapsed: 9.0, path: "/tmp/glowing_flora_t1.png")   // mid grow
let f2 = render(elapsed: 15.0, path: "/tmp/glowing_flora_t2.png")  // hold (bloomed)
precondition(f0.lit > 0 && f1.lit > 0 && f2.lit > 0, "frames should be non-blank")
precondition(f2.varr > 5, "grown frame should have color variance (glowing plants on dark)")
let d01 = diffCount(f0.fp, f1.fp), d12 = diffCount(f1.fp, f2.fp)
precondition(d01 > 0 && d12 > 0, "frames should change over time (upward growth + bloom)")
precondition(f2.lit > f0.lit, "grown frame should have more lit pixels than early-grow frame")
print("PASS: non-blank (lit=\(f0.lit),\(f1.lit),\(f2.lit)); variance=\(Int(f2.varr)); growth over time (d01=\(d01), d12=\(d12))")
