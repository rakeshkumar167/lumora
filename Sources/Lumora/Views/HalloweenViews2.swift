import LumoraKit
import SwiftUI

// MARK: - Effect 3: Haunted House

/// **Haunted House** — a crooked mansion silhouetted on a hill under a harvest
/// moon: windows flicker and blink, a bare tree creaks in the wind, fog creeps
/// along the ground and lightning periodically flashes the whole sky.
/// Stateless: everything derives from `time`.
struct HauntedHouseView: View {
    let time: Double

    private let lightningPeriod = 11.0

    var body: some View {
        Canvas { ctx, size in draw(ctx: ctx, size: size) }
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }
        let unit = min(w, h)

        HalloweenPalette.drawSky(ctx: ctx, size: size, time: time, moonX: 0.78, moonY: 0.2, moonScale: 1.1)

        // Lightning: a bolt plus a brief sky flash, two quick strobes per period.
        let lt = time.truncatingRemainder(dividingBy: lightningPeriod)
        var flash = 0.0
        if lt < 0.5 {
            flash = max(0, 1 - lt / 0.5) * (0.6 + 0.4 * sin(lt * 50))
            drawBolt(ctx: ctx, size: size, strength: flash,
                     seed: Int(time / lightningPeriod))
        }

        // Rolling hill
        var hill = Path()
        hill.move(to: CGPoint(x: 0, y: h))
        hill.addLine(to: CGPoint(x: 0, y: h * 0.82))
        hill.addQuadCurve(to: CGPoint(x: w, y: h * 0.86), control: CGPoint(x: w * 0.5, y: h * 0.66))
        hill.addLine(to: CGPoint(x: w, y: h))
        hill.closeSubpath()
        let ink = Color(red: 0.012, green: 0.006, blue: 0.025)

        // House (drawn on the hill crest)
        let hx = w * 0.5, base = h * 0.76
        let u = unit
        var house = Path()
        // main block
        house.addRect(CGRect(x: hx - u * 0.2, y: base - u * 0.2, width: u * 0.4, height: u * 0.24))
        // main roof
        house.move(to: CGPoint(x: hx - u * 0.23, y: base - u * 0.2))
        house.addLine(to: CGPoint(x: hx - u * 0.02, y: base - u * 0.36))
        house.addLine(to: CGPoint(x: hx + u * 0.23, y: base - u * 0.2))
        house.closeSubpath()
        // tower
        house.addRect(CGRect(x: hx + u * 0.12, y: base - u * 0.42, width: u * 0.1, height: u * 0.26))
        house.move(to: CGPoint(x: hx + u * 0.105, y: base - u * 0.42))
        house.addLine(to: CGPoint(x: hx + u * 0.17, y: base - u * 0.56))
        house.addLine(to: CGPoint(x: hx + u * 0.235, y: base - u * 0.42))
        house.closeSubpath()
        // chimney
        house.addRect(CGRect(x: hx - u * 0.16, y: base - u * 0.34, width: u * 0.035, height: u * 0.1))
        // left wing
        house.addRect(CGRect(x: hx - u * 0.34, y: base - u * 0.12, width: u * 0.15, height: u * 0.16))
        house.move(to: CGPoint(x: hx - u * 0.36, y: base - u * 0.12))
        house.addLine(to: CGPoint(x: hx - u * 0.265, y: base - u * 0.22))
        house.addLine(to: CGPoint(x: hx - u * 0.17, y: base - u * 0.12))
        house.closeSubpath()
        ctx.fill(house, with: .color(ink))

