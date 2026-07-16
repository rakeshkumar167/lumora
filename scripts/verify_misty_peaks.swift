// Run: swift scripts/verify_misty_peaks.swift
// Renders the Misty Peaks backdrop (moonlit sky + parallax ridges + mist bands)
// at three `time` values, mirroring the drawing math in
// Sources/Lumora/Views/BioluminescentViews.swift (standalone scripts can't
// import the app module's internal views). Writes PNGs to /tmp and asserts each
// frame is non-blank, has color variance, and changes over time (parallax/mist).
import AppKit
import SwiftUI

enum P {
    static let night = Color(red: 0.008, green: 0.024, blue: 0.039)
    static let moon = Color(red: 0.749, green: 0.914, blue: 1.0)
    static let mist = Color(red: 0.055, green: 0.165, blue: 0.200)
    static func hash01(_ i: Int, _ salt: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return CGFloat(v - floor(v))
    }
}

struct MistyFrame: View {
    let time: Double
    var body: some View {
        Canvas { ctx, size in drawMisty(ctx: ctx, size: size, time: time) }
        .frame(width: 640, height: 440)
    }
}

func drawMisty(ctx: GraphicsContext, size: CGSize, time: Double) {
            let w = size.width, h = size.height
            let skyTop = Color(red: 0.02, green: 0.06, blue: 0.10)
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [skyTop, P.night]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            let moonBreathe = 0.85 + 0.15 * sin(time * 0.25)
            let moonC = CGPoint(x: w * 0.68, y: h * 0.22)
            let moonR = min(w, h) * 0.28
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 30)); l.blendMode = .plusLighter
                l.fill(Path(ellipseIn: CGRect(x: moonC.x - moonR, y: moonC.y - moonR, width: moonR * 2, height: moonR * 2)),
                       with: .radialGradient(Gradient(colors: [P.moon.opacity(0.55 * moonBreathe), .clear]),
                                             center: moonC, startRadius: 0, endRadius: moonR))
            }
            let discR = min(w, h) * 0.05
            ctx.fill(Path(ellipseIn: CGRect(x: moonC.x - discR, y: moonC.y - discR, width: discR * 2, height: discR * 2)),
                     with: .color(P.moon.opacity(0.9 * moonBreathe)))
            for i in 0..<60 {
                let sx = P.hash01(i, 1) * w
                let sy = P.hash01(i, 2) * h * 0.6
                let tw = 0.3 + 0.7 * (0.5 + 0.5 * sin(time * 1.3 + Double(i) * 1.7))
                let s = 0.8 + 1.4 * P.hash01(i, 3)
                ctx.fill(Path(ellipseIn: CGRect(x: sx, y: sy, width: s, height: s)), with: .color(P.moon.opacity(0.7 * tw)))
            }
            let ridgeCount = 4
            for r in 0..<ridgeCount {
                let depth = Double(r) / Double(ridgeCount - 1)
                let baseY = h * CGFloat(0.42 + 0.14 * depth)
                let amp = h * CGFloat(0.06 + 0.10 * depth)
                let drift = CGFloat(time * (0.6 + Double(r) * 1.4)) * (1 + CGFloat(depth))
                let tint = Color(red: 0.03 + 0.05 * (1 - depth), green: 0.08 + 0.10 * (1 - depth), blue: 0.12 + 0.14 * (1 - depth))
                var ridge = Path(); ridge.move(to: CGPoint(x: 0, y: h))
                let steps = 40
                for s in 0...steps {
                    let fx = CGFloat(s) / CGFloat(steps); let x = fx * w
                    let n1 = sin(Double(fx) * 6.0 + Double(drift) * 0.03 + Double(r) * 2.0)
                    let n2 = sin(Double(fx) * 15.0 + Double(drift) * 0.05 + Double(r) * 5.0) * 0.4
                    let jag = Double(P.hash01(s + r * 100, r + 1)) * 0.5
                    let y = baseY - amp * CGFloat(n1 + n2 + jag - 0.4)
                    ridge.addLine(to: CGPoint(x: x, y: y))
                }
                ridge.addLine(to: CGPoint(x: w, y: h)); ridge.closeSubpath()
                ctx.fill(ridge, with: .color(tint))
            }
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 26)); l.blendMode = .plusLighter
                for b in 0..<3 {
                    let by = h * CGFloat(0.45 + 0.16 * Double(b)); let bh = h * 0.10
                    let phase = time * (0.03 + 0.02 * Double(b)) + Double(b)
                    let ox = CGFloat(sin(phase) * Double(w) * 0.15)
                    let band = Path(roundedRect: CGRect(x: -w * 0.2 + ox, y: by - bh / 2, width: w * 1.4, height: bh), cornerRadius: bh / 2)
                    l.fill(band, with: .color(P.mist.opacity(0.22)))
                }
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
        let renderer = ImageRenderer(content: MistyFrame(time: time)); renderer.scale = 2
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
let f0 = render(time: 0.0, path: "/tmp/misty_peaks_t0.png")
let f1 = render(time: 2.0, path: "/tmp/misty_peaks_t1.png")
let f2 = render(time: 5.0, path: "/tmp/misty_peaks_t2.png")
precondition(f0.lit > 0 && f1.lit > 0 && f2.lit > 0, "frames should be non-blank")
precondition(f0.varr > 20, "frame should have color variance (sky/ridges/moon)")
let d01 = diffCount(f0.fp, f1.fp), d12 = diffCount(f1.fp, f2.fp)
precondition(d01 > 0 && d12 > 0, "frames should change over time (parallax/mist/twinkle)")
print("PASS: non-blank (lit=\(f0.lit),\(f1.lit),\(f2.lit)); variance=\(Int(f0.varr)); change over time (d01=\(d01), d12=\(d12))")
