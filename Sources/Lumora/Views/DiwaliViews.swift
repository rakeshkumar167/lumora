import LumoraKit
import SwiftUI

/// Fixed warm festival palette shared by the Diwali effects. None of the
/// effects expose color pickers (see `EffectKind.usesColor`).
enum DiwaliPalette {
    static let night = Color(red: 0.047, green: 0.012, blue: 0.027)     // #0C0307
    static let maroon = Color(red: 0.200, green: 0.027, blue: 0.063)    // #330710
    static let clay = Color(red: 0.690, green: 0.294, blue: 0.133)      // #B04B22
    static let clayDark = Color(red: 0.384, green: 0.133, blue: 0.067)  // #622211
    static let gold = Color(red: 1.0, green: 0.780, blue: 0.231)        // #FFC73B
    static let saffron = Color(red: 1.0, green: 0.557, blue: 0.082)     // #FF8E15
    static let flame = Color(red: 1.0, green: 0.357, blue: 0.067)       // #FF5B11
    static let magenta = Color(red: 0.882, green: 0.133, blue: 0.482)   // #E1227B
    static let teal = Color(red: 0.067, green: 0.675, blue: 0.690)      // #11ACB0
    static let violet = Color(red: 0.463, green: 0.173, blue: 0.710)    // #762CB5

    static func hash01(_ i: Int, _ salt: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return CGFloat(v - floor(v))
    }

    static func fract(_ x: Double) -> Double { x - floor(x) }
}

// MARK: - Effect 1: Diya Lamps

/// **Diya Lamps** — two rows of clay oil lamps along the bottom, each with a
/// flickering flame and soft additive glow, with golden bokeh and embers
/// drifting upward. Stateless: everything is derived from `time`.
struct DiyaLampsView: View {
    let time: Double

    var body: some View {
        Canvas { ctx, size in draw(ctx: ctx, size: size) }
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }

        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [DiwaliPalette.night, DiwaliPalette.maroon]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

        // Golden bokeh drifting slowly upward.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 14))
            l.blendMode = .plusLighter
            for i in 0..<22 {
                let r = (6 + 18 * DiwaliPalette.hash01(i, 1)) * min(w, h) / 400
                let x = DiwaliPalette.hash01(i, 2) * w + CGFloat(sin(time * 0.3 + Double(i))) * 12
                let u = DiwaliPalette.fract(time * (0.015 + 0.02 * Double(DiwaliPalette.hash01(i, 3))) + Double(DiwaliPalette.hash01(i, 4)))
                let y = h * (1.05 - 1.1 * CGFloat(u))
                let a = 0.22 * sin(u * .pi)
                l.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                       with: .color(DiwaliPalette.gold.opacity(a)))
            }
        }

        // Back row (smaller, higher), then front row.
        drawRow(ctx: ctx, size: size, count: 7, baseY: h * 0.80, scale: 0.75, salt: 10)
        drawRow(ctx: ctx, size: size, count: 5, baseY: h * 0.92, scale: 1.0, salt: 20)

        // Embers rising from the lamps.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 1.2))
            l.blendMode = .plusLighter
            for i in 0..<36 {
                let u = DiwaliPalette.fract(time * (0.08 + 0.1 * Double(DiwaliPalette.hash01(i, 5))) + Double(DiwaliPalette.hash01(i, 6)))
                let x0 = DiwaliPalette.hash01(i, 7) * w
                let x = x0 + CGFloat(sin(time * 1.1 + Double(i) * 2.3)) * 14 * CGFloat(u)
                let y = h * 0.88 - CGFloat(u) * h * 0.7
                let s = (1.2 + 2.2 * DiwaliPalette.hash01(i, 8)) * min(w, h) / 500
                l.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                       with: .color(DiwaliPalette.saffron.opacity(0.9 * (1 - u))))
            }
        }
    }

    private func drawRow(ctx: GraphicsContext, size: CGSize, count: Int, baseY: CGFloat, scale: CGFloat, salt: Int) {
        let w = size.width
        let r = min(w / CGFloat(count) * 0.32, size.height * 0.07) * scale
        for i in 0..<count {
            let cx = (CGFloat(i) + 0.5) / CGFloat(count) * w
            drawDiya(ctx: ctx, center: CGPoint(x: cx, y: baseY), r: r, index: i + salt)
        }
    }

    private func drawDiya(ctx: GraphicsContext, center c: CGPoint, r: CGFloat, index: Int) {
        let phase = Double(DiwaliPalette.hash01(index, 9)) * 6.28
        let flicker = 0.82 + 0.12 * sin(time * 9 + phase) + 0.06 * sin(time * 17.3 + phase * 2)
        let sway = CGFloat(sin(time * 2.6 + phase)) * r * 0.12

        // Glow behind the flame.
        let glowR = r * 3.6
        let flameBase = CGPoint(x: c.x, y: c.y - r * 0.05)
        let glowC = CGPoint(x: c.x, y: c.y - r * 0.7)
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: r * 0.8))
            l.blendMode = .plusLighter
            l.fill(Path(ellipseIn: CGRect(x: glowC.x - glowR, y: glowC.y - glowR, width: glowR * 2, height: glowR * 2)),
                   with: .radialGradient(Gradient(colors: [DiwaliPalette.saffron.opacity(0.5 * flicker), .clear]),
                                         center: glowC, startRadius: 0, endRadius: glowR))
        }

        // Clay bowl: half-moon with a pinched spout on the right.
        var bowl = Path()
        bowl.move(to: CGPoint(x: c.x - r, y: c.y))
        bowl.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x, y: c.y + r * 1.15))
        bowl.addQuadCurve(to: CGPoint(x: c.x + r * 1.35, y: c.y - r * 0.18), control: CGPoint(x: c.x + r * 1.2, y: c.y - r * 0.02))
        bowl.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x, y: c.y - r * 0.28))
        ctx.fill(bowl, with: .linearGradient(Gradient(colors: [DiwaliPalette.clay, DiwaliPalette.clayDark]),
                                             startPoint: CGPoint(x: c.x, y: c.y - r * 0.3),
                                             endPoint: CGPoint(x: c.x, y: c.y + r * 1.1)))
        // Gold trim along the rim and a lit oil surface.
        let rim = CGRect(x: c.x - r, y: c.y - r * 0.2, width: r * 2, height: r * 0.4)
        ctx.fill(Path(ellipseIn: rim), with: .color(DiwaliPalette.saffron.opacity(0.55 * flicker)))
        ctx.stroke(Path(ellipseIn: rim), with: .color(DiwaliPalette.gold.opacity(0.8)), lineWidth: max(1, r * 0.06))

        // Flame: a teardrop with a bright inner core.
        let fh = r * 1.5 * flicker
        let fw = r * 0.42
        let tip = CGPoint(x: flameBase.x + sway, y: flameBase.y - fh)
        var flame = Path()
        flame.move(to: flameBase)
        flame.addQuadCurve(to: tip, control: CGPoint(x: flameBase.x - fw * 1.5 + sway * 0.4, y: flameBase.y - fh * 0.45))
        flame.addQuadCurve(to: flameBase, control: CGPoint(x: flameBase.x + fw * 1.5 + sway * 0.4, y: flameBase.y - fh * 0.45))
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            l.fill(flame, with: .linearGradient(Gradient(colors: [DiwaliPalette.gold, DiwaliPalette.flame.opacity(0.9)]),
                                                startPoint: flameBase, endPoint: tip))
            var core = Path()
            let coreTip = CGPoint(x: flameBase.x + sway * 0.6, y: flameBase.y - fh * 0.6)
            core.move(to: flameBase)
            core.addQuadCurve(to: coreTip, control: CGPoint(x: flameBase.x - fw * 0.7, y: flameBase.y - fh * 0.25))
            core.addQuadCurve(to: flameBase, control: CGPoint(x: flameBase.x + fw * 0.7, y: flameBase.y - fh * 0.25))
            l.fill(core, with: .color(Color.white.opacity(0.85)))
        }
    }
}

