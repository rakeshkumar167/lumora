import LumoraKit
import SwiftUI

// MARK: - Effect 5: Diwali Skyline

/// **Diwali Skyline** — a lit palace on the river under a firework night.
/// Peony, ring and willow bursts rise and explode over the domes (a fresh
/// position, style and colour every cycle), the sky flashes, and every window
/// and parapet diya is mirrored in rippling water. Stateless.
struct DiwaliSkylineView: View {
    let time: Double

    private let slots = 5

    var body: some View {
        Canvas { ctx, size in draw(ctx: ctx, size: size) }
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }
        let waterY = h * 0.78

        // Sky
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [
                    Color(red: 0.01, green: 0.01, blue: 0.06),
                    Color(red: 0.07, green: 0.03, blue: 0.14),
                    Color(red: 0.25, green: 0.07, blue: 0.12),
                 ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: waterY)))
        for i in 0..<80 {
            let tw = 0.4 + 0.6 * (0.5 + 0.5 * sin(time * (0.7 + Double(DiwaliPalette.hash01(i, 501))) + Double(i)))
            let s = 0.8 + 1.2 * DiwaliPalette.hash01(i, 502)
            ctx.fill(Path(ellipseIn: CGRect(x: DiwaliPalette.hash01(i, 503) * w, y: DiwaliPalette.hash01(i, 504) * waterY * 0.7, width: s, height: s)),
                     with: .color(Color.white.opacity(0.5 * tw)))
        }

        // Fireworks (behind the palace), collecting this frame's flash for the water.
        var flashes: [(CGPoint, Color, Double)] = []
        for k in 0..<slots {
            if let f = firework(ctx: ctx, size: size, slot: k, waterY: waterY) { flashes.append(f) }
        }

        // Palace
        let lights = drawPalace(ctx: ctx, size: size, waterY: waterY)

        // River
        drawWater(ctx: ctx, size: size, waterY: waterY, lights: lights, flashes: flashes)
    }

    // MARK: Fireworks

    private func firework(ctx: GraphicsContext, size: CGSize, slot: Int, waterY: CGFloat) -> (CGPoint, Color, Double)? {
        let w = size.width
        let period = 4.2 + 0.5 * Double(slot)
        let offset = Double(slot) * 1.3
        let local = time + offset
        let n = Int(floor(local / period))
        let tt = local - Double(n) * period                      // seconds into this cycle
        let seed = n * 7 + slot * 131

        let bx = w * (0.12 + 0.76 * DiwaliPalette.hash01(seed, 511))
        let by = waterY * (0.14 + 0.36 * DiwaliPalette.hash01(seed, 512))
        let styleN = Int(DiwaliPalette.hash01(seed, 513) * 3)    // 0 peony, 1 ring, 2 willow
        let hues: [Color] = [
            Color(red: 1.0, green: 0.35, blue: 0.3), Color(red: 1.0, green: 0.75, blue: 0.2),
            Color(red: 0.4, green: 0.9, blue: 1.0), Color(red: 0.8, green: 0.4, blue: 1.0),
            Color(red: 0.5, green: 1.0, blue: 0.5), Color(red: 1.0, green: 0.55, blue: 0.85),
        ]
        let col = styleN == 2 ? Color(red: 1.0, green: 0.78, blue: 0.3) : hues[Int(DiwaliPalette.hash01(seed, 514) * 6) % 6]
        let col2 = hues[Int(DiwaliPalette.hash01(seed, 515) * 6) % 6]
        let riseT = 1.0
        let burstLife = styleN == 2 ? 3.2 : 2.4
        let launchX = bx + CGFloat(DiwaliPalette.hash01(seed, 516) - 0.5) * w * 0.05

        if tt < riseT {
            // Rocket climbing with a thin spark tail.
            let q = tt / riseT
            let ease = 1 - pow(1 - q, 2)
            let pos = CGPoint(x: launchX + (bx - launchX) * CGFloat(ease), y: waterY - (waterY - by) * CGFloat(ease))
            let tail = CGPoint(x: pos.x - (bx - launchX) * 0.05, y: pos.y + (waterY - by) * 0.07)
            var p = Path(); p.move(to: tail); p.addLine(to: pos)
            ctx.drawLayer { l in
                l.blendMode = .plusLighter
                l.stroke(p, with: .color(Color(red: 1, green: 0.85, blue: 0.5).opacity(0.9)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            return nil
        }
        let b = tt - riseT
        guard b < burstLife else { return nil }
        let u = b / burstLife
        let c = CGPoint(x: bx, y: by)
        let unit = min(size.width, size.height)
        let R = Double(unit) * (styleN == 2 ? 0.30 : 0.26)

        // Flash glow at the moment of burst.
        let flash = max(0, 1 - b / 0.6)
        if flash > 0 {
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 20))
                l.blendMode = .plusLighter
                let g = CGFloat(R) * 1.3
                l.fill(Path(ellipseIn: CGRect(x: c.x - g, y: c.y - g, width: g * 2, height: g * 2)),
                       with: .radialGradient(Gradient(colors: [col.opacity(0.45 * flash), .clear]), center: c, startRadius: 0, endRadius: g))
            }
        }

        var pathsA = Path(), pathsB = Path(), glints = Path()
        let count = styleN == 1 ? 70 : 110
        for i in 0..<count {
            let h1 = Double(DiwaliPalette.hash01(seed * 3 + i, 521)), h2 = Double(DiwaliPalette.hash01(seed * 3 + i, 522))
            var ang = h1 * 2 * Double.pi
            var speed = R * (0.55 + 0.45 * h2)
            if styleN == 0 { speed = R * (0.35 + 0.65 * sqrt(h2)) }
            if styleN == 1 { ang = Double(i) / Double(count) * 2 * Double.pi; speed = R * 0.8 }
            let drag = styleN == 2 ? 2.0 : 2.6
            func pos(_ t: Double) -> CGPoint {
                let k = (1 - exp(-drag * t)) / drag
                let grav = (styleN == 2 ? 0.55 : 0.32) * R * t * t
                var dx = cos(ang) * speed * k
                var dy = sin(ang) * speed * k + grav
                if styleN == 1 { dy = sin(ang) * speed * k * 0.9 + grav * 0.6; dx = cos(ang) * speed * k }
                return CGPoint(x: c.x + CGFloat(dx), y: c.y + CGFloat(dy))
            }
            let tau = b
            let trail = styleN == 2 ? 0.34 : 0.12
            let p1 = pos(tau), p0 = pos(max(0, tau - trail))
            if i % 2 == 0 { pathsA.move(to: p0); pathsA.addLine(to: p1) } else { pathsB.move(to: p0); pathsB.addLine(to: p1) }
            // Twinkling glitter at the head late in life.
            if u > 0.55 && sin(time * 30 + Double(i) * 2.1) > 0.6 {
                glints.addEllipse(in: CGRect(x: p1.x - 1.2, y: p1.y - 1.2, width: 2.4, height: 2.4))
            }
        }
        let fade = pow(1 - u, 1.4)
        let col2Use = styleN == 2 ? col : col2
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            l.stroke(pathsA, with: .color(col.opacity(0.95 * fade)), style: StrokeStyle(lineWidth: 2.0, lineCap: .round))
            l.stroke(pathsB, with: .color(col2Use.opacity(0.9 * fade)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            l.fill(glints, with: .color(Color.white.opacity(0.9 * fade)))
        }
        return (c, col, flash * 0.6 + (1 - u) * 0.4)
    }

    // MARK: Palace

    /// Draws the palace silhouette and returns the lit points (for reflection).
    private func drawPalace(ctx: GraphicsContext, size: CGSize, waterY: CGFloat) -> [(CGPoint, Color)] {
        let w = size.width
        let unit = min(size.width, size.height)
        let ink = Color(red: 0.03, green: 0.012, blue: 0.04)
        var lights: [(CGPoint, Color)] = []
        var body = Path()
        let baseY = waterY

        // Long arcaded hall.
        let hallTop = baseY - unit * 0.14
        body.addRect(CGRect(x: w * 0.05, y: hallTop, width: w * 0.9, height: unit * 0.14))
        // Central grand dome + drum + kalash.
        func dome(_ cx: CGFloat, _ rBase: CGFloat, _ drumH: CGFloat, _ y0: CGFloat) {
            body.addRect(CGRect(x: cx - rBase, y: y0 - drumH, width: rBase * 2, height: drumH))
            var d = Path()
            d.move(to: CGPoint(x: cx - rBase * 1.1, y: y0 - drumH))
            d.addCurve(to: CGPoint(x: cx, y: y0 - drumH - rBase * 1.9),
                       control1: CGPoint(x: cx - rBase * 1.3, y: y0 - drumH - rBase * 1.1),
                       control2: CGPoint(x: cx - rBase * 0.5, y: y0 - drumH - rBase * 1.7))
            d.addCurve(to: CGPoint(x: cx + rBase * 1.1, y: y0 - drumH),
                       control1: CGPoint(x: cx + rBase * 0.5, y: y0 - drumH - rBase * 1.7),
                       control2: CGPoint(x: cx + rBase * 1.3, y: y0 - drumH - rBase * 1.1))
            d.closeSubpath()
            body.addPath(d)
            body.addRect(CGRect(x: cx - 1.2, y: y0 - drumH - rBase * 2.5, width: 2.4, height: rBase * 0.7))
            body.addEllipse(in: CGRect(x: cx - rBase * 0.1, y: y0 - drumH - rBase * 2.05, width: rBase * 0.2, height: rBase * 0.3))
        }
        dome(w * 0.5, unit * 0.1, unit * 0.1, hallTop)
        dome(w * 0.27, unit * 0.055, unit * 0.06, hallTop)
        dome(w * 0.73, unit * 0.055, unit * 0.06, hallTop)
        // Minarets with chhatri caps at the ends.
        for fx in [CGFloat(0.07), CGFloat(0.93), CGFloat(0.37), CGFloat(0.63)] {
            let cx = w * fx
            let mh = unit * (fx < 0.2 || fx > 0.8 ? 0.34 : 0.22)
            body.addRect(CGRect(x: cx - unit * 0.012, y: hallTop - mh, width: unit * 0.024, height: mh))
            var cap = Path()
            cap.move(to: CGPoint(x: cx - unit * 0.022, y: hallTop - mh))
            cap.addQuadCurve(to: CGPoint(x: cx, y: hallTop - mh - unit * 0.045), control: CGPoint(x: cx - unit * 0.02, y: hallTop - mh - unit * 0.03))
            cap.addQuadCurve(to: CGPoint(x: cx + unit * 0.022, y: hallTop - mh), control: CGPoint(x: cx + unit * 0.02, y: hallTop - mh - unit * 0.03))
            cap.closeSubpath()
            body.addPath(cap)
        }
        ctx.fill(body, with: .color(ink))

        // Arched windows in three rows, each flickering independently.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 1.5))
            l.blendMode = .plusLighter
            let cols = 22
            for row in 0..<2 {
                for i in 0..<cols {
                    let fx = 0.075 + 0.85 * (CGFloat(i) + 0.5) / CGFloat(cols)
                    let on = DiwaliPalette.fract(time * 0.05 + Double(DiwaliPalette.hash01(i * 3 + row, 531))) < 0.9
                    if !on { continue }
                    let f = 0.65 + 0.3 * sin(time * (4 + 3 * Double(DiwaliPalette.hash01(i, 532))) + Double(i * 5 + row))
                    let ww = unit * 0.014, wh = unit * 0.03
                    let x = w * fx - ww / 2
                    let y = hallTop + unit * (0.025 + 0.055 * CGFloat(row))
                    var arch = Path(CGRect(x: x, y: y + ww / 2, width: ww, height: wh - ww / 2))
                    arch.addEllipse(in: CGRect(x: x, y: y, width: ww, height: ww))
                    let warm = Color(red: 1, green: 0.62 + 0.2 * Double(DiwaliPalette.hash01(i, 533)), blue: 0.18)
                    l.fill(arch, with: .color(warm.opacity(f)))
                    lights.append((CGPoint(x: x + ww / 2, y: y + wh / 2), warm.opacity(f)))
                }
            }
        }
        // Parapet diyas.
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            for i in 0..<60 {
                let x = w * 0.05 + w * 0.9 * (CGFloat(i) + 0.5) / 60
                let f = 0.55 + 0.45 * sin(time * 6 + Double(i) * 2.7)
                let r = unit * 0.0045
                let pt = CGPoint(x: x, y: hallTop - r)
                l.fill(Path(ellipseIn: CGRect(x: pt.x - r, y: pt.y - r, width: r * 2, height: r * 2)),
                       with: .color(Color(red: 1, green: 0.78, blue: 0.3).opacity(f)))
                if i % 3 == 0 { lights.append((pt, Color(red: 1, green: 0.78, blue: 0.3).opacity(f))) }
            }
        }
        return lights
    }

    // MARK: Water

    private func drawWater(ctx: GraphicsContext, size: CGSize, waterY: CGFloat, lights: [(CGPoint, Color)], flashes: [(CGPoint, Color, Double)]) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(x: 0, y: waterY, width: w, height: h - waterY)),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.09, green: 0.03, blue: 0.09), Color(red: 0.01, green: 0.01, blue: 0.04)]),
                                       startPoint: CGPoint(x: 0, y: waterY), endPoint: CGPoint(x: 0, y: h)))
        // Reflected lights as wobbling vertical streaks.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 2.5))
            l.blendMode = .plusLighter
            for (i, item) in lights.enumerated() {
                let (p, col) = item
                let dist = p.y - (waterY - min(w, h) * 0.14)
                let ry = waterY + (waterY - p.y) * 0.55
                let wob = CGFloat(sin(time * 2 + Double(i) * 0.9)) * 3
                let len = min(w, h) * 0.035
                var s = Path()
                s.move(to: CGPoint(x: p.x + wob, y: ry - len / 2))
                s.addLine(to: CGPoint(x: p.x - wob, y: ry + len / 2))
                _ = dist
                l.stroke(s, with: .color(col.opacity(0.45)), style: StrokeStyle(lineWidth: max(1.5, min(w, h) * 0.006), lineCap: .round))
            }
            // Firework glow pooling on the water.
            for (c, col, k) in flashes {
                let g = min(w, h) * 0.25
                let rc = CGPoint(x: c.x, y: waterY + (waterY - c.y) * 0.25)
                l.fill(Path(ellipseIn: CGRect(x: rc.x - g, y: rc.y - g * 0.18, width: g * 2, height: g * 0.36)),
                       with: .radialGradient(Gradient(colors: [col.opacity(0.35 * k), .clear]), center: rc, startRadius: 0, endRadius: g))
            }
        }
        // Ripple lines.
        var rip = Path()
        for i in 0..<14 {
            let y = waterY + (h - waterY) * (CGFloat(i) + 0.5) / 14
            let x0 = w * CGFloat(DiwaliPalette.fract(time * 0.02 + Double(DiwaliPalette.hash01(i, 541))))
            rip.move(to: CGPoint(x: x0, y: y)); rip.addLine(to: CGPoint(x: x0 + w * 0.08, y: y))
        }
        ctx.stroke(rip, with: .color(Color.white.opacity(0.07)), lineWidth: 1)
    }
}

