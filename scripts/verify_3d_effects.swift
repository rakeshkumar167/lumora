// Run: swift scripts/verify_3d_effects.swift
// Renders the two new 3D effects (Strange Attractor Lorenz ribbon + DNA Helix)
// offscreen via ImageRenderer at two `time` values each, mirroring the renderers
// in SurfaceContentView.swift. Writes PNGs to /tmp and asserts every frame has
// lit pixels (non-blank) and that rotating the scene changes the frame (the two
// times produce a materially different lit-pixel count / pixel signature).
import AppKit
import SwiftUI

// MARK: - 3D math (mirrors SurfaceContentView private helpers)

struct Vec3 { var x = 0.0, y = 0.0, z = 0.0 }

func rot3(_ p: Vec3, _ ax: Double, _ ay: Double) -> Vec3 {
    let cx = cos(ax), sx = sin(ax)
    let y1 = p.y * cx - p.z * sx
    let z1 = p.y * sx + p.z * cx
    let cy = cos(ay), sy = sin(ay)
    return Vec3(x: p.x * cy + z1 * sy, y: y1, z: -p.x * sy + z1 * cy)
}
func fract(_ v: Double) -> Double { v - floor(v) }

// MARK: - Lorenz integrator (mirrors LumoraKit.StrangeAttractor; scripts don't import LumoraKit)

func lorenz(steps: Int, dt: Double, sigma: Double = 10, rho: Double = 28, beta: Double = 8.0/3.0) -> [Vec3] {
    var x = 0.1, y = 0.0, z = 0.0
    var out: [Vec3] = []; out.reserveCapacity(steps)
    for _ in 0..<steps {
        let dx = sigma * (y - x), dy = x * (rho - z) - y, dz = x * y - beta * z
        x += dx * dt; y += dy * dt; z += dz * dt
        out.append(Vec3(x: x, y: y, z: z))
    }
    return out
}

let lorenzPolyline: [Vec3] = {
    let raw = lorenz(steps: 4000, dt: 0.005)
    var cx = 0.0, cy = 0.0, cz = 0.0
    for p in raw { cx += p.x; cy += p.y; cz += p.z }
    let n = Double(raw.count); cx /= n; cy /= n; cz /= n
    var maxExt = 1e-6
    for p in raw {
        maxExt = max(maxExt, abs(p.x - cx)); maxExt = max(maxExt, abs(p.y - cy)); maxExt = max(maxExt, abs(p.z - cz))
    }
    let s = 1.0 / maxExt
    return raw.map { Vec3(x: ($0.x - cx) * s, y: ($0.y - cy) * s, z: ($0.z - cz) * s) }
}()

// MARK: - Views mirroring the renderers

struct AttractorFrame: View {
    let time: Double
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            let poly = lorenzPolyline
            let scale = Double(min(size.width, size.height)) * 1.6
            let camDist = 5.0, cx = size.width / 2, cy = size.height / 2
            var screen: [CGPoint] = []
            for p in poly {
                let r = rot3(p, time * 0.3, time * 0.5)
                let f = camDist / max(r.z + camDist, 0.1)
                screen.append(CGPoint(x: cx + r.x * f * scale, y: cy + r.y * f * scale))
            }
            let bandCount = 48
            var bands = [Path](repeating: Path(), count: bandCount)
            let total = screen.count
            for i in 1..<total {
                let bi = min(bandCount - 1, Int(Double(i) / Double(total) * Double(bandCount)))
                bands[bi].move(to: screen[i - 1]); bands[bi].addLine(to: screen[i])
            }
            func bandColor(_ bi: Int) -> Color { Color(hue: (Double(bi) + 0.5) / Double(bandCount), saturation: 0.85, brightness: 1) }
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 7)); layer.blendMode = .plusLighter
                for bi in bands.indices where !bands[bi].isEmpty {
                    layer.stroke(bands[bi], with: .color(bandColor(bi).opacity(0.5)),
                                 style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
            }
            ctx.drawLayer { layer in
                layer.blendMode = .plusLighter
                for bi in bands.indices where !bands[bi].isEmpty {
                    layer.stroke(bands[bi], with: .color(bandColor(bi)),
                                 style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .frame(width: 500, height: 500)
    }
}

struct DNAFrame: View {
    let time: Double
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            let n = 92, turns = 2.3, radius = 1.05, vHalf = 1.45
            let scale = Double(min(size.width, size.height)) * 0.30
            let camDist = 5.0, cx = size.width / 2, cy = size.height / 2
            let spin = time * 0.25
            func project(_ v: Vec3) -> (CGPoint, Double) {
                let r = rot3(v, 0, spin)
                let f = camDist / max(r.z + camDist, 0.1)
                return (CGPoint(x: cx + r.x * f * scale, y: cy + r.y * f * scale), f)
            }
            var dots: [(CGPoint, Double, Double)] = []
            var rungs: [(CGPoint, CGPoint, Double, Double)] = []
            for i in 0..<n {
                let t = Double(i) / Double(n)
                let a = t * turns * 2 * .pi + time
                let yv = (t - 0.5) * 2 * vHalf
                let (sa, fa) = project(Vec3(x: radius * cos(a), y: yv, z: radius * sin(a)))
                let (sb, fb) = project(Vec3(x: radius * cos(a + .pi), y: yv, z: radius * sin(a + .pi)))
                let hue = fract(t + time * 0.03)
                dots.append((sa, fa, hue)); dots.append((sb, fb, fract(hue + 0.5)))
                if i % 3 == 0 { rungs.append((sa, sb, (fa + fb) / 2, hue)) }
            }
            dots.sort { $0.1 < $1.1 }
            ctx.drawLayer { layer in
                layer.blendMode = .plusLighter
                for (a, b, f, hue) in rungs {
                    var line = Path(); line.move(to: a); line.addLine(to: b)
                    layer.stroke(line, with: .color(Color(hue: hue, saturation: 0.5, brightness: 1).opacity(min(0.45, f * 0.38))),
                                 style: StrokeStyle(lineWidth: max(1, (f - 0.5) * 3), lineCap: .round))
                }
            }
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 6))
                layer.blendMode = .plusLighter
                for (sp, f, hue) in dots {
                    let rad = max(1.6, (f - 0.45) * 11)
                    layer.fill(Path(ellipseIn: CGRect(x: sp.x - rad, y: sp.y - rad, width: rad * 2, height: rad * 2)),
                               with: .color(Color(hue: hue, saturation: 0.85, brightness: 1).opacity(min(1, f * 0.8))))
                }
            }
            ctx.drawLayer { layer in
                layer.blendMode = .plusLighter
                for (sp, f, hue) in dots {
                    let rad = max(0.9, (f - 0.5) * 6.0)
                    layer.fill(Path(ellipseIn: CGRect(x: sp.x - rad, y: sp.y - rad, width: rad * 2, height: rad * 2)),
                               with: .color(Color(hue: hue, saturation: 0.7, brightness: 1).opacity(min(1, f * 0.95))))
                }
            }
        }
        .frame(width: 500, height: 500)
    }
}

