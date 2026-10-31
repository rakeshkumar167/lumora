import LumoraKit
import SwiftUI

// Brick Wall effects. Each one lays a `BrickGrid` over the surface and lights
// individual bricks or the mortar between them, so with the grid tuned to a
// real wall the light lands on the actual bricks. Black = unlit wall.
// All are stateless (derived from the global `time`).

// MARK: - Shared helpers

private func brickHash(_ i: Int, _ salt: Int) -> Double {
    let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
    return v - floor(v)
}

private func mix(_ a: RGBAColor, _ b: RGBAColor, _ t: Double) -> Color {
    let t = min(max(t, 0), 1)
    return Color(red: a.r + (b.r - a.r) * t, green: a.g + (b.g - a.g) * t, blue: a.b + (b.b - a.b) * t)
}

private func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = min(max((x - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)
}

/// Draws lit bricks with a soft additive halo underneath the crisp faces.
private func drawLitBricks(_ ctx: GraphicsContext, _ items: [(CGRect, Color)], grid: BrickGrid, glow: Bool = true) {
    let corner = min(grid.joint * 0.6, grid.courseHeight * 0.12)
    if glow {
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: max(2, grid.courseHeight * 0.35)))
            l.blendMode = .plusLighter
            for (r, c) in items { l.fill(Path(roundedRect: r, cornerRadius: corner), with: .color(c)) }
        }
    }
    for (r, c) in items { ctx.fill(Path(roundedRect: r, cornerRadius: corner), with: .color(c)) }
}

/// A faint outline of every brick so the grid reads even where nothing is lit.
private func drawBrickGhosts(_ ctx: GraphicsContext, grid: BrickGrid, color: RGBAColor, opacity: Double) {
    let corner = min(grid.joint * 0.6, grid.courseHeight * 0.12)
    var p = Path()
    for b in grid.bricks { p.addRoundedRect(in: b.rect, cornerSize: CGSize(width: corner, height: corner)) }
    ctx.fill(p, with: .color(color.color.opacity(opacity)))
}

private func blackBackdrop(_ ctx: GraphicsContext, _ size: CGSize) {
    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
}

// MARK: - Brick Cascade

/// Bricks light up in waves, cycling through three choreographies: a diagonal
/// sweep, a ripple from the centre, and a stack that fills from the floor brick
/// by brick (falling into place) before clearing course by course.
struct BrickCascadeView: View {
    let time: Double
    let color: RGBAColor
    let accent: RGBAColor
    let config: BrickWallConfig

    private let modeLength = 10.0

    var body: some View {
        Canvas { ctx, size in
            blackBackdrop(ctx, size)
            let grid = BrickGrid(size: size, config: config)
            drawBrickGhosts(ctx, grid: grid, color: color, opacity: 0.05)

            let cycle = time / modeLength
            let mode = Int(floor(cycle)) % 3
            let local = (cycle - floor(cycle)) * modeLength
            // Fade between choreographies.
            let fade = min(1, local / 0.5, (modeLength - local) / 0.5)
            let w = Double(size.width), h = Double(size.height)

            var items: [(CGRect, Color)] = []
            for b in grid.bricks {
                let u = Double(b.center.x) / w, v = Double(b.center.y) / h
                switch mode {
                case 0:
                    // Diagonal band sweeping bottom-left → top-right, twice per mode,
                    // first in the surface colour then the accent, white-hot at its core.
                    let p = (u + (1 - v)) / 2
                    let pass = local / modeLength * 2
                    let front = (pass - floor(pass)) * 1.6 - 0.3
                    let d = abs(p - front)
                    let lit = max(0, 1 - d / 0.16)
                    guard lit > 0.01 else { continue }
                    let base = Int(floor(pass)) % 2 == 0 ? color : accent
                    items.append((b.rect, mix(base, .white, pow(lit, 4) * 0.6).opacity(lit * fade)))
                case 1:
                    // Rings from the centre (aspect-corrected), alternating colours.
                    let dx = (u - 0.5) * w / max(w, h), dy = (v - 0.5) * h / max(w, h)
                    let d = (dx * dx + dy * dy).squareRoot() * 2
                    let phase = d * 4 - local * 1.1
                    let ring = Int(floor(phase))
                    let wave = pow(max(0, cos((phase - Double(ring)) * .pi * 2 - .pi)), 0.6)
                    let lit = pow(1 - (phase - floor(phase)), 2) * wave
                    guard lit > 0.02 else { continue }
                    items.append((b.rect, (ring % 2 == 0 ? color : accent).color.opacity(lit * fade)))
                default:
                    if let item = stackItem(b, grid: grid, local: local, h: h) {
                        items.append((item.0, item.1.opacity(fade)))
                    }
                }
            }
            drawLitBricks(ctx, items, grid: grid)
        }
    }