// MARK: - Effect 6: Marigold Toran

/// **Marigold Toran** — festive door-hangings: swags of marigold flowers and
/// mango leaves strung across the top, vertical flower strings with brass
/// bells swaying beneath, and twinkling fairy lights along each wire, over a
/// deep maroon wall with soft bokeh. Stateless.
struct MarigoldToranView: View {
    let time: Double

    var body: some View {
        Canvas { ctx, size in draw(ctx: ctx, size: size) }
    }

    private struct Swag {
        var y0: CGFloat       // end heights as fractions of h
        var y1: CGFloat
        var sag: CGFloat      // fraction of h
        var flowers: Int
        var scale: CGFloat
        var phase: Double
        var dim: Double       // depth dimming
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }
        let unit = min(w, h)

        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(colors: [Color(red: 0.28, green: 0.05, blue: 0.08), Color(red: 0.07, green: 0.01, blue: 0.03)]),
                                       center: CGPoint(x: w / 2, y: h * 0.35), startRadius: 0, endRadius: max(w, h) * 0.8))
        // Wall bokeh.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 18))
            l.blendMode = .plusLighter
            for i in 0..<18 {
                let r = unit * (0.02 + 0.05 * DiwaliPalette.hash01(i, 601))
                let x = DiwaliPalette.hash01(i, 602) * w
                let y = DiwaliPalette.hash01(i, 603) * h
                let a = 0.07 + 0.08 * sin(time * 0.5 + Double(i))
                l.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                       with: .color(DiwaliPalette.gold.opacity(max(0, a))))
            }
        }

        // Back swag (dimmer, higher), then the main front swags.
        let swags: [Swag] = [
            Swag(y0: 0.02, y1: 0.02, sag: 0.15, flowers: 22, scale: 0.7, phase: 1.3, dim: 0.65),
            Swag(y0: 0.0, y1: 0.0, sag: 0.22, flowers: 20, scale: 1.0, phase: 0.0, dim: 1.0),
        ]
        for (i, sg) in swags.enumerated() {
            drawSwag(ctx: ctx, size: size, swag: sg, index: i, hangings: i == 1)
        }
    }

    private func swagPoint(_ s: CGFloat, size: CGSize, swag: Swag) -> CGPoint {
        let w = size.width, h = size.height
        let x = -w * 0.02 + (w * 1.04) * s
        let baseY = h * (swag.y0 + (swag.y1 - swag.y0) * s)
        let sag = h * swag.sag * 4 * s * (1 - s)
        let sway = CGFloat(sin(time * 0.7 + swag.phase + Double(s) * 3)) * h * 0.004 * (4 * s * (1 - s))
        return CGPoint(x: x, y: baseY + sag + sway)
    }

    private func drawSwag(ctx: GraphicsContext, size: CGSize, swag: Swag, index: Int, hangings: Bool) {
        let unit = min(size.width, size.height)
        let n = swag.flowers
        let fr = unit * 0.036 * swag.scale

        // Wire
        var wire = Path()
        for k in 0...60 {
            let p = swagPoint(CGFloat(k) / 60, size: size, swag: swag)
            if k == 0 { wire.move(to: p) } else { wire.addLine(to: p) }
        }
        ctx.stroke(wire, with: .color(DiwaliPalette.gold.opacity(0.6 * swag.dim)), lineWidth: max(1, unit * 0.002))

        var leaves = Path(), outerP = Path(), innerP = Path(), centreP = Path(), outer2 = Path()
        for i in 0..<n {
            let s = (CGFloat(i) + 0.5) / CGFloat(n)
            let p = swagPoint(s, size: size, swag: swag)
            let q = swagPoint(min(1, s + 0.01), size: size, swag: swag)
            let tang = atan2(q.y - p.y, q.x - p.x)
            // Mango leaves flanking each flower.
            for side in [CGFloat(-1), CGFloat(1)] {
                let lp = swagPoint(s + side * 0.5 / CGFloat(n), size: size, swag: swag)
                let ang = tang + Double.pi / 2 + Double(side) * 0.25 + 0.2 * sin(time * 1.1 + Double(i) + Double(side))
                leaves.addPath(leaf(at: lp, length: fr * 2.4, angle: ang))
            }
            // Marigold: outer petals, inner petals, dark eye.
            let flower = i % 2 == 0
            let pc = p
            let petals = 11
            for k in 0..<petals {
                let a = Double(k) / Double(petals) * 2 * Double.pi + Double(i)
                let pe = CGPoint(x: pc.x + CGFloat(cos(a)) * fr * 0.62, y: pc.y + CGFloat(sin(a)) * fr * 0.62)
                let rr = fr * 0.42
                let rect = CGRect(x: pe.x - rr, y: pe.y - rr, width: rr * 2, height: rr * 2)
                if flower { outerP.addEllipse(in: rect) } else { outer2.addEllipse(in: rect) }
            }
            for k in 0..<7 {
                let a = Double(k) / 7 * 2 * Double.pi + Double(i) * 1.3
                let pe = CGPoint(x: pc.x + CGFloat(cos(a)) * fr * 0.3, y: pc.y + CGFloat(sin(a)) * fr * 0.3)
                let rr = fr * 0.3
                innerP.addEllipse(in: CGRect(x: pe.x - rr, y: pe.y - rr, width: rr * 2, height: rr * 2))
            }
            centreP.addEllipse(in: CGRect(x: pc.x - fr * 0.14, y: pc.y - fr * 0.14, width: fr * 0.28, height: fr * 0.28))
        }
        let d = swag.dim
        ctx.fill(leaves, with: .color(Color(red: 0.12, green: 0.5, blue: 0.18).opacity(d)))
        ctx.fill(outerP, with: .color(Color(red: 1.0, green: 0.52, blue: 0.05).opacity(d)))
        ctx.fill(outer2, with: .color(Color(red: 1.0, green: 0.74, blue: 0.08).opacity(d)))
        ctx.fill(innerP, with: .color(Color(red: 1.0, green: 0.86, blue: 0.3).opacity(0.85 * d)))
        ctx.fill(centreP, with: .color(Color(red: 0.55, green: 0.2, blue: 0.02).opacity(d)))

        // Fairy lights hanging just under the garland.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: unit * 0.006))
            l.blendMode = .plusLighter
            let bulbs = 56
            for i in 0..<bulbs {
                let s = (CGFloat(i) + 0.5) / CGFloat(bulbs)
                let p = swagPoint(s, size: size, swag: swag)
                let f = 0.35 + 0.65 * pow(max(0, sin(time * (1.5 + 2 * Double(DiwaliPalette.hash01(i, 611))) + Double(i) * 1.7)), 2)
                let r = unit * 0.006 * swag.scale
                let c = i % 3 == 0 ? Color(red: 1, green: 0.5, blue: 0.7) : (i % 3 == 1 ? Color(red: 1, green: 0.85, blue: 0.4) : Color(red: 0.6, green: 1, blue: 0.7))
                l.fill(Path(ellipseIn: CGRect(x: p.x - r * 3, y: p.y + fr * 0.95 - r * 3, width: r * 6, height: r * 6)),
                       with: .color(c.opacity(0.25 * f * d)))
                l.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y + fr * 0.95 - r, width: r * 2, height: r * 2)),
                       with: .color(c.opacity(f * d)))
            }
        }

        if hangings {
            let strands = 9
            for k in 0..<strands {
                let s = (CGFloat(k) + 0.5) / CGFloat(strands)
                let top = swagPoint(s, size: size, swag: swag)
                let depth = 1 - abs(2 * s - 1)               // longer toward the middle
                let m = 6 + Int(depth * 7) + (k % 3)
                drawHanging(ctx: ctx, size: size, top: top, count: m, index: k, fr: fr * 0.85)
            }
        }
    }

    private func leaf(at p: CGPoint, length: CGFloat, angle: Double) -> Path {
        let xf = CGAffineTransform(translationX: p.x, y: p.y).rotated(by: angle)
        var l = Path()
        l.move(to: .zero)
        l.addQuadCurve(to: CGPoint(x: length, y: 0), control: CGPoint(x: length * 0.5, y: -length * 0.32))
        l.addQuadCurve(to: .zero, control: CGPoint(x: length * 0.5, y: length * 0.32))
        return l.applying(xf)
    }

    /// A pendulum string of flowers ending in a brass bell.
    private func drawHanging(ctx: GraphicsContext, size: CGSize, top: CGPoint, count: Int, index: Int, fr: CGFloat) {
        let ph = Double(index) * 1.9
        let spacing = fr * 1.55
        var pts: [CGPoint] = []
        for i in 0..<count {
            let f = CGFloat(i + 1) / CGFloat(count + 1)
            let swing = CGFloat(sin(time * 0.9 + ph)) * spacing * 0.35 * f * f * 3
            pts.append(CGPoint(x: top.x + swing, y: top.y + spacing * CGFloat(i + 1)))
        }
        var thread = Path()
        thread.move(to: top)
        for p in pts { thread.addLine(to: p) }
        let last = pts.last ?? top
        let bell = CGPoint(x: last.x + CGFloat(sin(time * 0.9 + ph)) * fr * 0.15, y: last.y + spacing * 0.95)
        thread.addLine(to: bell)
        ctx.stroke(thread, with: .color(DiwaliPalette.gold.opacity(0.6)), lineWidth: max(1, fr * 0.08))

        var outerP = Path(), innerP = Path(), outer2 = Path(), leaves = Path()
        for (i, c) in pts.enumerated() {
            if i % 2 == 1 { leaves.addPath(leaf(at: c, length: fr * 1.5, angle: Double.pi / 2 + 0.7)); leaves.addPath(leaf(at: c, length: fr * 1.5, angle: Double.pi / 2 - 0.7)) }
            let orange = (i + index) % 2 == 0
            for k in 0..<9 {
                let a = Double(k) / 9 * 2 * Double.pi + Double(i)
                let pe = CGPoint(x: c.x + CGFloat(cos(a)) * fr * 0.6, y: c.y + CGFloat(sin(a)) * fr * 0.6)
                let rr = fr * 0.42
                let rect = CGRect(x: pe.x - rr, y: pe.y - rr, width: rr * 2, height: rr * 2)
                if orange { outerP.addEllipse(in: rect) } else { outer2.addEllipse(in: rect) }
            }
            innerP.addEllipse(in: CGRect(x: c.x - fr * 0.45, y: c.y - fr * 0.45, width: fr * 0.9, height: fr * 0.9))
        }
        ctx.fill(leaves, with: .color(Color(red: 0.12, green: 0.5, blue: 0.18)))
        ctx.fill(outerP, with: .color(Color(red: 1.0, green: 0.52, blue: 0.05)))
        ctx.fill(outer2, with: .color(Color(red: 1.0, green: 0.74, blue: 0.08)))
        ctx.fill(innerP, with: .color(Color(red: 1.0, green: 0.86, blue: 0.3).opacity(0.9)))

        // Brass bell with clapper and a glint.
        let br = fr * 0.62
        var b = Path()
        b.move(to: CGPoint(x: bell.x - br, y: bell.y + br * 0.9))
        b.addQuadCurve(to: CGPoint(x: bell.x, y: bell.y - br), control: CGPoint(x: bell.x - br * 1.1, y: bell.y - br * 0.4))
        b.addQuadCurve(to: CGPoint(x: bell.x + br, y: bell.y + br * 0.9), control: CGPoint(x: bell.x + br * 1.1, y: bell.y - br * 0.4))
        b.closeSubpath()
        ctx.fill(b, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.88, blue: 0.4), Color(red: 0.7, green: 0.45, blue: 0.08)]),
                                          startPoint: CGPoint(x: bell.x - br, y: bell.y), endPoint: CGPoint(x: bell.x + br, y: bell.y)))
        ctx.fill(Path(ellipseIn: CGRect(x: bell.x - br * 0.2, y: bell.y + br * 0.8, width: br * 0.4, height: br * 0.4)),
                 with: .color(Color(red: 0.7, green: 0.45, blue: 0.08)))
    }
}
