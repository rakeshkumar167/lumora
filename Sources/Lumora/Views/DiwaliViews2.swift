import LumoraKit
import SwiftUI

// MARK: - Effect 3: Sky Lanterns

/// **Sky Lanterns** — glowing paper akash kandils float up through a deep
/// indigo-to-maroon night, near ones large and fast, far ones small and soft,
/// over a lit temple silhouette on the horizon. Stateless.
struct SkyLanternsView: View {
    let time: Double

    private let count = 34

    var body: some View {
        Canvas { ctx, size in draw(ctx: ctx, size: size) }
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }
        let unit = min(w, h)

        // Sky: indigo overhead warming to a maroon-orange horizon.
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [
                    Color(red: 0.03, green: 0.02, blue: 0.12),
                    Color(red: 0.16, green: 0.05, blue: 0.20),
                    Color(red: 0.45, green: 0.13, blue: 0.12),
                 ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        for i in 0..<70 {
            let tw = 0.4 + 0.6 * (0.5 + 0.5 * sin(time * (0.8 + Double(DiwaliPalette.hash01(i, 301))) + Double(i)))
            let s = 0.8 + 1.4 * DiwaliPalette.hash01(i, 302)
            ctx.fill(Path(ellipseIn: CGRect(x: DiwaliPalette.hash01(i, 303) * w, y: DiwaliPalette.hash01(i, 304) * h * 0.6, width: s, height: s)),
                     with: .color(Color.white.opacity(0.55 * tw)))
        }
        // Crescent moon.
        let mc = CGPoint(x: w * 0.14, y: h * 0.16), mr = unit * 0.05
        ctx.drawLayer { l in
            l.fill(Path(ellipseIn: CGRect(x: mc.x - mr, y: mc.y - mr, width: mr * 2, height: mr * 2)),
                   with: .color(Color(red: 1, green: 0.93, blue: 0.75).opacity(0.92)))
            l.blendMode = .destinationOut
            l.fill(Path(ellipseIn: CGRect(x: mc.x - mr * 0.45, y: mc.y - mr * 1.15, width: mr * 2, height: mr * 2)),
                   with: .color(Color.black))
        }

        drawTemple(ctx: ctx, size: size)

        // Lanterns, far to near.
        let order = (0..<count).sorted { DiwaliPalette.hash01($0, 311) < DiwaliPalette.hash01($1, 311) }
        for i in order {
            let depth = DiwaliPalette.hash01(i, 311)                       // 0 far … 1 near
            let sz = unit * (0.028 + 0.075 * depth)
            let speed = 0.012 + 0.03 * Double(depth)
            let u = DiwaliPalette.fract(time * speed + Double(DiwaliPalette.hash01(i, 312)))
            let x = DiwaliPalette.hash01(i, 313) * w + CGFloat(sin(time * 0.5 + Double(i) * 1.7)) * sz * 0.9
            let y = h * (1.08 - 1.2 * CGFloat(u))
            let vis = min(1, u * 8) * min(1, (1 - u) * 5)
            lantern(ctx: ctx, at: CGPoint(x: x, y: y), size: sz, depth: depth, index: i, alpha: Double(vis))
        }
    }

    private func lantern(ctx: GraphicsContext, at c: CGPoint, size s: CGFloat, depth: CGFloat, index: Int, alpha: Double) {
        guard alpha > 0.01 else { return }
        let flick = 0.88 + 0.08 * sin(time * 6 + Double(index) * 2) + 0.04 * sin(time * 13.1 + Double(index))
        let tilt = CGFloat(sin(time * 0.6 + Double(index))) * 0.08
        let xf = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: Double(tilt))
        let tw = s * 0.42, bw = s * 0.30, hh = s * 0.62