        // Windows: flicker, and a couple blink out now and then.
        let windows: [CGRect] = [
            CGRect(x: hx - u * 0.15, y: base - u * 0.14, width: u * 0.045, height: u * 0.065),
            CGRect(x: hx - u * 0.06, y: base - u * 0.14, width: u * 0.045, height: u * 0.065),
            CGRect(x: hx + u * 0.04, y: base - u * 0.14, width: u * 0.045, height: u * 0.065),
            CGRect(x: hx + u * 0.145, y: base - u * 0.37, width: u * 0.04, height: u * 0.06),
            CGRect(x: hx - u * 0.285, y: base - u * 0.07, width: u * 0.04, height: u * 0.055),
            CGRect(x: hx - u * 0.04, y: base - u * 0.285, width: u * 0.04, height: u * 0.05),
        ]
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: u * 0.012))
            l.blendMode = .plusLighter
            for (i, r) in windows.enumerated() {
                let blink = HalloweenPalette.fract(time * 0.07 + Double(HalloweenPalette.hash01(i, 61)))
                let on = blink < 0.82 || flash > 0.2
                let f = 0.75 + 0.2 * sin(time * 7 + Double(i) * 2.1) + 0.05 * sin(time * 19 + Double(i))
                if on { l.fill(Path(r), with: .color(HalloweenPalette.moon.opacity(f))) }
            }
        }
        // Crisp pane cross-bars
        for r in windows {
            var bars = Path()
            bars.move(to: CGPoint(x: r.midX, y: r.minY)); bars.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            bars.move(to: CGPoint(x: r.minX, y: r.midY)); bars.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            ctx.stroke(bars, with: .color(ink.opacity(0.9)), lineWidth: max(1, u * 0.003))
        }

        ctx.fill(hill, with: .color(ink))

        // Bare tree on the left, branches swaying.
        drawTree(ctx: ctx, base: CGPoint(x: w * 0.16, y: h * 0.82), length: u * 0.2, angle: -.pi / 2, depth: 6, color: ink)

        // Bats leaving the tower.
        for i in 0..<5 {
            let t = HalloweenPalette.fract(time * 0.05 + Double(i) * 0.19)
            let x = hx + u * 0.17 + CGFloat(t) * w * 0.4 * (i % 2 == 0 ? 1 : -1.4)
            let y = base - u * 0.5 - CGFloat(t) * h * 0.2 + CGFloat(sin(time * 1.4 + Double(i))) * 10
            ctx.fill(HalloweenPalette.bat(at: CGPoint(x: x, y: y), span: u * (0.035 + 0.02 * CGFloat(i % 3)), flap: time * 10 + Double(i)),
                     with: .color(Color.black.opacity(0.9 * (1 - t))))
        }

        HalloweenPalette.drawFog(ctx: ctx, size: size, time: time, baseY: 0.82, bands: 4)

        // Full-sky lightning flash overlay.
        if flash > 0 {
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .color(Color(red: 0.8, green: 0.85, blue: 1.0).opacity(0.22 * flash)))
        }
    }

    private func drawBolt(ctx: GraphicsContext, size: CGSize, strength: Double, seed: Int) {
        let w = size.width, h = size.height
        var p = Path()
        var x = w * (0.1 + 0.35 * HalloweenPalette.hash01(seed, 71))
        var y: CGFloat = 0
        p.move(to: CGPoint(x: x, y: y))
        let steps = 9
        for k in 0..<steps {
            x += (HalloweenPalette.hash01(seed * 31 + k, 72) - 0.5) * w * 0.09
            y += h * 0.52 / CGFloat(steps)
            p.addLine(to: CGPoint(x: x, y: y))
        }
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 6))
            l.blendMode = .plusLighter
            l.stroke(p, with: .color(Color(red: 0.7, green: 0.8, blue: 1.0).opacity(strength)), lineWidth: 7)
        }
        ctx.stroke(p, with: .color(Color.white.opacity(strength)), lineWidth: 2)
    }

    private func drawTree(ctx: GraphicsContext, base: CGPoint, length: CGFloat, angle: Double, depth: Int, color: Color) {
        guard depth > 0 else { return }
        let sway = sin(time * 0.9 + Double(depth) * 0.7 + Double(base.x)) * 0.025 * Double(7 - depth)
        let a = angle + sway
        let end = CGPoint(x: base.x + CGFloat(cos(a)) * length, y: base.y + CGFloat(sin(a)) * length)
        var seg = Path()
        seg.move(to: base); seg.addLine(to: end)
        ctx.stroke(seg, with: .color(color), style: StrokeStyle(lineWidth: max(1, CGFloat(depth) * 1.8), lineCap: .round))
        drawTree(ctx: ctx, base: end, length: length * 0.74, angle: angle - 0.42, depth: depth - 1, color: color)
        drawTree(ctx: ctx, base: end, length: length * 0.72, angle: angle + 0.5, depth: depth - 1, color: color)
    }
}

// MARK: - Effect 4: Witch's Cauldron

/// **Witch's Cauldron** — a black iron pot over a crackling fire, its slime-green
/// brew glowing, bubbling and popping, with vapour curling up and sparks
/// drifting into the dark. Stateless.
struct WitchCauldronView: View {
    let time: Double

    var body: some View {
        Canvas { ctx, size in draw(ctx: ctx, size: size) }
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }
        let unit = min(w, h)
        let cx = w / 2
        let r = unit * 0.2
        let rimY = h * 0.6

        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [HalloweenPalette.night, HalloweenPalette.dusk]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