// MARK: - Effect 2: Rangoli Bloom

/// **Rangoli Bloom** — a grand festival floor-pattern. Concentric rings of
/// lotus petals, peacock feathers, stars, diamonds, scallops and kolam weaves
/// bloom outward from a glowing centre over sand-textured ground, then a ring
/// of diyas lights up around the edge while powder glitters and marigold petals
/// drift down. Pattern, palette, ring count, symmetry, speed and extras come
/// from `RangoliConfig`. Stateless: the build cycle is a function of `time`.
struct RangoliBloomView: View {
    let time: Double
    var config: RangoliConfig = RangoliConfig()

    private let period = 22.0

    // MARK: Palettes

    private struct Palette {
        var colors: [Color]
        var bg: [Color]
    }

    private func palette() -> Palette {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        switch config.palette {
        case .marigold:
            return Palette(colors: [DiwaliPalette.magenta, DiwaliPalette.saffron, DiwaliPalette.teal, DiwaliPalette.violet, DiwaliPalette.gold],
                           bg: [DiwaliPalette.maroon, DiwaliPalette.night])
        case .jewel:
            return Palette(colors: [c(0.82, 0.07, 0.22), c(0.10, 0.28, 0.85), c(0.05, 0.68, 0.38), c(0.56, 0.22, 0.82), c(0.98, 0.78, 0.25)],
                           bg: [c(0.06, 0.03, 0.14), c(0.015, 0.01, 0.04)])
        case .pastel:
            return Palette(colors: [c(1.0, 0.62, 0.76), c(0.62, 0.95, 0.82), c(0.78, 0.68, 1.0), c(1.0, 0.80, 0.62), c(1.0, 0.96, 0.80)],
                           bg: [c(0.20, 0.10, 0.22), c(0.07, 0.04, 0.10)])
        case .sunset:
            return Palette(colors: [c(0.86, 0.10, 0.20), c(1.0, 0.45, 0.05), c(1.0, 0.76, 0.18), c(0.95, 0.35, 0.50), c(0.40, 0.12, 0.55)],
                           bg: [c(0.24, 0.05, 0.05), c(0.06, 0.01, 0.03)])
        case .neon:
            return Palette(colors: [c(1.0, 0.1, 0.6), c(0.1, 0.9, 1.0), c(0.55, 1.0, 0.2), c(0.6, 0.3, 1.0), c(1.0, 0.95, 0.25)],
                           bg: [c(0.04, 0.02, 0.12), c(0.0, 0.0, 0.03)])
        }
    }

    // MARK: Motifs

    private enum Motif { case pointed, lotus, feather, dots, beads, scallop, star, diamond, weave, rays, paisley, chakra, bud, swirl, triangles

        var thin: Bool {
            switch self {
            case .dots, .beads, .scallop, .weave, .rays: return true
            default: return false
            }
        }
    }

    private var motifPlan: [Motif] {
        switch config.style {
        case .grand:   return [.lotus, .dots, .paisley, .scallop, .feather, .chakra, .star, .bud, .diamond, .beads, .lotus, .feather]
        case .lotus:   return [.lotus, .dots, .pointed, .scallop, .lotus, .beads]
        case .peacock: return [.feather, .dots, .scallop, .feather, .weave, .beads]
        case .star:    return [.star, .diamond, .rays, .star, .dots, .diamond]
        case .kolam:   return [.weave, .beads, .weave, .scallop, .weave, .dots]
        case .paisley: return [.paisley, .dots, .bud, .scallop, .paisley, .beads, .lotus, .weave]
        case .chakra:  return [.chakra, .rays, .bud, .diamond, .chakra, .dots, .star, .beads]
        case .spiral:  return [.swirl, .dots, .swirl, .beads, .pointed, .swirl, .scallop, .weave]
        case .yantra:  return [.triangles, .lotus, .beads, .triangles, .diamond, .dots, .triangles, .scallop]
        }
    }

    private var centreMotif: (Motif, Int) {
        switch config.style {
        case .paisley: return (.bud, 6)
        case .chakra:  return (.chakra, 8)
        case .spiral:  return (.swirl, 6)
        case .yantra:  return (.triangles, 6)
        default:       return (.lotus, 8)
        }
    }