        // Halo.
        let g = s * 2.6
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: s * 0.5))
            l.blendMode = .plusLighter
            l.fill(Path(ellipseIn: CGRect(x: c.x - g, y: c.y - g, width: g * 2, height: g * 2)),
                   with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.55, blue: 0.12).opacity(0.5 * flick * alpha * (0.4 + 0.6 * Double(depth))), .clear]),
                                         center: c, startRadius: 0, endRadius: g))
        }

        // Paper body: rounded, wider at the shoulder, narrowing to the base.
        var body = Path()
        body.move(to: CGPoint(x: -tw * 0.7, y: -hh))
        body.addQuadCurve(to: CGPoint(x: -tw, y: -hh * 0.2), control: CGPoint(x: -tw * 1.02, y: -hh * 0.8))
        body.addQuadCurve(to: CGPoint(x: -bw, y: hh), control: CGPoint(x: -tw * 0.95, y: hh * 0.6))
        body.addLine(to: CGPoint(x: bw, y: hh))
        body.addQuadCurve(to: CGPoint(x: tw, y: -hh * 0.2), control: CGPoint(x: tw * 0.95, y: hh * 0.6))
        body.addQuadCurve(to: CGPoint(x: tw * 0.7, y: -hh), control: CGPoint(x: tw * 1.02, y: -hh * 0.8))
        body.closeSubpath()
        let bp = body.applying(xf)
        ctx.drawLayer { l in
            l.opacity = alpha
            l.fill(bp, with: .linearGradient(Gradient(colors: [
                Color(red: 0.85, green: 0.25, blue: 0.05),
                Color(red: 1.0, green: 0.58, blue: 0.12),
                Color(red: 1.0, green: 0.88, blue: 0.45),
            ]), startPoint: CGPoint(x: c.x, y: c.y - hh), endPoint: CGPoint(x: c.x, y: c.y + hh)))
        }
        // Ribs.
        var ribs = Path()
        for k in [-0.5, 0.0, 0.5] {
            ribs.move(to: CGPoint(x: k * tw * 1.3, y: -hh * 0.95))
            ribs.addQuadCurve(to: CGPoint(x: k * bw * 1.5, y: hh), control: CGPoint(x: k * tw * 1.7, y: 0))
        }
        ctx.stroke(ribs.applying(xf), with: .color(Color(red: 0.5, green: 0.12, blue: 0.02).opacity(0.5 * alpha)), lineWidth: max(0.6, s * 0.02))
        // Inner flame light.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: s * 0.1))
            l.blendMode = .plusLighter
            let fr = s * 0.28
            let fc = CGPoint(x: c.x + tilt * hh * 0.6, y: c.y + hh * 0.55)
            l.fill(Path(ellipseIn: CGRect(x: fc.x - fr, y: fc.y - fr * 1.4, width: fr * 2, height: fr * 2.8)),
                   with: .color(Color(red: 1, green: 0.9, blue: 0.5).opacity(0.7 * flick * alpha)))
        }
        // Decorative gold band + tassel.
        var band = Path()
        band.move(to: CGPoint(x: -tw * 0.98, y: -hh * 0.05)); band.addLine(to: CGPoint(x: tw * 0.98, y: -hh * 0.05))
        ctx.stroke(band.applying(xf), with: .color(Color(red: 1, green: 0.8, blue: 0.3).opacity(0.6 * alpha)), lineWidth: max(0.8, s * 0.035))
        var tassel = Path()
        tassel.move(to: CGPoint(x: 0, y: hh)); tassel.addLine(to: CGPoint(x: CGFloat(sin(time * 1.5 + Double(index))) * s * 0.06, y: hh + s * 0.35))
        ctx.stroke(tassel.applying(xf), with: .color(Color(red: 1, green: 0.78, blue: 0.3).opacity(0.8 * alpha)), lineWidth: max(0.8, s * 0.03))
    }

    /// A shikhara-style temple on the horizon, glowing windows and a row of tiny
    /// diyas along its base.
    private func drawTemple(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let ink = Color(red: 0.05, green: 0.015, blue: 0.05)
        let base = h * 0.94
        let cx = w * 0.5
        let u = min(w, h)

        var hills = Path()
        hills.move(to: CGPoint(x: 0, y: h))
        hills.addLine(to: CGPoint(x: 0, y: h * 0.9))
        hills.addQuadCurve(to: CGPoint(x: w, y: h * 0.9), control: CGPoint(x: w * 0.5, y: h * 0.84))
        hills.addLine(to: CGPoint(x: w, y: h))
        hills.closeSubpath()
        ctx.fill(hills, with: .color(ink))

        var temple = Path()
        // stepped plinth
        temple.addRect(CGRect(x: cx - u * 0.22, y: base - u * 0.03, width: u * 0.44, height: u * 0.03))
        temple.addRect(CGRect(x: cx - u * 0.18, y: base - u * 0.06, width: u * 0.36, height: u * 0.03))
        // hall
        temple.addRect(CGRect(x: cx - u * 0.14, y: base - u * 0.14, width: u * 0.28, height: u * 0.08))
        // tiered shikhara (curved spire)
        temple.move(to: CGPoint(x: cx - u * 0.1, y: base - u * 0.14))
        temple.addQuadCurve(to: CGPoint(x: cx, y: base - u * 0.4), control: CGPoint(x: cx - u * 0.1, y: base - u * 0.3))
        temple.addQuadCurve(to: CGPoint(x: cx + u * 0.1, y: base - u * 0.14), control: CGPoint(x: cx + u * 0.1, y: base - u * 0.3))
        temple.closeSubpath()
        // kalash + flag
        temple.addEllipse(in: CGRect(x: cx - u * 0.01, y: base - u * 0.43, width: u * 0.02, height: u * 0.03))
        temple.addRect(CGRect(x: cx - u * 0.002, y: base - u * 0.5, width: u * 0.004, height: u * 0.07))
        // side towers
        for s in [CGFloat(-1), CGFloat(1)] {
            let tx = cx + s * u * 0.2
            temple.move(to: CGPoint(x: tx - u * 0.04, y: base - u * 0.06))
            temple.addLine(to: CGPoint(x: tx, y: base - u * 0.2))
            temple.addLine(to: CGPoint(x: tx + u * 0.04, y: base - u * 0.06))
            temple.closeSubpath()
        }
        ctx.fill(temple, with: .color(ink))

        // Lit arches/windows + a row of tiny diyas.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 2))
            l.blendMode = .plusLighter
            for k in -2...2 {
                let wx = cx + CGFloat(k) * u * 0.05
                let f = 0.7 + 0.25 * sin(time * 5 + Double(k) * 1.7)
                l.fill(Path(roundedRect: CGRect(x: wx - u * 0.01, y: base - u * 0.12, width: u * 0.02, height: u * 0.04), cornerRadius: u * 0.01),
                       with: .color(Color(red: 1, green: 0.7, blue: 0.2).opacity(f)))
            }
            for k in 0..<18 {
                let dx = cx - u * 0.21 + CGFloat(k) * u * 0.0245
                let f = 0.6 + 0.4 * sin(time * 6 + Double(k) * 2.3)
                l.fill(Path(ellipseIn: CGRect(x: dx - 1.8, y: base - u * 0.012, width: 3.6, height: 3.6)),
                       with: .color(Color(red: 1, green: 0.75, blue: 0.25).opacity(f)))
            }
        }
    }
}