        // Green brew light spilling up into the scene.
        let pulse = 0.85 + 0.15 * sin(time * 1.6)
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 30))
            l.blendMode = .plusLighter
            let g = r * 3.5
            l.fill(Path(ellipseIn: CGRect(x: cx - g, y: rimY - g, width: g * 2, height: g * 2)),
                   with: .radialGradient(Gradient(colors: [HalloweenPalette.slime.opacity(0.35 * pulse), .clear]),
                                         center: CGPoint(x: cx, y: rimY), startRadius: 0, endRadius: g))
        }

        // Fire beneath: coal bed, logs and layered flame tongues (behind the pot).
        let fireY = rimY + r * 1.55
        drawFire(ctx: ctx, cx: cx, fireY: fireY, r: r, front: false)

        // Pot body, legs, rim and brew surface.
        let ink = Color(red: 0.03, green: 0.025, blue: 0.045)
        for dx in [CGFloat(-0.7), CGFloat(0), CGFloat(0.7)] {
            var leg = Path()
            leg.move(to: CGPoint(x: cx + dx * r - r * 0.1, y: rimY + r * 1.0))
            leg.addLine(to: CGPoint(x: cx + dx * r * 1.15, y: rimY + r * 1.5))
            leg.addLine(to: CGPoint(x: cx + dx * r * 1.15 + r * 0.14, y: rimY + r * 1.5))
            leg.addLine(to: CGPoint(x: cx + dx * r + r * 0.1, y: rimY + r * 1.0))
            leg.closeSubpath()
            ctx.fill(leg, with: .color(ink))
        }
        let body = CGRect(x: cx - r * 1.1, y: rimY - r * 0.4, width: r * 2.2, height: r * 1.7)
        ctx.fill(Path(ellipseIn: body),
                 with: .radialGradient(Gradient(colors: [Color(red: 0.12, green: 0.1, blue: 0.15), ink]),
                                       center: CGPoint(x: cx - r * 0.4, y: rimY + r * 0.1),
                                       startRadius: 0, endRadius: r * 1.6))
        // Brew glow reflecting on the underside of the lip.
        let rim = CGRect(x: cx - r * 0.98, y: rimY - r * 0.24, width: r * 1.96, height: r * 0.48)
        ctx.fill(Path(ellipseIn: rim), with: .linearGradient(
            Gradient(colors: [HalloweenPalette.slime.opacity(0.95 * pulse), Color(red: 0.12, green: 0.45, blue: 0.1)]),
            startPoint: CGPoint(x: rim.minX, y: rim.minY), endPoint: CGPoint(x: rim.maxX, y: rim.maxY)))
        ctx.stroke(Path(ellipseIn: rim), with: .color(ink), lineWidth: r * 0.09)

        // A few low tongues licking up the front of the pot.
        drawFire(ctx: ctx, cx: cx, fireY: rimY + r * 1.55, r: r, front: true)

        // Bubbles rising from the brew, growing, then popping.
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            for i in 0..<14 {
                let period = 2.2 + 1.8 * Double(HalloweenPalette.hash01(i, 81))
                let u = HalloweenPalette.fract(time / period + Double(HalloweenPalette.hash01(i, 82)))
                let bx = cx + (HalloweenPalette.hash01(i, 83) - 0.5) * r * 1.5
                let rise = r * (0.15 + 0.9 * HalloweenPalette.hash01(i, 84))
                let by = rimY - CGFloat(min(u / 0.85, 1)) * rise
                let br = r * (0.05 + 0.08 * HalloweenPalette.hash01(i, 85)) * CGFloat(0.4 + 0.6 * min(u / 0.85, 1))
                if u < 0.85 {
                    let b = Path(ellipseIn: CGRect(x: bx - br, y: by - br, width: br * 2, height: br * 2))
                    l.fill(b, with: .color(HalloweenPalette.slime.opacity(0.35)))
                    l.stroke(b, with: .color(Color.white.opacity(0.7)), lineWidth: 1.2)
                } else {
                    // Pop: expanding fading ring plus a few droplets.
                    let pu = (u - 0.85) / 0.15
                    let pr = br * (1 + 0.8 * CGFloat(pu))
                    l.stroke(Path(ellipseIn: CGRect(x: bx - pr, y: by - pr, width: pr * 2, height: pr * 2)),
                             with: .color(HalloweenPalette.slime.opacity(0.8 * (1 - pu))), lineWidth: 1.5)
                    for k in 0..<4 {
                        let a = Double(k) * 1.57 + Double(i)
                        let d = pr * (1.2 + 1.2 * CGFloat(pu))
                        l.fill(Path(ellipseIn: CGRect(x: bx + CGFloat(cos(a)) * d - 1.2, y: by - CGFloat(sin(a)) * d - 1.2, width: 2.4, height: 2.4)),
                               with: .color(HalloweenPalette.slime.opacity(0.7 * (1 - pu))))
                    }
                }
            }
        }

        // Vapour curling up from the brew.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 16))
            l.blendMode = .plusLighter
            for i in 0..<10 {
                let u = HalloweenPalette.fract(time * (0.07 + 0.05 * Double(HalloweenPalette.hash01(i, 91))) + Double(HalloweenPalette.hash01(i, 92)))
                let x = cx + (HalloweenPalette.hash01(i, 93) - 0.5) * r * 1.2 + CGFloat(sin(time * 0.9 + Double(i) * 1.3 + u * 6)) * r * 0.5 * CGFloat(u)
                let y = rimY - CGFloat(u) * h * 0.55
                let vr = r * (0.2 + 0.55 * CGFloat(u))
                l.fill(Path(ellipseIn: CGRect(x: x - vr, y: y - vr, width: vr * 2, height: vr * 2)),
                       with: .color(HalloweenPalette.slime.opacity(0.18 * sin(u * .pi))))
            }
        }

        // Sparks from the fire.
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            for i in 0..<24 {
                let u = HalloweenPalette.fract(time * (0.1 + 0.12 * Double(HalloweenPalette.hash01(i, 95))) + Double(HalloweenPalette.hash01(i, 96)))
                let x = cx + (HalloweenPalette.hash01(i, 97) - 0.5) * r * 3 + CGFloat(sin(time * 1.5 + Double(i))) * 10 * CGFloat(u)
                let y = rimY + r * 1.55 - CGFloat(u) * h * 0.5
                let s = (1.2 + 2 * HalloweenPalette.hash01(i, 98)) * unit / 500
                l.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                       with: .color(HalloweenPalette.glow.opacity(0.9 * (1 - u))))
            }
        }
    }
    // MARK: Fire

    /// Colour layers of one flame tongue, outermost first: (width scale,
    /// height scale, colour).
    private static let flameLayers: [(CGFloat, CGFloat, Color)] = [
        (1.00, 1.00, Color(red: 0.85, green: 0.12, blue: 0.02).opacity(0.85)),
        (0.78, 0.82, Color(red: 1.00, green: 0.38, blue: 0.04).opacity(0.9)),
        (0.54, 0.62, Color(red: 1.00, green: 0.68, blue: 0.12).opacity(0.95)),
        (0.30, 0.38, Color(red: 1.00, green: 0.94, blue: 0.62).opacity(1.0)),
    ]

    private func drawFire(ctx: GraphicsContext, cx: CGFloat, fireY: CGFloat, r: CGFloat, front: Bool) {
        let spread = r * 1.5
        let count = front ? 6 : 15
        // Heat bloom behind everything.
        if !front {
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: r * 0.6))
                l.blendMode = .plusLighter
                let g = r * 2.6
                l.fill(Path(ellipseIn: CGRect(x: cx - g, y: fireY - g * 0.9, width: g * 2, height: g * 1.3)),
                       with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.4, blue: 0.05).opacity(0.5), .clear]),
                                             center: CGPoint(x: cx, y: fireY - r * 0.3), startRadius: 0, endRadius: g))
            }
            // Coal bed with pulsing hot spots.
            let bed = CGRect(x: cx - r * 1.3, y: fireY - r * 0.12, width: r * 2.6, height: r * 0.4)
            ctx.fill(Path(ellipseIn: bed), with: .radialGradient(
                Gradient(colors: [Color(red: 1, green: 0.5, blue: 0.1), Color(red: 0.45, green: 0.07, blue: 0.02), Color(red: 0.12, green: 0.03, blue: 0.02)]),
                center: CGPoint(x: cx, y: bed.midY), startRadius: 0, endRadius: r * 1.4))
            ctx.drawLayer { l in
                l.blendMode = .plusLighter
                for k in 0..<18 {
                    let hx = cx + (HalloweenPalette.hash01(k, 111) - 0.5) * r * 2.3
                    let hy = bed.midY + (HalloweenPalette.hash01(k, 112) - 0.5) * r * 0.22
                    let glow = 0.5 + 0.5 * sin(time * (2 + 3 * Double(HalloweenPalette.hash01(k, 113))) + Double(k))
                    let hr = r * 0.045 * CGFloat(0.6 + glow)
                    l.fill(Path(ellipseIn: CGRect(x: hx - hr, y: hy - hr * 0.6, width: hr * 2, height: hr * 1.2)),
                           with: .color(Color(red: 1, green: 0.7, blue: 0.2).opacity(0.5 + 0.4 * glow)))
                }
            }
            // Logs with glowing cracks.
            for s in [CGFloat(-1), CGFloat(1)] {
                var log = Path()
                log.move(to: CGPoint(x: cx + s * r * 1.15, y: fireY + r * 0.2))
                log.addLine(to: CGPoint(x: cx - s * r * 0.9, y: fireY - r * 0.02))
                ctx.stroke(log, with: .color(Color(red: 0.13, green: 0.06, blue: 0.03)),
                           style: StrokeStyle(lineWidth: r * 0.24, lineCap: .round))
                ctx.drawLayer { l in
                    l.blendMode = .plusLighter
                    l.stroke(log, with: .color(Color(red: 1, green: 0.3, blue: 0.03).opacity(0.35 + 0.15 * sin(time * 4 + Double(s)))),
                             style: StrokeStyle(lineWidth: r * 0.05, lineCap: .round, dash: [r * 0.1, r * 0.16]))
                }
            }
        }

        // Flame tongues: each is a 4-colour stack drawn additively and softened.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: r * (front ? 0.03 : 0.045)))
            l.blendMode = .plusLighter
            for i in 0..<count {
                let f = Double(i) / Double(max(count - 1, 1))
                let x = cx + CGFloat(f * 2 - 1) * spread * (front ? 0.85 : 1.0)
                let centre = 1 - abs(CGFloat(f * 2 - 1))                  // taller in the middle
                let n = 0.65 + 0.35 * sin(time * 3.1 + Double(i) * 2.3) * sin(time * 1.7 + Double(i))
                let hBase = r * (front ? 0.95 : 1.25 + 0.9 * centre)
                let height = hBase * CGFloat(0.7 + 0.3 * n) * (0.85 + 0.3 * HalloweenPalette.hash01(i, front ? 121 : 122))
                let width = r * (front ? 0.34 : 0.5) * (0.8 + 0.4 * HalloweenPalette.hash01(i, 123))
                let base = CGPoint(x: x, y: fireY + (front ? r * 0.08 : 0))
                for (ws, hs, col) in Self.flameLayers {
                    var layer = l
                    layer.opacity = 1
                    // Fill the tongue with this layer's colour.
                    let steps = 14
                    var left: [CGPoint] = [], right: [CGPoint] = []
                    let phase = Double(i) * 1.9 + (front ? 40 : 0)
                    for k in 0...steps {
                        let s = Double(k) / Double(steps)
                        let amp = Double(width) * 0.75 * s * s
                        let off = CGFloat((0.6 * sin(time * 5.2 + phase + s * 4.0) + 0.4 * sin(time * 9.7 + phase * 1.7 + s * 8.0)) * amp)
                        let pinch = pow(1 - s, 1.25)
                        let bulge = min(1.0, 0.45 + s * 6.0)
                        let wob = 1 + 0.2 * sin(time * 7.3 + s * 5 + phase)
                        let hw = width * ws * 0.5 * CGFloat(pinch * bulge * wob)
                        let y = base.y - CGFloat(s) * height * hs
                        left.append(CGPoint(x: base.x + off - hw, y: y))
                        right.append(CGPoint(x: base.x + off + hw, y: y))
                    }
                    var p = Path()
                    p.move(to: left[0])
                    for pt in left.dropFirst() { p.addLine(to: pt) }
                    for pt in right.reversed() { p.addLine(to: pt) }
                    p.closeSubpath()
                    layer.fill(p, with: .color(col.opacity(front ? 0.7 : 0.9)))
                }
            }
        }

        // Detached flame licks and embers lifting off the fire.
        if !front {
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: r * 0.02))
                l.blendMode = .plusLighter
                for k in 0..<16 {
                    let u = HalloweenPalette.fract(time * (0.35 + 0.3 * Double(HalloweenPalette.hash01(k, 131))) + Double(HalloweenPalette.hash01(k, 132)))
                    let x = cx + (HalloweenPalette.hash01(k, 133) - 0.5) * r * 2.2 + CGFloat(sin(time * 2 + Double(k) * 1.7)) * r * 0.2 * CGFloat(u)
                    let y = fireY - r * 0.4 - CGFloat(u) * r * 2.2
                    let sz = r * 0.07 * CGFloat(1 - u * 0.8)
                    l.fill(Path(ellipseIn: CGRect(x: x - sz * 0.6, y: y - sz * 1.2, width: sz * 1.2, height: sz * 2.4)),
                           with: .color(Color(red: 1, green: 0.55 - 0.3 * u, blue: 0.1).opacity(0.85 * (1 - u))))
                }
            }
        }
    }
}