    private struct RingPaths {
        var a = Path(), b = Path(), gold = Path(), dark = Path()
        var line = Path(), strokeA = Path(), strokeB = Path()
    }

    private struct RingSpec {
        var motif: Motif
        var r0: CGFloat
        var r1: CGFloat
        var count: Int
        var ca: Color
        var cb: Color
        var fixedGold: Bool
    }

    var body: some View {
        Canvas { ctx, size in draw(ctx: ctx, size: size) }
    }

    // MARK: Draw

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }
        let pal = palette()
        let t = time * config.speed
        let center = CGPoint(x: w / 2, y: h / 2)
        let R = min(w, h) * 0.40

        // Ground: warm radial wash with sand grain and a chalk outline.
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(colors: pal.bg), center: center, startRadius: 0, endRadius: max(w, h) * 0.7))
        for i in 0..<320 {
            let a = Double(DiwaliPalette.hash01(i, 201)) * 6.2832
            let d = sqrt(Double(DiwaliPalette.hash01(i, 202))) * Double(max(w, h)) * 0.62
            let gx = center.x + CGFloat(cos(a) * d), gy = center.y + CGFloat(sin(a) * d)
            ctx.fill(Path(CGRect(x: gx, y: gy, width: 1.4, height: 1.4)),
                     with: .color(Color.white.opacity(0.03 + 0.07 * Double(DiwaliPalette.hash01(i, 203)))))
        }

        // Build cycle
        let u = config.buildCycle ? (t.truncatingRemainder(dividingBy: period)) / period : 0.5
        let build = config.buildCycle ? min(u / 0.58, 1.0) : 1.0
        let fade = (config.buildCycle && u > 0.92) ? max(0, 1 - (u - 0.92) / 0.08) : 1.0
        guard fade > 0.001 else { return }
        let breathe = 1 + 0.012 * sin(t * 1.1)
        let Rb = R * CGFloat(breathe)

        let motion = config.motion
        let cycle = config.buildCycle ? Int(floor(t / period)) : 0
        let specs = ringSpecs(pal: pal, shift: cycle)
        let slots = specs.count + 1                    // + centrepiece, revealed first
        func reveal(_ slot: Int) -> CGFloat {
            let raw = min(max(build * Double(slots) - Double(slot), 0), 1)
            return CGFloat(raw * raw * (3 - 2 * raw))
        }

        // Pre-build ring paths once per frame.
        var rings: [(RingPaths, RingSpec, CGFloat)] = []
        let cen = RingSpec(motif: centreMotif.0, r0: 0.012, r1: 0.1, count: centreMotif.1, ca: pal.colors[4 % pal.colors.count], cb: pal.colors[0], fixedGold: false)
        let centerReveal = reveal(0)
        rings.append((buildRing(cen, center: center, R: Rb, rot: t * 0.05, reveal: centerReveal, detail: true), cen, centerReveal))
        for (k, sp) in specs.enumerated() {
            let rv = reveal(k + 1)
            if rv < 0.001 { continue }
            let dir: Double = (k % 2 == 0) ? 1 : -1
            let spin = config.style == .spiral ? 2.4 : 1.0
            let rot = t * (0.035 + 0.004 * Double(k)) * dir * spin + Double(k) * 0.23 + Double(1 - rv) * dir * 1.3
            // Living motion: petals open/close and rings ripple in a wave travelling outward.
            let unfurl = CGFloat(1 + motion * 0.16 * sin(t * 1.6 - Double(k) * 0.7))
            let ripple = CGFloat(1 + motion * 0.012 * sin(t * 1.3 - Double(k) * 0.5))
            rings.append((buildRing(sp, center: center, R: Rb * ripple, rot: rot, reveal: rv, detail: true, widthScale: unfurl), sp, rv))
        }

        // Soft glow pass first (fills only), then the crisp pass.
        if config.glow > 0.01 {
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: Rb * 0.045))
                l.blendMode = .plusLighter
                let g = config.glow * fade
                for (rp, sp, rv) in rings {
                    let al = Double(rv) * g * 0.6
                    l.fill(rp.a, with: .color(sp.ca.opacity(al)))
                    l.fill(rp.b, with: .color(sp.cb.opacity(al)))
                    l.fill(rp.gold, with: .color(DiwaliPalette.gold.opacity(al)))
                }
            }
        }
        for (rp, sp, rv) in rings {
            let al = Double(rv) * fade
            ctx.fill(rp.a, with: .color(sp.ca.opacity(0.88 * al)))
            ctx.fill(rp.b, with: .color(sp.cb.opacity(0.92 * al)))
            ctx.fill(rp.gold, with: .color(DiwaliPalette.gold.opacity(al)))
            ctx.fill(rp.dark, with: .color(Color.black.opacity(0.7 * al)))
            ctx.stroke(rp.strokeA, with: .color(sp.ca.opacity(al)), style: StrokeStyle(lineWidth: max(1.6, Rb * 0.008), lineCap: .round))
            ctx.stroke(rp.strokeB, with: .color(sp.cb.opacity(al)), style: StrokeStyle(lineWidth: max(1.6, Rb * 0.008), lineCap: .round))
            ctx.stroke(rp.line, with: .color(DiwaliPalette.gold.opacity(0.85 * al)), lineWidth: max(0.8, Rb * 0.0035))
        }

        // Shimmer: a bright wave of light rolling outward through the rings.
        if motion > 0.01 {
            ctx.drawLayer { l in
                l.blendMode = .plusLighter
                for (idx, (rp, _, rv)) in rings.enumerated() {
                    let pulse = pow(max(0, sin(t * 1.1 - Double(idx) * 0.55)), 6) * motion * Double(rv) * fade
                    if pulse < 0.02 { continue }
                    l.fill(rp.a, with: .color(Color.white.opacity(0.3 * pulse)))
                    l.fill(rp.b, with: .color(Color.white.opacity(0.22 * pulse)))
                    l.stroke(rp.line, with: .color(DiwaliPalette.gold.opacity(0.8 * pulse)), lineWidth: max(1.2, Rb * 0.007))
                }
            }
        }

        if config.cornerRosettes {
            drawRosettes(ctx: ctx, size: size, R: Rb, pal: pal, build: build, fade: fade, t: t, shift: cycle)
        }

        // Pulsing sun at the very centre.
        let cp = 0.8 + 0.2 * sin(t * 2.2)
        let cr = Rb * 0.03 * CGFloat(cp) * centerReveal
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: Rb * 0.02))
            l.blendMode = .plusLighter
            l.fill(Path(ellipseIn: CGRect(x: center.x - cr * 2.2, y: center.y - cr * 2.2, width: cr * 4.4, height: cr * 4.4)),
                   with: .color(DiwaliPalette.gold.opacity(0.7 * fade)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - cr, y: center.y - cr, width: cr * 2, height: cr * 2)),
                 with: .color(Color.white.opacity(0.95 * fade)))

        // Diya ring around the outside, lighting clockwise after the pattern forms.
        if config.diyaRing {
            let m = max(12, config.symmetry * 2)
            let lightBuild = config.buildCycle ? min(max((build - 0.8) / 0.2, 0), 1.0) * Double(m) : Double(m)
            for j in 0..<m {
                let lit = min(max(lightBuild - Double(j), 0), 1)
                let a = Double(j) / Double(m) * 6.2832 - 1.5708
                let pos = CGPoint(x: center.x + CGFloat(cos(a)) * Rb * 1.16, y: center.y + CGFloat(sin(a)) * Rb * 1.16)
                miniDiya(ctx: ctx, at: pos, r: Rb * 0.034, angle: a, lit: lit * fade, phase: Double(j))
            }
        }

        // Powder glitter.
        if config.sparkle {
            drawGlitter(ctx: ctx, center: center, Rb: Rb, build: build, fade: fade, t: t)
        }

        // Marigold petals drifting down over everything.
        if config.fallingPetals {
            let unit = min(w, h)
            for i in 0..<28 {
                let sp = 0.03 + 0.04 * Double(DiwaliPalette.hash01(i, 221))
                let v = DiwaliPalette.fract(time * sp + Double(DiwaliPalette.hash01(i, 222)))
                let x = DiwaliPalette.hash01(i, 223) * w + CGFloat(sin(time * 0.7 + Double(i) * 1.9)) * unit * 0.05
                let y = -unit * 0.04 + CGFloat(v) * (h + unit * 0.08)
                let sz = unit * (0.011 + 0.014 * DiwaliPalette.hash01(i, 224))
                let rotA = time * (0.8 + Double(DiwaliPalette.hash01(i, 225))) + Double(i)
                let flip = CGFloat(0.35 + 0.65 * abs(cos(time * 0.9 + Double(i))))
                let xf = CGAffineTransform(translationX: x, y: y).rotated(by: rotA).scaledBy(x: 1, y: flip)
                let petal = Path(ellipseIn: CGRect(x: -sz, y: -sz * 0.5, width: sz * 2, height: sz)).applying(xf)
                let col = [DiwaliPalette.saffron, DiwaliPalette.gold, DiwaliPalette.flame][i % 3]
                ctx.fill(petal, with: .color(col.opacity(0.85 * fade)))
                ctx.fill(Path(ellipseIn: CGRect(x: -sz * 0.6, y: -sz * 0.22, width: sz * 1.2, height: sz * 0.44)).applying(xf),
                         with: .color(Color.white.opacity(0.22 * fade)))
            }
        }
    }

    // MARK: Glitter

    private func drawGlitter(ctx: GraphicsContext, center: CGPoint, Rb: CGFloat, build: Double, fade: Double, t: Double) {
        let extent: CGFloat = Rb * CGFloat(0.15 + 0.9 * build)
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            for i in 0..<110 {
                let h1: Double = Double(DiwaliPalette.hash01(i, 211))
                let h2: Double = Double(DiwaliPalette.hash01(i, 212))
                let h3: Double = Double(DiwaliPalette.hash01(i, 213))
                let h4: Double = Double(DiwaliPalette.hash01(i, 214))
                let h5: Double = Double(DiwaliPalette.hash01(i, 215))
                let rad: CGFloat = CGFloat(h1.squareRoot()) * extent
                let ang: Double = h2 * 6.2832 + t * 0.03
                let speed: Double = 1.2 + 3 * h3
                let wave: Double = sin(t * speed + h4 * 6.28)
                let tw: Double = pow(max(0, wave), 8)
                if tw < 0.05 { continue }
                let sx: CGFloat = center.x + CGFloat(cos(ang)) * rad
                let sy: CGFloat = center.y + CGFloat(sin(ang)) * rad
                let sz: CGFloat = Rb * 0.02 * CGFloat(0.5 + h5) * CGFloat(tw)
                var star = Path()
                star.move(to: CGPoint(x: sx - sz, y: sy)); star.addLine(to: CGPoint(x: sx + sz, y: sy))
                star.move(to: CGPoint(x: sx, y: sy - sz)); star.addLine(to: CGPoint(x: sx, y: sy + sz))
                l.stroke(star, with: .color(Color.white.opacity(0.9 * tw * fade)), lineWidth: 1.2)
                let dot = CGRect(x: sx - sz * 0.35, y: sy - sz * 0.35, width: sz * 0.7, height: sz * 0.7)
                l.fill(Path(ellipseIn: dot), with: .color(DiwaliPalette.gold.opacity(tw * fade)))
            }
        }
    }

    // MARK: Corner rosettes

    /// Small counter-rotating mandalas tucked into the surface corners, sized
    /// to stay clear of the main pattern and its diya ring. They bloom late in
    /// the build so the eye follows centre → edge → corners.
    private func drawRosettes(ctx: GraphicsContext, size: CGSize, R: CGFloat, pal: Palette, build: Double, fade: Double, t: Double, shift: Int) {
        let w = size.width, h = size.height
        let diag = hypot(w / 2, h / 2)
        let rr = min(min(w, h) * 0.16, (diag - R * 1.24) / 2.6)
        guard rr > min(w, h) * 0.045 else { return }
        let rv = CGFloat(min(max((build - 0.55) / 0.35, 0), 1))
        guard rv > 0.001 else { return }
        let cols = pal.colors
        let specs = [
            RingSpec(motif: .lotus, r0: 0.06, r1: 0.42, count: 8, ca: cols[(1 + shift) % cols.count], cb: cols[(3 + shift) % cols.count], fixedGold: false),
            RingSpec(motif: .dots, r0: 0.44, r1: 0.56, count: 16, ca: cols[(2 + shift) % cols.count], cb: DiwaliPalette.gold, fixedGold: false),
            RingSpec(motif: .pointed, r0: 0.58, r1: 0.92, count: 12, ca: cols[(shift) % cols.count], cb: DiwaliPalette.gold, fixedGold: false),
            RingSpec(motif: .beads, r0: 0.93, r1: 1.02, count: 24, ca: DiwaliPalette.gold, cb: cols[(4 + shift) % cols.count], fixedGold: true),
        ]
        let inset = rr * 1.1
        let corners = [CGPoint(x: inset, y: inset), CGPoint(x: w - inset, y: inset),
                       CGPoint(x: w - inset, y: h - inset), CGPoint(x: inset, y: h - inset)]
        for (ci, cc) in corners.enumerated() {
            let dir: Double = ci % 2 == 0 ? 1 : -1
            let pulse = CGFloat(1 + config.motion * 0.04 * sin(t * 1.4 + Double(ci) * 1.57))
            let paths = specs.enumerated().map { (k, sp) in
                buildRing(sp, center: cc, R: rr * rv * pulse, rot: t * 0.12 * dir * (k % 2 == 0 ? 1 : -1.3), reveal: rv, detail: true,
                          widthScale: CGFloat(1 + config.motion * 0.15 * sin(t * 1.8 - Double(k) * 0.8 + Double(ci))))
            }
            let al = Double(rv) * fade
            if config.glow > 0.01 {
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: rr * 0.08))
                    l.blendMode = .plusLighter
                    for (rp, sp) in zip(paths, specs) {
                        l.fill(rp.a, with: .color(sp.ca.opacity(0.5 * al * config.glow)))
                        l.fill(rp.b, with: .color(sp.cb.opacity(0.5 * al * config.glow)))
                    }
                }
            }
            for (rp, sp) in zip(paths, specs) {
                ctx.fill(rp.a, with: .color(sp.ca.opacity(0.88 * al)))
                ctx.fill(rp.b, with: .color(sp.cb.opacity(0.92 * al)))
                ctx.fill(rp.gold, with: .color(DiwaliPalette.gold.opacity(al)))
                ctx.stroke(rp.line, with: .color(DiwaliPalette.gold.opacity(0.85 * al)), lineWidth: max(0.7, rr * 0.012))
            }
            let dr = rr * 0.07 * rv
            ctx.fill(Path(ellipseIn: CGRect(x: cc.x - dr, y: cc.y - dr, width: dr * 2, height: dr * 2)), with: .color(Color.white.opacity(0.9 * al)))
        }
    }

    // MARK: Ring layout

    /// Concentric ring specs from the config: motif sequence, band widths
    /// (thin motifs get thinner bands), symmetry growth and palette colours,
    /// followed by the fixed gold border rings.
    private func ringSpecs(pal: Palette, shift: Int = 0) -> [RingSpec] {
        let n = config.rings
        let plan = motifPlan
        let motifs = (0..<n).map { plan[$0 % plan.count] }
        let weights = motifs.map { $0.thin ? 0.55 : 1.0 }
        let total = weights.reduce(0, +)
        let inner: CGFloat = 0.11, outer: CGFloat = 0.86
        var r = inner
        var out: [RingSpec] = []
        let base = config.symmetry
        for (k, m) in motifs.enumerated() {
            let band = (outer - inner) * CGFloat(weights[k] / total)
            let growth = base + (base * k * 2) / max(n, 1)
            let count = min(64, max(6, (growth / 2) * 2))
            let cols = pal.colors
            out.append(RingSpec(motif: m, r0: r, r1: r + band, count: count,
                                ca: cols[(k + shift) % cols.count], cb: cols[(k + shift + 2) % cols.count], fixedGold: false))
            r += band
        }
        let gold = DiwaliPalette.gold
        let outerCount = min(64, max(base * 2, 24))
        out.append(RingSpec(motif: .scallop, r0: 0.875, r1: 0.965, count: outerCount, ca: pal.colors[0], cb: gold, fixedGold: true))
        out.append(RingSpec(motif: .beads, r0: 0.97, r1: 1.04, count: outerCount * 2, ca: gold, cb: pal.colors[1 % pal.colors.count], fixedGold: true))
        return out
    }

    // MARK: Ring geometry

    private func polar(_ c: CGPoint, _ ang: Double, _ rad: CGFloat) -> CGPoint {
        CGPoint(x: c.x + CGFloat(cos(ang)) * rad, y: c.y + CGFloat(sin(ang)) * rad)
    }

    private func offset(_ c: CGPoint, _ ang: Double, _ rad: CGFloat, _ side: CGFloat) -> CGPoint {
        CGPoint(x: c.x + CGFloat(cos(ang)) * rad - CGFloat(sin(ang)) * side,
                y: c.y + CGFloat(sin(ang)) * rad + CGFloat(cos(ang)) * side)
    }

    private func buildRing(_ sp: RingSpec, center c: CGPoint, R: CGFloat, rot: Double, reveal: CGFloat, detail: Bool, widthScale: CGFloat = 1) -> RingPaths {
        var rp = RingPaths()
        let r0 = sp.r0 * R
        let fullL = (sp.r1 - sp.r0) * R
        let L = max(0.5, fullL * reveal)
        let r1 = r0 + L
        let rm = (r0 + r1) / 2
        let count = sp.count
        let step = 2 * Double.pi / Double(count)
        let hw = max(1, min(L * 0.42, rm * CGFloat(step) * 0.5)) * widthScale

        switch sp.motif {
        case .pointed:
            for j in 0..<count {
                let a = rot + Double(j) * step
                var p = Path()
                p.move(to: polar(c, a, r0))
                p.addQuadCurve(to: polar(c, a, r1), control: offset(c, a, rm, hw * 2))
                p.addQuadCurve(to: polar(c, a, r0), control: offset(c, a, rm, -hw * 2))
                rp.a.addPath(p); rp.line.addPath(p)
            }
        case .lotus:
            for j in 0..<count {
                let a = rot + Double(j) * step
                func petal(_ s0: CGFloat, _ s1: CGFloat, _ wk: CGFloat) -> Path {
                    let q0 = r0 + L * s0, q1 = r0 + L * s1, ql = q1 - q0
                    var p = Path()
                    p.move(to: polar(c, a, q0))
                    p.addCurve(to: polar(c, a, q1), control1: offset(c, a, q0 + ql * 0.3, hw * 2.3 * wk), control2: offset(c, a, q0 + ql * 0.9, hw * 1.1 * wk))
                    p.addCurve(to: polar(c, a, q0), control1: offset(c, a, q0 + ql * 0.9, -hw * 1.1 * wk), control2: offset(c, a, q0 + ql * 0.3, -hw * 2.3 * wk))
                    return p
                }
                let outerP = petal(0, 1, 1)
                rp.a.addPath(outerP); rp.line.addPath(outerP)
                let inner = petal(0.1, 0.72, 0.55)
                rp.b.addPath(inner)
                rp.line.move(to: polar(c, a, r0 + L * 0.12)); rp.line.addLine(to: polar(c, a, r0 + L * 0.62))
            }
        case .feather:
            for j in 0..<count {
                let a = rot + Double(j) * step
                var body = Path()
                body.move(to: polar(c, a, r0))
                body.addCurve(to: polar(c, a, r1), control1: offset(c, a, r0 + L * 0.35, hw * 1.3), control2: offset(c, a, r0 + L * 1.0, hw * 1.7))
                body.addCurve(to: polar(c, a, r0), control1: offset(c, a, r0 + L * 1.0, -hw * 1.7), control2: offset(c, a, r0 + L * 0.35, -hw * 1.3))
                rp.a.addPath(body); rp.line.addPath(body)
                // The eye.
                let ec = polar(c, a, r0 + L * 0.7)
                let xf = CGAffineTransform(translationX: ec.x, y: ec.y).rotated(by: a)
                func eye(_ k: CGFloat) -> Path {
                    Path(ellipseIn: CGRect(x: -L * 0.21 * k, y: -hw * 0.66 * k, width: L * 0.42 * k, height: hw * 1.32 * k)).applying(xf)
                }
                rp.b.addPath(eye(1)); rp.gold.addPath(eye(0.62)); rp.dark.addPath(eye(0.3))
                // Stem and barbs.
                rp.line.move(to: polar(c, a, r0)); rp.line.addLine(to: polar(c, a, r0 + L * 0.5))
                for bi in 1...2 {
                    let sr = r0 + L * (0.12 + 0.14 * CGFloat(bi))
                    rp.line.move(to: polar(c, a, sr)); rp.line.addLine(to: offset(c, a, sr + L * 0.14, hw * 0.65))
                    rp.line.move(to: polar(c, a, sr)); rp.line.addLine(to: offset(c, a, sr + L * 0.14, -hw * 0.65))
                }
            }
        case .dots:
            let dr = max(1.2, min(L * 0.38, rm * CGFloat(step) * 0.3))
            for j in 0..<count {
                let pc = polar(c, rot + Double(j) * step, rm)
                rp.a.addEllipse(in: CGRect(x: pc.x - dr, y: pc.y - dr, width: dr * 2, height: dr * 2))
                rp.gold.addEllipse(in: CGRect(x: pc.x - dr * 0.4, y: pc.y - dr * 0.4, width: dr * 0.8, height: dr * 0.8))
            }
        case .beads:
            let dr = max(1.1, min(L * 0.26, rm * CGFloat(step) * 0.28))
            for j in 0..<count {
                let pc = polar(c, rot + Double(j) * step, j % 2 == 0 ? r0 + L * 0.32 : r0 + L * 0.68)
                (j % 2 == 0 ? { rp.a.addEllipse(in: $0) } : { rp.b.addEllipse(in: $0) })(CGRect(x: pc.x - dr, y: pc.y - dr, width: dr * 2, height: dr * 2))
            }
            rp.line.addEllipse(in: CGRect(x: c.x - rm, y: c.y - rm, width: rm * 2, height: rm * 2))
        case .scallop:
            for j in 0..<count {
                let a = rot + Double(j) * step
                var p = Path()
                p.move(to: polar(c, a, r0))
                p.addQuadCurve(to: polar(c, a + step, r0), control: polar(c, a + step / 2, 2 * r1 - r0))
                p.closeSubpath()
                rp.a.addPath(p); rp.line.addPath(p)
                var q = Path()
                let i0 = r0 + L * 0.08, i1 = r0 + L * 0.62
                q.move(to: polar(c, a + step * 0.12, i0))
                q.addQuadCurve(to: polar(c, a + step * 0.88, i0), control: polar(c, a + step / 2, 2 * i1 - i0))
                q.closeSubpath()
                rp.b.addPath(q)
            }
        case .star:
            let vr = r0 + L * 0.3
            for j in 0..<count {
                let a = rot + Double(j) * step
                var sp = Path()
                sp.move(to: polar(c, a - step / 2, r0))
                sp.addLine(to: polar(c, a - step / 2, vr))
                sp.addLine(to: polar(c, a, r1))
                sp.addLine(to: polar(c, a + step / 2, vr))
                sp.addLine(to: polar(c, a + step / 2, r0))
                sp.closeSubpath()
                rp.a.addPath(sp); rp.line.addPath(sp)
                var ip = Path()
                ip.move(to: polar(c, a - step * 0.3, vr + L * 0.04))
                ip.addLine(to: polar(c, a, r0 + L * 0.72))
                ip.addLine(to: polar(c, a + step * 0.3, vr + L * 0.04))
                ip.closeSubpath()
                rp.b.addPath(ip)
            }
        case .diamond:
            for j in 0..<count {
                let a = rot + Double(j) * step
                var p = Path()
                p.move(to: polar(c, a, r0))
                p.addLine(to: polar(c, a - step * 0.38, rm)); p.addLine(to: polar(c, a, r1)); p.addLine(to: polar(c, a + step * 0.38, rm))
                p.closeSubpath()
                rp.a.addPath(p); rp.line.addPath(p)
                var q = Path()
                q.move(to: polar(c, a, rm - L * 0.22))
                q.addLine(to: polar(c, a - step * 0.16, rm)); q.addLine(to: polar(c, a, rm + L * 0.22)); q.addLine(to: polar(c, a + step * 0.16, rm))
                q.closeSubpath()
                rp.b.addPath(q)
            }
        case .weave:
            let samples = max(48, count * 8)
            for pass in 0..<2 {
                var p = Path()
                for i in 0...samples {
                    let ang = rot + Double(i) / Double(samples) * 2 * Double.pi
                    let rad = rm + L * 0.38 * CGFloat(sin(Double(count) * (ang - rot) + Double(pass) * Double.pi))
                    let pt = polar(c, ang, rad)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                if pass == 0 { rp.strokeA = p } else { rp.strokeB = p }
            }
            let dr = max(1.2, L * 0.12)
            for j in 0..<(count * 2) {
                let pc = polar(c, rot + Double(j) * step / 2, rm)
                rp.gold.addEllipse(in: CGRect(x: pc.x - dr, y: pc.y - dr, width: dr * 2, height: dr * 2))
            }
        case .paisley:
            // Mango-shaped kairi: round bulb at the base, tip curling sideways;
            // alternate neighbours are mirrored so pairs face each other.
            func pt(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: u * L, y: v * hw) }
            var shape = Path()
            shape.move(to: pt(0, 0))
            shape.addCurve(to: pt(0.32, 1.0), control1: pt(0, 0.6), control2: pt(0.12, 1.0))
            shape.addCurve(to: pt(1.0, -0.45), control1: pt(0.62, 1.0), control2: pt(0.95, 0.4))
            shape.addCurve(to: pt(0.62, -0.62), control1: pt(0.98, -0.75), control2: pt(0.78, -0.75))
            shape.addCurve(to: pt(0.3, -0.95), control1: pt(0.5, -0.55), control2: pt(0.45, -0.95))
            shape.addCurve(to: pt(0, 0), control1: pt(0.12, -0.95), control2: pt(0, -0.6))
            shape.closeSubpath()
            let bulb = pt(0.34, 0)
            let innerXf = CGAffineTransform(translationX: bulb.x, y: bulb.y).scaledBy(x: 0.6, y: 0.6).translatedBy(x: -bulb.x, y: -bulb.y)
            let dr = max(1, min(L * 0.1, hw * 0.3))
            for j in 0..<count {
                let a = rot + Double(j) * step
                var xf = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: a).translatedBy(x: r0, y: 0)
                if j % 2 == 1 { xf = xf.scaledBy(x: 1, y: -1) }
                rp.a.addPath(shape.applying(xf)); rp.line.addPath(shape.applying(xf))
                rp.b.addPath(shape.applying(innerXf.concatenating(xf)))
                let e = bulb.applying(xf)
                rp.gold.addEllipse(in: CGRect(x: e.x - dr * 1.6, y: e.y - dr * 1.6, width: dr * 3.2, height: dr * 3.2))
                rp.dark.addEllipse(in: CGRect(x: e.x - dr * 0.7, y: e.y - dr * 0.7, width: dr * 1.4, height: dr * 1.4))
            }
        case .chakra:
            // Spoked wheel: twin rims, gold spokes, petals between spokes and
            // knobs where spokes meet the outer rim.
            let rIn = r0 + L * 0.1, rOut = r1 - L * 0.1
            rp.strokeA.addEllipse(in: CGRect(x: c.x - rIn, y: c.y - rIn, width: rIn * 2, height: rIn * 2))
            rp.strokeA.addEllipse(in: CGRect(x: c.x - rOut, y: c.y - rOut, width: rOut * 2, height: rOut * 2))
            let kr = max(1.2, min(L * 0.1, rOut * CGFloat(step) * 0.22))
            for j in 0..<count {
                let a = rot + Double(j) * step
                rp.line.move(to: polar(c, a, rIn)); rp.line.addLine(to: polar(c, a, rOut))
                let k = polar(c, a, rOut)
                rp.gold.addEllipse(in: CGRect(x: k.x - kr, y: k.y - kr, width: kr * 2, height: kr * 2))
                var d = Path()
                let mid = (rIn + rOut) / 2
                d.move(to: polar(c, a, mid - L * 0.12)); d.addLine(to: offset(c, a, mid, hw * 0.25))
                d.addLine(to: polar(c, a, mid + L * 0.12)); d.addLine(to: offset(c, a, mid, -hw * 0.25))
                d.closeSubpath()
                rp.a.addPath(d)
                let b = a + step / 2
                var p = Path()
                p.move(to: polar(c, b, rIn + L * 0.06))
                p.addQuadCurve(to: polar(c, b, rOut - L * 0.06), control: offset(c, b, mid, hw * 1.3))
                p.addQuadCurve(to: polar(c, b, rIn + L * 0.06), control: offset(c, b, mid, -hw * 1.3))
                rp.b.addPath(p); rp.line.addPath(p)
            }
        case .bud:
            // Tulip / trident: a tall centre petal flanked by two curling lobes.
            func pt(_ u: CGFloat, _ v: CGFloat) -> CGPoint { CGPoint(x: u * L, y: v * hw) }
            var centre = Path()
            centre.move(to: pt(0, 0))
            centre.addCurve(to: pt(1, 0), control1: pt(0.35, 0.75), control2: pt(0.8, 0.35))
            centre.addCurve(to: pt(0, 0), control1: pt(0.8, -0.35), control2: pt(0.35, -0.75))
            var lobes = Path()
            for side: CGFloat in [1, -1] {
                lobes.move(to: pt(0.05, 0.1 * side))
                lobes.addCurve(to: pt(0.72, 1.15 * side), control1: pt(0.1, 0.9 * side), control2: pt(0.4, 1.3 * side))
                lobes.addCurve(to: pt(0.28, 0.25 * side), control1: pt(0.6, 0.7 * side), control2: pt(0.45, 0.3 * side))
                lobes.closeSubpath()
            }
            let dr = max(1, min(L * 0.09, hw * 0.35))
            for j in 0..<count {
                let a = rot + Double(j) * step
                let xf = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: a).translatedBy(x: r0, y: 0)
                rp.a.addPath(centre.applying(xf)); rp.line.addPath(centre.applying(xf))
                rp.b.addPath(lobes.applying(xf)); rp.line.addPath(lobes.applying(xf))
                let d = pt(0.12, 0).applying(xf)
                rp.gold.addEllipse(in: CGRect(x: d.x - dr, y: d.y - dr, width: dr * 2, height: dr * 2))
            }
        case .swirl:
            // Comma-shaped arms sweeping around the ring like a vortex.
            let n = 14
            let sweep = step * 1.4
            for j in 0..<count {
                let a = rot + Double(j) * step
                var p = Path()
                for i in 0...n {
                    let u = CGFloat(i) / CGFloat(n)
                    let wv = hw * 0.62 * pow(sin(.pi * min(u * 1.15, 1)), 0.7)
                    let pt = offset(c, a + Double(u) * sweep, r0 + u * L, wv)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                for i in stride(from: n, through: 0, by: -1) {
                    let u = CGFloat(i) / CGFloat(n)
                    let wv = hw * 0.62 * pow(sin(.pi * min(u * 1.15, 1)), 0.7)
                    p.addLine(to: offset(c, a + Double(u) * sweep, r0 + u * L, -wv))
                }
                p.closeSubpath()
                if j % 2 == 0 { rp.a.addPath(p) } else { rp.b.addPath(p) }
                rp.line.addPath(p)
                let tip = polar(c, a + sweep * 0.55, r0 + L * 0.55)
                let dr = max(1, hw * 0.22)
                rp.gold.addEllipse(in: CGRect(x: tip.x - dr, y: tip.y - dr, width: dr * 2, height: dr * 2))
            }
        case .triangles:
            // Interlocking up/down triangles (yantra lattice).
            let span = step * 0.5
            for j in 0..<count {
                let a = rot + Double(j) * step
                var up = Path()
                up.move(to: polar(c, a, r1)); up.addLine(to: polar(c, a - span, r0)); up.addLine(to: polar(c, a + span, r0))
                up.closeSubpath()
                rp.a.addPath(up); rp.line.addPath(up)
                let b = a + step / 2
                var down = Path()
                down.move(to: polar(c, b, r0)); down.addLine(to: polar(c, b - span, r1)); down.addLine(to: polar(c, b + span, r1))
                down.closeSubpath()
                rp.strokeB.addPath(down)
                var core = Path()
                core.move(to: polar(c, a, r0 + L * 0.62)); core.addLine(to: polar(c, a - step * 0.14, r0 + L * 0.2))
                core.addLine(to: polar(c, a + step * 0.14, r0 + L * 0.2))
                core.closeSubpath()
                rp.gold.addPath(core)
                let k = polar(c, b, r1)
                let dr = max(1, hw * 0.18)
                rp.b.addEllipse(in: CGRect(x: k.x - dr, y: k.y - dr, width: dr * 2, height: dr * 2))
            }
        case .rays:
            for j in 0..<count {
                let a = rot + Double(j) * step
                var p = Path()
                p.move(to: polar(c, a - step * 0.2, r0))
                p.addLine(to: polar(c, a, j % 2 == 0 ? r1 : r0 + L * 0.62))
                p.addLine(to: polar(c, a + step * 0.2, r0))
                p.closeSubpath()
                if j % 2 == 0 { rp.a.addPath(p) } else { rp.b.addPath(p) }
            }
        }
        return rp
    }

    // MARK: Diya

    private func miniDiya(ctx: GraphicsContext, at c: CGPoint, r: CGFloat, angle: Double, lit: Double, phase: Double) {
        guard lit > 0.001 else {
            return
        }
        let flick = 0.85 + 0.1 * sin(time * 9 + phase * 1.9) + 0.05 * sin(time * 17 + phase)
        let xf = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: angle + .pi / 2)  // flame points outward
        var bowl = Path()
        bowl.move(to: CGPoint(x: -r, y: 0))
        bowl.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: -r * 1.2))   // bowl bulges toward centre
        bowl.closeSubpath()
        let g = r * 3
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: r * 0.7))
            l.blendMode = .plusLighter
            l.fill(Path(ellipseIn: CGRect(x: c.x - g, y: c.y - g, width: g * 2, height: g * 2)),
                   with: .radialGradient(Gradient(colors: [DiwaliPalette.saffron.opacity(0.5 * flick * lit), .clear]),
                                         center: c, startRadius: 0, endRadius: g))
        }
        ctx.fill(bowl.applying(xf), with: .color(DiwaliPalette.clay.opacity(lit)))
        ctx.stroke(bowl.applying(xf), with: .color(DiwaliPalette.gold.opacity(0.8 * lit)), lineWidth: 1)
        var flame = Path()
        let fh = r * 1.9 * CGFloat(flick) * CGFloat(lit)
        flame.move(to: CGPoint(x: 0, y: -r * 0.1))
        flame.addQuadCurve(to: CGPoint(x: 0, y: r * 0.1 + fh), control: CGPoint(x: -r * 0.55, y: fh * 0.45))
        flame.addQuadCurve(to: CGPoint(x: 0, y: -r * 0.1), control: CGPoint(x: r * 0.55, y: fh * 0.45))
        // Flame grows away from the pattern: local +y points outward after the rotation.
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            l.fill(flame.applying(xf), with: .color(DiwaliPalette.gold.opacity(0.95 * lit)))
            l.fill(flame.applying(CGAffineTransform(scaleX: 0.45, y: 0.6).concatenating(xf)), with: .color(Color.white.opacity(0.9 * lit)))
        }
    }
}
