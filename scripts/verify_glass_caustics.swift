// Run: swift scripts/verify_glass_caustics.swift
// Offscreen check for the new Stained Glass (.fields) and Water Caustics
// (.ambient) effects. Both renderers live as `private` funcs inside
// SurfaceContentView.swift, which a standalone script can't import — so this
// mirrors their logic here, exactly, matching drawStainedGlass/drawCaustics
// and the stainedGlassCells helper. Renders each effect at 3 `time` values,
// writes PNGs to /tmp, and asserts frames are non-blank with non-trivial
// color variance (i.e. not a flat fill).
import AppKit
import SwiftUI

// MARK: - Mirrored from SurfaceContentView.swift (EffectView)

func hash01(_ i: Int, _ salt: Int) -> CGFloat {
    let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
    return CGFloat(v - floor(v))
}

/// Sutherland-Hodgman clip of a convex polygon to the half-plane n*p <= c.
/// Mirrors EffectView.clipHalfPlane exactly.
func clipHalfPlane(_ poly: [CGPoint], nx: Double, ny: Double, c: Double) -> [CGPoint] {
    guard poly.count >= 3 else { return [] }
    var out: [CGPoint] = []
    out.reserveCapacity(poly.count + 1)
    for i in 0..<poly.count {
        let a = poly[i], b = poly[(i + 1) % poly.count]
        let da = nx * Double(a.x) + ny * Double(a.y) - c
        let db = nx * Double(b.x) + ny * Double(b.y) - c
        let ain = da <= 0, bin = db <= 0
        if ain { out.append(a) }
        if ain != bin {
            let t = da / (da - db)
            out.append(CGPoint(x: a.x + CGFloat(t) * (b.x - a.x),
                               y: a.y + CGFloat(t) * (b.y - a.y)))
        }
    }
    return out
}

/// Mirrors EffectView.stainedGlassCells exactly.
func stainedGlassCells(in size: CGSize, count: Int) -> [[CGPoint]] {
    var sites: [(x: Double, y: Double)] = []
    sites.reserveCapacity(count)
    for i in 0..<count {
        let x = Double(hash01(i, 11)) * Double(size.width)
        let y = Double(hash01(i, 29)) * Double(size.height)
        sites.append((x, y))
    }
    var cells: [[CGPoint]] = []
    cells.reserveCapacity(count)
    for s in sites {
        var poly = [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
                    CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)]
        for o in sites {
            if o.x == s.x && o.y == s.y { continue }
            let nx = o.x - s.x, ny = o.y - s.y
            let c = (o.x * o.x + o.y * o.y - s.x * s.x - s.y * s.y) / 2
            poly = clipHalfPlane(poly, nx: nx, ny: ny, c: c)
            if poly.count < 3 { break }
        }
        if poly.count >= 3 { cells.append(poly) }
    }
    return cells
}

/// Mirrors EffectView.drawStainedGlass exactly.
struct StainedGlassFrame: View {
    let time: Double
    var body: some View {
        Canvas { ctx, size in
            let cells = stainedGlassCells(in: size, count: 26)
            let palette: [Color] = [
                Color(red: 0.10, green: 0.20, blue: 0.65), Color(red: 0.65, green: 0.10, blue: 0.20),
                Color(red: 0.10, green: 0.55, blue: 0.30), Color(red: 0.85, green: 0.65, blue: 0.15),
                Color(red: 0.45, green: 0.15, blue: 0.60)]
            let diag = Double(hypot(size.width, size.height))
            let lc = CGPoint(x: size.width * (0.5 + 0.4 * cos(time * 0.3)),
                              y: size.height * (0.5 + 0.4 * sin(time * 0.23)))
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.03)))
            for (i, poly) in cells.enumerated() {
                guard let c0 = poly.first else { continue }
                var p = Path(); p.addLines(poly); p.closeSubpath()
                let d = Double(hypot(c0.x - lc.x, c0.y - lc.y))
                let lit = max(0.35, 1.0 - d / diag)
                ctx.fill(p, with: .color(palette[i % palette.count].opacity(0.85 * lit)))
                ctx.stroke(p, with: .color(Color(white: 0.04)), lineWidth: 4)
            }
            let glowR = diag * 0.16
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 22))
                layer.blendMode = .plusLighter
                layer.fill(
                    Path(ellipseIn: CGRect(x: lc.x - glowR, y: lc.y - glowR, width: glowR * 2, height: glowR * 2)),
                    with: .color(.white.opacity(0.20)))
            }
        }
        .frame(width: 500, height: 500)
    }
}