// MARK: - Pixel analysis

func litPixelCount(_ image: NSImage) -> Int {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return 0 }
    var count = 0
    let w = rep.pixelsWide, h = rep.pixelsHigh
    for y in stride(from: 0, to: h, by: 2) {
        for x in stride(from: 0, to: w, by: 2) {
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
            if lum > 0.08 { count += 1 }
        }
    }
    return count
}

func render<V: View>(_ view: V, path: String) -> (Int, [UInt8]) {
    var lit = 0
    var sig: [UInt8] = []
    MainActor.assumeIsolated {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage else { print("FAIL: no image for \(path)"); return }
        lit = litPixelCount(img)
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            // Coarse signature: sample a grid of luminances to detect frame change.
            let w = rep.pixelsWide, h = rep.pixelsHigh
            for gy in stride(from: 0, to: h, by: max(1, h / 20)) {
                for gx in stride(from: 0, to: w, by: max(1, w / 20)) {
                    if let c = rep.colorAt(x: gx, y: gy) {
                        let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
                        sig.append(UInt8(min(255, max(0, lum * 255))))
                    }
                }
            }
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
                print("wrote \(path) (lit pixels: \(lit))")
            }
        }
    }
    return (lit, sig)
}

func sigDiff(_ a: [UInt8], _ b: [UInt8]) -> Int {
    guard a.count == b.count else { return Int.max }
    var d = 0
    for i in a.indices where a[i] != b[i] { d += 1 }
    return d
}

let (attrA, attrSigA) = render(AttractorFrame(time: 1.0), path: "/tmp/attractor_t1.png")
let (attrB, attrSigB) = render(AttractorFrame(time: 4.0), path: "/tmp/attractor_t2.png")
let (dnaA, dnaSigA) = render(DNAFrame(time: 1.0), path: "/tmp/dna_t1.png")
let (dnaB, dnaSigB) = render(DNAFrame(time: 4.0), path: "/tmp/dna_t2.png")

precondition(attrA > 0 && attrB > 0, "Strange Attractor frames must be non-blank (\(attrA), \(attrB))")
precondition(dnaA > 0 && dnaB > 0, "DNA Helix frames must be non-blank (\(dnaA), \(dnaB))")

let attrChange = sigDiff(attrSigA, attrSigB)
let dnaChange = sigDiff(dnaSigA, dnaSigB)
precondition(attrChange > 5, "Strange Attractor must change with rotation (sig diff \(attrChange))")
precondition(dnaChange > 5, "DNA Helix must change with rotation (sig diff \(dnaChange))")

print("PASS: Strange Attractor non-blank (\(attrA),\(attrB)) rotates (sigdiff=\(attrChange)); DNA Helix non-blank (\(dnaA),\(dnaB)) rotates (sigdiff=\(dnaChange))")