// MARK: - Effect 4: Sparklers & Anar

/// **Sparklers & Anar** — a courtyard at night with three anar flowerpot
/// fountains showering coloured sparks, a spinning ground chakra throwing
/// spiral trails, and a phuljhadi sparkler scribbling a figure-eight of light
/// in the air. Stateless: every spark is a closed-form function of `time`.
struct SparklersView: View {
    let time: Double

    /// Spark colours by life stage: white-hot, gold, orange, ember.
    private let stage: [Color] = [
        Color(red: 1.0, green: 0.97, blue: 0.80),
        Color(red: 1.0, green: 0.80, blue: 0.30),
        Color(red: 1.0, green: 0.50, blue: 0.10),
        Color(red: 0.85, green: 0.22, blue: 0.05),
    ]

    private struct Batch {
        var paths = [Path](repeating: Path(), count: 4)
        mutating func add(stage s: Int, from a: CGPoint, to b: CGPoint) {
            paths[s].move(to: a); paths[s].addLine(to: b)
        }
    }

    var body: some View {
        Canvas { ctx, size in draw(ctx: ctx, size: size) }
    }

    private func flush(_ batch: Batch, ctx: GraphicsContext, alpha: Double, width: CGFloat, colors: [Color]? = nil) {
        let cols = colors ?? stage
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            for (i, p) in batch.paths.enumerated() {
                let a = alpha * [1.0, 0.95, 0.8, 0.55][i]
                l.stroke(p, with: .color(cols[i].opacity(a)), style: StrokeStyle(lineWidth: width * [0.9, 1.0, 0.85, 0.7][i], lineCap: .round))
            }
        }
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }
        let unit = min(w, h)
        let ground = h * 0.88

        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.01, green: 0.01, blue: 0.05), Color(red: 0.10, green: 0.03, blue: 0.08)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        // Courtyard floor.
        ctx.fill(Path(CGRect(x: 0, y: ground, width: w, height: h - ground)), with: .color(Color(red: 0.05, green: 0.02, blue: 0.04)))

        // Anar fountains: three pots with different colour mixes and burn cycles.
        let pots: [(CGFloat, CGFloat, Double, [Color])] = [
            (0.2, 1.0, 0.0, stage),
            (0.46, 1.4, 2.1, [Color(red: 0.9, green: 1.0, blue: 0.9), Color(red: 0.4, green: 1.0, blue: 0.5), Color(red: 0.1, green: 0.75, blue: 0.4), Color(red: 0.05, green: 0.4, blue: 0.3)]),
            (0.64, 0.9, 4.3, [Color(red: 1.0, green: 0.92, blue: 0.97), Color(red: 1.0, green: 0.45, blue: 0.8), Color(red: 0.8, green: 0.2, blue: 0.75), Color(red: 0.45, green: 0.1, blue: 0.55)]),
        ]
        for (fx, scale, phase, cols) in pots {
            fountain(ctx: ctx, origin: CGPoint(x: w * fx, y: ground), scale: unit * 0.26 * scale, phase: phase, colors: cols, unit: unit)
        }
        chakra(ctx: ctx, center: CGPoint(x: w * 0.82, y: h * 0.7), radius: unit * 0.22, unit: unit)
        phuljhadi(ctx: ctx, anchor: CGPoint(x: w * 0.12, y: h * 0.45), unit: unit)
    }

    // MARK: Fountain

    private func fountain(ctx: GraphicsContext, origin o: CGPoint, scale s: CGFloat, phase: Double, colors: [Color], unit: CGFloat) {
        // Burn cycle: strong plume, brief sputter, repeat.
        let cyc = 9.0
        let cu = ((time + phase * 2).truncatingRemainder(dividingBy: cyc)) / cyc
        let burn = cu < 0.78 ? min(1, cu * 8) : max(0.12, 1 - (cu - 0.78) * 6)
        let sputter = cu >= 0.78 ? 0.5 + 0.5 * sin(time * 40) : 1.0

        // Pot.
        let pw = unit * 0.05
        var pot = Path()
        pot.move(to: CGPoint(x: o.x - pw * 0.8, y: o.y - pw * 1.5))
        pot.addLine(to: CGPoint(x: o.x + pw * 0.8, y: o.y - pw * 1.5))
        pot.addLine(to: CGPoint(x: o.x + pw * 1.1, y: o.y))
        pot.addLine(to: CGPoint(x: o.x - pw * 1.1, y: o.y))
        pot.closeSubpath()
        ctx.fill(pot, with: .linearGradient(Gradient(colors: [DiwaliPalette.clay, DiwaliPalette.clayDark]),
                                            startPoint: CGPoint(x: o.x, y: o.y - pw * 1.5), endPoint: o))
        var stripe = Path()
        stripe.move(to: CGPoint(x: o.x - pw * 0.95, y: o.y - pw * 0.75)); stripe.addLine(to: CGPoint(x: o.x + pw * 0.95, y: o.y - pw * 0.75))
        ctx.stroke(stripe, with: .color(DiwaliPalette.gold.opacity(0.7)), lineWidth: 1.5)
        let mouth = CGPoint(x: o.x, y: o.y - pw * 1.5)

        // Glow on the ground and above the mouth.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: s * 0.15))
            l.blendMode = .plusLighter
            let g = s * 0.9
            l.fill(Path(ellipseIn: CGRect(x: mouth.x - g, y: mouth.y - g * 0.8, width: g * 2, height: g * 1.6)),
                   with: .radialGradient(Gradient(colors: [colors[1].opacity(0.45 * burn), .clear]),
                                         center: mouth, startRadius: 0, endRadius: g))
        }

        var batch = Batch()
        let n = 420
        let life = 1.15
        for i in 0..<n {
            let h1 = Double(DiwaliPalette.hash01(i, 401)), h2 = Double(DiwaliPalette.hash01(i, 402)), h3 = Double(DiwaliPalette.hash01(i, 403))
            let u = DiwaliPalette.fract(time * (0.9 + 0.4 * h3) / life + h1)
            let tau = u * life
            let spread = 0.8 * (h2 - 0.5) * 2 * (0.35 + 0.65 * h3)               // radians off vertical
            let speed = Double(s) * (1.4 + 2.0 * h3) * burn
            let g = Double(s) * 2.4
            func pos(_ t: Double) -> CGPoint {
                CGPoint(x: mouth.x + CGFloat(sin(spread) * speed * t),
                        y: mouth.y - CGFloat(cos(spread) * speed * t - 0.5 * g * t * t))
            }
            let p1 = pos(tau), p0 = pos(max(0, tau - 0.075))
            let st = min(3, Int(u * 4))
            batch.add(stage: st, from: p0, to: p1)
        }
        flush(batch, ctx: ctx, alpha: burn * sputter, width: max(1.4, unit * 0.004), colors: colors)
    }

    // MARK: Chakra (ground spinner)

    private func chakra(ctx: GraphicsContext, center c: CGPoint, radius R: CGFloat, unit: CGFloat) {
        let omega = 7.0
        let jets = 6
        // Hot centre.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: R * 0.08))
            l.blendMode = .plusLighter
            let g = R * 0.5
            l.fill(Path(ellipseIn: CGRect(x: c.x - g, y: c.y - g, width: g * 2, height: g * 2)),
                   with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.5).opacity(0.7), .clear]),
                                         center: c, startRadius: 0, endRadius: g))
        }
        var batch = Batch()
        let per = 36
        let life = 0.9
        for j in 0..<jets {
            for i in 0..<per {
                let u = Double(i) / Double(per)
                let tau = u * life
                func pos(_ t: Double) -> CGPoint {
                    let te = time - t
                    let ang = omega * te + Double(j) * 2 * Double.pi / Double(jets)
                    let rad = Double(R) * (0.08 + 0.92 * pow(t / life, 0.9))
                    return CGPoint(x: c.x + CGFloat(cos(ang) * rad), y: c.y + CGFloat(sin(ang) * rad))
                }
                let st = min(3, Int(u * 4))
                batch.add(stage: st, from: pos(tau), to: pos(min(life, tau + 0.035)))
            }
        }
        flush(batch, ctx: ctx, alpha: 0.95, width: max(1.4, unit * 0.004))
    }

    // MARK: Phuljhadi sparkler writing in the air

    private func phuljhadi(ctx: GraphicsContext, anchor a: CGPoint, unit: CGFloat) {
        let ax = unit * 0.22, ay = unit * 0.18
        func tip(_ t: Double) -> CGPoint {
            CGPoint(x: a.x + CGFloat(sin(t * 0.9)) * ax + ax,
                    y: a.y + CGFloat(sin(t * 1.8)) * ay)
        }
        let tp = tip(time)

        // Glowing trail of recent positions.
        var trail = [Path](repeating: Path(), count: 3)
        let steps = 42
        var prev = tip(time)
        for k in 1...steps {
            let t = time - Double(k) * 0.022
            let pt = tip(t)
            let bucket = k < 10 ? 0 : (k < 24 ? 1 : 2)
            trail[bucket].move(to: prev); trail[bucket].addLine(to: pt)
            prev = pt
        }
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 2))
            l.blendMode = .plusLighter
            let widths: [CGFloat] = [3.2, 2.2, 1.2]
            let alphas = [0.9, 0.5, 0.2]
            for i in 0..<3 {
                l.stroke(trail[i], with: .color(stage[i + 1 > 3 ? 3 : i].opacity(alphas[i])), style: StrokeStyle(lineWidth: widths[i], lineCap: .round, lineJoin: .round))
            }
        }

        // Stick from lower-left to the burning tip.
        var stick = Path()
        stick.move(to: CGPoint(x: tp.x - unit * 0.07, y: tp.y + unit * 0.11))
        stick.addLine(to: tp)
        ctx.stroke(stick, with: .color(Color(red: 0.35, green: 0.3, blue: 0.3)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

        // Radial spark burst from the tip.
        var batch = Batch()
        for i in 0..<110 {
            let h1 = Double(DiwaliPalette.hash01(i, 421)), h2 = Double(DiwaliPalette.hash01(i, 422)), h3 = Double(DiwaliPalette.hash01(i, 423))
            let life = 0.5
            let u = DiwaliPalette.fract(time * (1.6 + h3) + h1)
            let tau = u * life
            let ang = h2 * 2 * Double.pi
            let speed = Double(unit) * (0.12 + 0.22 * h3)
            func pos(_ t: Double) -> CGPoint {
                CGPoint(x: tp.x + CGFloat(cos(ang) * speed * t),
                        y: tp.y + CGFloat(sin(ang) * speed * t + 0.5 * Double(unit) * 0.5 * t * t))
            }
            batch.add(stage: min(3, Int(u * 4)), from: pos(max(0, tau - 0.03)), to: pos(tau))
        }
        flush(batch, ctx: ctx, alpha: 1.0, width: max(1.1, unit * 0.003))

        ctx.drawLayer { l in
            l.addFilter(.blur(radius: unit * 0.008))
            l.blendMode = .plusLighter
            let g = unit * 0.05
            l.fill(Path(ellipseIn: CGRect(x: tp.x - g, y: tp.y - g, width: g * 2, height: g * 2)),
                   with: .radialGradient(Gradient(colors: [Color.white.opacity(0.95), Color(red: 1, green: 0.7, blue: 0.2).opacity(0.5), .clear]),
                                         center: tp, startRadius: 0, endRadius: g))
        }
    }
}