/// Mirrors EffectView.drawCaustics exactly, with fixed sample color/accent.
struct CausticsFrame: View {
    let time: Double
    let color: Color = Color(red: 0.02, green: 0.20, blue: 0.35)
    let accent: Color = Color(red: 0.30, green: 0.85, blue: 0.95)
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.opacity(0.9)))
            let w = Double(size.width), h = Double(size.height)
            for layer in 0..<3 {
                let n = 12
                let sp = 0.15 + 0.09 * Double(layer)
                let dir: Double = layer % 2 == 0 ? 1 : -1
                let sites: [CGPoint] = (0..<n).map { i in
                    let fi = Double(i)
                    return CGPoint(
                        x: w * (0.5 + 0.48 * sin(dir * time * sp + fi * 1.7 + Double(layer))),
                        y: h * (0.5 + 0.48 * cos(dir * time * sp * 1.3 + fi * 2.3)))
                }
                var links = Path()
                for i in 0..<sites.count {
                    var dists: [(Int, Double)] = []
                    for j in 0..<sites.count where j != i {
                        let dx = sites[i].x - sites[j].x, dy = sites[i].y - sites[j].y
                        dists.append((j, Double(dx * dx + dy * dy)))
                    }
                    dists.sort { $0.1 < $1.1 }
                    for (j, _) in dists.prefix(2) {
                        links.move(to: sites[i])
                        links.addLine(to: sites[j])
                    }
                }
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: 4 + CGFloat(layer) * 1.2))
                    l.blendMode = .plusLighter
                    l.stroke(links, with: .color(accent.opacity(0.16)), lineWidth: 2.5)
                    for s in sites {
                        let r = 20 + 9 * CGFloat(sin(time * 0.8 + Double(s.x) * 0.015 + Double(layer)))
                        l.stroke(
                            Path(ellipseIn: CGRect(x: s.x - r, y: s.y - r, width: r * 2, height: r * 2)),
                            with: .color(accent.opacity(0.30)), lineWidth: 3)
                    }
                }
            }
        }
        .frame(width: 500, height: 500)
    }
}

// MARK: - Pixel stats

struct PixelStats {
    let litCount: Int
    let variance: Double // variance of per-pixel luminance
}

func pixelStats(_ image: NSImage) -> PixelStats {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
        return PixelStats(litCount: 0, variance: 0)
    }
    var lums: [Double] = []
    let w = rep.pixelsWide, h = rep.pixelsHigh
    for y in stride(from: 0, to: h, by: 3) {
        for x in stride(from: 0, to: w, by: 3) {
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            let lum = 0.299 * Double(c.redComponent) + 0.587 * Double(c.greenComponent) + 0.114 * Double(c.blueComponent)
            lums.append(lum)
        }
    }
    let lit = lums.filter { $0 > 0.08 }.count
    guard !lums.isEmpty else { return PixelStats(litCount: 0, variance: 0) }
    let mean = lums.reduce(0, +) / Double(lums.count)
    let variance = lums.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(lums.count)
    return PixelStats(litCount: lit, variance: variance)
}

@MainActor
func render<V: View>(_ view: V, path: String) -> PixelStats {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let img = renderer.nsImage else {
        print("FAIL: no image for \(path)")
        return PixelStats(litCount: 0, variance: 0)
    }
    let stats = pixelStats(img)
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (lit pixels: \(stats.litCount), luminance variance: \(String(format: "%.5f", stats.variance)))")
    }
    return stats
}

let times: [Double] = [0.4, 12.7, 48.3]

var glassStats: [PixelStats] = []
var causticsStats: [PixelStats] = []

MainActor.assumeIsolated {
    for (i, t) in times.enumerated() {
        glassStats.append(render(StainedGlassFrame(time: t), path: "/tmp/stained_glass_t\(i).png"))
    }
    for (i, t) in times.enumerated() {
        causticsStats.append(render(CausticsFrame(time: t), path: "/tmp/caustics_t\(i).png"))
    }
}

let minVariance = 0.00005

for (i, s) in glassStats.enumerated() {
    precondition(s.litCount > 0, "stained glass frame \(i) should have lit pixels")
    precondition(s.variance > minVariance, "stained glass frame \(i) variance too low (flat fill?): \(s.variance)")
}
for (i, s) in causticsStats.enumerated() {
    precondition(s.litCount > 0, "caustics frame \(i) should have lit pixels")
    precondition(s.variance > minVariance, "caustics frame \(i) variance too low (flat fill?): \(s.variance)")
}

// The stained glass panes are STATIC (only the light sweep moves), so per-cell
// brightness shifts across time but the overall variance should stay in a
// similar ballpark rather than collapsing to near-zero at any sampled time.
// Caustics layers drift continuously, so consecutive frames should differ.
func framesDiffer(_ a: PixelStats, _ b: PixelStats) -> Bool {
    abs(a.variance - b.variance) > 1e-6 || a.litCount != b.litCount
}
precondition(framesDiffer(causticsStats[0], causticsStats[1]) || framesDiffer(causticsStats[1], causticsStats[2]),
             "caustics frames should visibly differ across time (drifting layers)")

print("PASS: Stained Glass and Water Caustics render non-blank frames with non-trivial color variance across all sampled times.")
