// Run: swift scripts/verify_godrays_ink.swift
// Offscreen check for the new God Rays (.ambient, primary-only) and Ink in
// Water (.ambient, primary+accent, STATEFUL) effects. Both renderers live
// inside SurfaceContentView.swift (drawGodRays / InkFlowView), which a
// standalone script can't import — so this mirrors their logic here. God Rays
// is stateless (rendered at 3 time values). Ink is stateful: we run a
// simplified advected-blob sim (the same spawn/advect/grow/fade loop, using
// the same CurlNoiseField math) forward across many frames so blobs build up,
// then render. Asserts non-blank frames with non-trivial luminance variance.
import AppKit
import SwiftUI

// MARK: - hash01 (mirrors EffectView.hash01)

func hash01(_ i: Int, _ salt: Int) -> CGFloat {
    let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
    return CGFloat(v - floor(v))
}

// MARK: - CurlNoiseField (mirrors LumoraKit/CurlNoiseField.swift)

struct CurlField {
    var frequency = 2.4
    var timeScale = 0.12

    func flow(x: Double, y: Double, t: Double) -> CGVector {
        let eps = 1e-3
        let dpsi_dx = (potential(x + eps, y, t) - potential(x - eps, y, t)) / (2 * eps)
        let dpsi_dy = (potential(x, y + eps, t) - potential(x, y - eps, t)) / (2 * eps)
        return CGVector(dx: dpsi_dy, dy: -dpsi_dx)
    }
    func potential(_ x: Double, _ y: Double, _ t: Double) -> Double {
        let lo = valueNoise(x * frequency, y * frequency, t * timeScale)
        let hi = valueNoise(x * frequency * 2.3 + 11.5, y * frequency * 2.3 + 4.2, t * timeScale * 1.6)
        return ((lo * 0.65 + hi * 0.35) * 2 - 1)
    }
    func valueNoise(_ x: Double, _ y: Double, _ z: Double) -> Double {
        let xi = fastFloor(x), yi = fastFloor(y), zi = fastFloor(z)
        let xf = x - Double(xi), yf = y - Double(yi), zf = z - Double(zi)
        let u = fade(xf), v = fade(yf), w = fade(zf)
        func corner(_ dx: Int, _ dy: Int, _ dz: Int) -> Double { hash(xi + dx, yi + dy, zi + dz) }
        let x00 = lerp(corner(0, 0, 0), corner(1, 0, 0), u)
        let x10 = lerp(corner(0, 1, 0), corner(1, 1, 0), u)
        let x01 = lerp(corner(0, 0, 1), corner(1, 0, 1), u)
        let x11 = lerp(corner(0, 1, 1), corner(1, 1, 1), u)
        let y0 = lerp(x00, x10, v), y1 = lerp(x01, x11, v)
        return lerp(y0, y1, w)
    }
    func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }
    func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    func fastFloor(_ v: Double) -> Int { v >= 0 ? Int(v) : Int(v) - 1 }
    func hash(_ x: Int, _ y: Int, _ z: Int) -> Double {
        var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263 &+ z &* 2_147_483_647))
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h = h ^ (h >> 16)
        return Double(h & 0xFFFFFF) / Double(0xFFFFFF)
    }
}

// MARK: - God Rays frame (mirrors EffectView.drawGodRays)