    /// Stack mode: each brick drops in from above and lands in order from the
    /// bottom course up; then the full wall clears top-down.
    private func stackItem(_ b: Brick, grid: BrickGrid, local: Double, h: Double) -> (CGRect, Color)? {
        let fillEnd = modeLength * 0.68
        let fromBottom = Double(grid.rows - 1 - b.row)
        let land = 0.4 + (fromBottom + brickHash(b.id, 3) * 0.9) / Double(grid.rows) * (fillEnd - 0.8)
        let fall = 0.45
        guard local > land - fall else { return nil }
        var rect = b.rect
        if local < land {
            let p = (land - local) / fall                     // 1 → 0 while falling
            rect.origin.y -= CGFloat(p * p * Double(b.rect.maxY) * 1.05)
        }
        let c = brickHash(b.id, 7) < 0.5 ? color : accent
        // Clear: flash white then fade, course by course from the top.
        let clearStart = fillEnd + 0.9 + Double(b.row) / Double(grid.rows) * 1.2
        if local > clearStart {
            let k = (local - clearStart) / 0.6
            guard k < 1 else { return nil }
            return (rect, mix(c, .white, 1 - k).opacity(1 - k))
        }
        let landed = local >= land ? max(0, 1 - (local - land) / 0.25) : 0
        return (rect, mix(c, .white, landed * 0.8))
    }
}

// MARK: - Pixel-Art Mural

/// Every brick is one big pixel of a chunky animated scene. Cycles through a
/// sunset over the sea, a rainstorm with lightning, a roaring fire and a
/// rainbow plasma, cross-fading between them. Fixed palettes.
struct BrickMuralView: View {
    let time: Double
    let config: BrickWallConfig

    private let sceneLength = 12.0
    private let crossfade = 1.5

    private typealias RGB = (r: Double, g: Double, b: Double)

    var body: some View {
        Canvas { ctx, size in
            blackBackdrop(ctx, size)
            let grid = BrickGrid(size: size, config: config)
            let idx = Int(floor(time / sceneLength))
            let local = time - Double(idx) * sceneLength
            let blend = smoothstep(sceneLength - crossfade, sceneLength, local)
            let w = Double(size.width), h = Double(size.height)

            var items: [(CGRect, Color)] = []
            items.reserveCapacity(grid.bricks.count)
            for b in grid.bricks {
                let u = Double(b.center.x) / w, v = Double(b.center.y) / h
                var c = scene(idx % 4, u: u, v: v, brick: b, grid: grid, aspect: w / max(h, 1))
                if blend > 0 {
                    let n = scene((idx + 1) % 4, u: u, v: v, brick: b, grid: grid, aspect: w / max(h, 1))
                    c = (c.r + (n.r - c.r) * blend, c.g + (n.g - c.g) * blend, c.b + (n.b - c.b) * blend)
                }
                items.append((b.rect, Color(red: c.r, green: c.g, blue: c.b)))
            }
            drawLitBricks(ctx, items, grid: grid, glow: false)
        }
    }

    private func scene(_ i: Int, u: Double, v: Double, brick: Brick, grid: BrickGrid, aspect: Double) -> RGB {
        switch i {
        case 0: return sunset(u: u, v: v, brick: brick, aspect: aspect)
        case 1: return rain(u: u, v: v, brick: brick, grid: grid)
        case 2: return fire(u: u, v: v)
        default: return plasma(u: u, v: v)
        }
    }

    private func sunset(u: Double, v: Double, brick: Brick, aspect: Double) -> RGB {
        let horizon = 0.62
        let sunY = 0.5 + 0.04 * sin(time * 0.3)
        if v < horizon {
            // Sky: indigo at the top to orange at the horizon, twinkling stars up high.
            let k = v / horizon
            var c: RGB = (0.12 + 0.85 * k * k, 0.04 + 0.35 * k * k * k, 0.25 - 0.1 * k)
            if v < 0.3, brickHash(brick.id, 31) > 0.86 {
                let tw = 0.5 + 0.5 * sin(time * 3 + brickHash(brick.id, 32) * 6)
                c = (c.r + 0.6 * tw, c.g + 0.6 * tw, c.b + 0.5 * tw)
            }
            let dx = (u - 0.5) * aspect, dy = v - sunY
            let d = (dx * dx + dy * dy).squareRoot()
            if d < 0.22 { return (1.0, 0.88 - d * 1.4, 0.3) }
            let haze = max(0, 1 - d / 0.55) * 0.5
            return (min(1, c.r + haze), min(1, c.g + haze * 0.5), c.b)
        }
        // Sea: dark blue with a shimmering orange reflection under the sun.
        let depth = (v - horizon) / (1 - horizon)
        var c: RGB = (0.03, 0.08 + 0.05 * (1 - depth), 0.22 - 0.08 * depth)
        let spread = 0.08 + depth * 0.18
        if abs(u - 0.5) * aspect < spread {
            let sh = brickHash(brick.id, Int(time * 4))
            if sh > 0.35 { c = (0.95 * (1 - depth * 0.5), 0.5 * (1 - depth * 0.6), 0.15) }
        }
        return c
    }

    private func rain(u: Double, v: Double, brick: Brick, grid: BrickGrid) -> RGB {
        var c: RGB = (0.03, 0.05, 0.1 + 0.06 * v)
        // Lightning every ~7 s: a double flicker over the whole wall.
        let lt = time.truncatingRemainder(dividingBy: 7.3)
        let flash = max(0, 1 - abs(lt - 5.0) / 0.08) + 0.7 * max(0, 1 - abs(lt - 5.25) / 0.06)
        c = (c.r + flash * 0.7, c.g + flash * 0.7, c.b + flash * 0.8)
        // Drops: a few lanes per brick column, each a bright head with a trail.
        let lane = Int(floor(u * Double(grid.columns) * 2))
        let rows = Double(grid.rows)
        let speed = 0.9 + 0.6 * brickHash(lane, 41)
        for drop in 0..<2 {
            let phase = time * speed + brickHash(lane, 42) + Double(drop) * (0.4 + 0.2 * brickHash(lane, 43))
            let head = (phase - floor(phase)) * (rows + 6) - 3
            let d = head - Double(brick.row)
            if d >= 0 && d < 4 {
                let k = 1 - d / 4
                c = (c.r + 0.35 * k, c.g + 0.6 * k, c.b + 0.85 * k)
            }
            // Splash on the bottom course.
            if brick.row == grid.rows - 1, head > rows - 1, head < rows + 0.5 {
                c = (c.r + 0.5, c.g + 0.7, c.b + 0.9)
            }
        }
        return (min(1, c.r), min(1, c.g), min(1, c.b))
    }

    private func fire(u: Double, v: Double) -> RGB {
        let up = 1 - v                                          // 0 bottom … 1 top
        let n = valueNoise(u * 5, up * 4 - time * 2.2) * 0.6 + valueNoise(u * 11, up * 8 - time * 3.5) * 0.4
        let heat = min(1, max(0, (1 - up) * 1.35 - 0.35 + (n - 0.5) * 0.9))
        // black → red → orange → yellow → white
        return (min(1, heat * 2.2), min(1, max(0, heat * 2 - 0.6)), min(1, max(0, heat * 3 - 2.2)))
    }

    private func plasma(u: Double, v: Double) -> RGB {
        let t = time * 0.6
        let p = sin(u * 7 + t) + sin(v * 6 - t * 1.3) + sin((u + v) * 5 + t * 0.7)
            + sin(((u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5)).squareRoot() * 12 - t * 2)
        let hue = p / 8 + 0.5 + t * 0.05
        return (0.5 + 0.5 * cos(.pi * 2 * hue),
                0.5 + 0.5 * cos(.pi * 2 * (hue + 0.33)),
                0.5 + 0.5 * cos(.pi * 2 * (hue + 0.67)))
    }

    /// Smooth 2D value noise in 0…1.
    private func valueNoise(_ x: Double, _ y: Double) -> Double {
        let xi = floor(x), yi = floor(y)
        let fx = x - xi, fy = y - yi
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        func h(_ a: Double, _ b: Double) -> Double {
            let v = sin(a * 127.1 + b * 311.7) * 43758.5453
            return v - floor(v)
        }
        let a = h(xi, yi), b = h(xi + 1, yi), c = h(xi, yi + 1), d = h(xi + 1, yi + 1)
        return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy
    }
}