struct GodRaysFrame: View {
    let time: Double
    let light = Color(red: 1.0, green: 0.85, blue: 0.55)
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.02)))
            let origin = CGPoint(x: size.width * 0.15, y: -size.height * 0.1)
            var beams: [Path] = []
            var breathes: [Double] = []
            for i in 0..<4 {
                let ang = 0.5 + Double(i) * 0.22
                let breathe = 0.4 + 0.6 * abs(sin(time * 0.2 + Double(i)))
                let far = CGPoint(x: origin.x + cos(ang) * size.width * 1.4,
                                  y: origin.y + sin(ang) * size.height * 1.6)
                let w: CGFloat = 40
                var beam = Path()
                beam.move(to: CGPoint(x: origin.x - w, y: origin.y))
                beam.addLine(to: CGPoint(x: origin.x + w, y: origin.y))
                beam.addLine(to: CGPoint(x: far.x + w * 3, y: far.y))
                beam.addLine(to: CGPoint(x: far.x - w * 3, y: far.y))
                beam.closeSubpath()
                beams.append(beam); breathes.append(breathe)
            }
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 24)); l.blendMode = .plusLighter
                for (i, beam) in beams.enumerated() {
                    l.fill(beam, with: .color(light.opacity(0.18 * breathes[i])))
                }
            }
            ctx.drawLayer { l in
                var union = Path(); for beam in beams { union.addPath(beam) }
                l.clip(to: union)
                l.addFilter(.blur(radius: 1.5)); l.blendMode = .plusLighter
                for i in 0..<28 {
                    let x = (Double(hash01(i, 3)) + time * 0.01).truncatingRemainder(dividingBy: 1) * size.width
                    let y = (Double(hash01(i, 5)) + time * 0.02).truncatingRemainder(dividingBy: 1) * size.height
                    let tw = 0.4 + 0.6 * abs(sin(time * 0.9 + Double(i) * 1.7))
                    let r = 1.0 + 1.4 * Double(hash01(i, 8))
                    l.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)),
                           with: .color(light.opacity(0.3 * tw)))
                }
            }
        }
        .frame(width: 500, height: 500)
    }
}

// MARK: - Ink sim (mirrors InkFlowView + InkFlowState), stepped forward

struct InkBlob { var x, y, radius, age: Double; var useAccent: Bool }

final class InkSim {
    var blobs: [InkBlob] = []
    var lastTime: Double?
    var spawnAccum: Double = 0
    var spawnCount = 0
    let field = CurlField()
    let spawnInterval = 1.5, advectSpeed = 0.11, growRate = 0.028, lifespan = 9.0
    let maxBlobs = 40

    func makeBlob(seed: Int) -> InkBlob {
        func h(_ salt: Int) -> Double {
            let v = sin(Double(seed) * 12.9898 + Double(salt) * 78.233) * 43758.5453
            return v - floor(v)
        }
        return InkBlob(x: 0.1 + 0.8 * h(1), y: 0.55 + 0.4 * h(2),
                       radius: 0.02 + 0.03 * h(3), age: 0, useAccent: seed % 2 == 1)
    }

    func step(now: Double) {
        guard now != lastTime else { return }
        let dt = lastTime == nil ? 1.0 / 60 : min(max(now - lastTime!, 0), 0.05)
        lastTime = now
        guard dt > 0 else { return }
        spawnAccum += dt
        while spawnAccum >= spawnInterval && blobs.count < maxBlobs {
            spawnAccum -= spawnInterval
            blobs.append(makeBlob(seed: spawnCount)); spawnCount += 1
        }
        for i in blobs.indices {
            let b = blobs[i]
            let f = field.flow(x: b.x, y: b.y, t: now)
            var nx = b.x + Double(f.dx) * advectSpeed * dt
            var ny = b.y + Double(f.dy) * advectSpeed * dt - 0.012 * dt
            nx = min(max(nx, -0.1), 1.1); ny = min(max(ny, -0.1), 1.1)
            blobs[i].x = nx; blobs[i].y = ny
            blobs[i].radius += growRate * dt; blobs[i].age += dt
        }
        blobs.removeAll { $0.age >= lifespan }
    }
}

struct InkFrame: View {
    let blobs: [InkBlob]
    let lifespan: Double
    let primary = Color(red: 0.15, green: 0.35, blue: 0.95)
    let accent = Color(red: 0.95, green: 0.20, blue: 0.55)
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.02)))
            let w = size.width, h = size.height, minDim = min(w, h)
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 18)); layer.blendMode = .plusLighter
                for b in blobs {
                    let lifeFrac = b.age / lifespan
                    let fadeIn = min(1, b.age / 0.6)
                    let opacity = fadeIn * (1 - lifeFrac) * (1 - lifeFrac) * 0.55
                    guard opacity > 0.003 else { continue }
                    let r = CGFloat(b.radius) * minDim
                    let c = CGPoint(x: CGFloat(b.x) * w, y: CGFloat(b.y) * h)
                    let ink = b.useAccent ? accent : primary
                    layer.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                               with: .color(ink.opacity(opacity)))
                }
            }
        }
        .frame(width: 500, height: 500)
    }
}

// MARK: - Pixel stats

struct PixelStats { let litCount: Int; let variance: Double }

func pixelStats(_ image: NSImage) -> PixelStats {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
        return PixelStats(litCount: 0, variance: 0)
    }
    var lums: [Double] = []
    let w = rep.pixelsWide, h = rep.pixelsHigh
    for y in stride(from: 0, to: h, by: 3) {
        for x in stride(from: 0, to: w, by: 3) {
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            lums.append(0.299 * Double(c.redComponent) + 0.587 * Double(c.greenComponent) + 0.114 * Double(c.blueComponent))
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
    guard let img = renderer.nsImage else { print("FAIL: no image for \(path)"); return PixelStats(litCount: 0, variance: 0) }
    let stats = pixelStats(img)
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) (lit pixels: \(stats.litCount), luminance variance: \(String(format: "%.5f", stats.variance)))")
    }
    return stats
}

let godTimes: [Double] = [0.4, 12.7, 48.3]
var godStats: [PixelStats] = []
var inkStats: [PixelStats] = []

MainActor.assumeIsolated {
    for (i, t) in godTimes.enumerated() {
        godStats.append(render(GodRaysFrame(time: t), path: "/tmp/godrays_t\(i).png"))
    }

    // Step the ink sim forward across many frames (60fps) so blobs spawn,
    // advect, grow and start to fade — then render three snapshots.
    let sim = InkSim()
    var t = 0.0
    let dt = 1.0 / 60
    var snapAt: Set<Int> = [180, 600, 1200]   // ~3s, 10s, 20s
    var frame = 0
    while frame <= 1200 {
        sim.step(now: t)
        if snapAt.contains(frame) {
            let idx = [180, 600, 1200].firstIndex(of: frame)!
            inkStats.append(render(InkFrame(blobs: sim.blobs, lifespan: sim.lifespan),
                                   path: "/tmp/inkflow_f\(idx).png"))
            print("  ink snapshot at frame \(frame): \(sim.blobs.count) live blobs")
            snapAt.remove(frame)
        }
        t += dt; frame += 1
    }
}

let minVariance = 0.00003

for (i, s) in godStats.enumerated() {
    precondition(s.litCount > 0, "god rays frame \(i) should have lit pixels")
    precondition(s.variance > minVariance, "god rays frame \(i) variance too low (flat fill?): \(s.variance)")
}
for (i, s) in inkStats.enumerated() {
    precondition(s.litCount > 0, "ink frame \(i) should have lit pixels (blobs should exist)")
    precondition(s.variance > minVariance, "ink frame \(i) variance too low (flat fill?): \(s.variance)")
}

func framesDiffer(_ a: PixelStats, _ b: PixelStats) -> Bool {
    abs(a.variance - b.variance) > 1e-6 || a.litCount != b.litCount
}
precondition(framesDiffer(godStats[0], godStats[1]) || framesDiffer(godStats[1], godStats[2]),
             "god rays frames should visibly differ across time (breathing beams)")
precondition(framesDiffer(inkStats[0], inkStats[1]) || framesDiffer(inkStats[1], inkStats[2]),
             "ink frames should visibly differ as the sim evolves")

print("PASS: God Rays and Ink in Water render non-blank frames with non-trivial variance; ink sim builds up blobs over stepped frames.")
