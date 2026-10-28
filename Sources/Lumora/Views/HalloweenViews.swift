import LumoraKit
import SwiftUI

/// Fixed spooky-night palette shared by the Halloween effects. None of the
/// effects expose color pickers (see `EffectKind.usesColor`).
enum HalloweenPalette {
    static let night = Color(red: 0.027, green: 0.016, blue: 0.063)      // #070410
    static let dusk = Color(red: 0.133, green: 0.039, blue: 0.173)       // #220A2C
    static let moon = Color(red: 1.0, green: 0.718, blue: 0.294)         // #FFB74B
    static let pumpkin = Color(red: 0.929, green: 0.396, blue: 0.039)    // #ED650A
    static let pumpkinDark = Color(red: 0.490, green: 0.173, blue: 0.027) // #7D2C07
    static let stem = Color(red: 0.243, green: 0.314, blue: 0.098)       // #3E5019
    static let glow = Color(red: 1.0, green: 0.82, blue: 0.25)           // #FFD140
    static let ghost = Color(red: 0.84, green: 0.95, blue: 0.93)         // #D6F2ED
    static let slime = Color(red: 0.49, green: 0.93, blue: 0.20)         // #7DEE33
    static let fog = Color(red: 0.42, green: 0.30, blue: 0.55)           // #6B4D8C

    static func hash01(_ i: Int, _ salt: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return CGFloat(v - floor(v))
    }

    static func fract(_ x: Double) -> Double { x - floor(x) }

    /// Dusk sky, glowing moon and drifting fog bands — the common backdrop.
    static func drawSky(ctx: GraphicsContext, size: CGSize, time: Double, moonX: CGFloat, moonY: CGFloat, moonScale: CGFloat) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [night, dusk]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        let c = CGPoint(x: w * moonX, y: h * moonY)
        let r = min(w, h) * 0.09 * moonScale
        let pulse = 0.9 + 0.1 * sin(time * 0.4)
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 28))
            l.blendMode = .plusLighter
            let g = r * 3.2
            l.fill(Path(ellipseIn: CGRect(x: c.x - g, y: c.y - g, width: g * 2, height: g * 2)),
                   with: .radialGradient(Gradient(colors: [moon.opacity(0.5 * pulse), .clear]),
                                         center: c, startRadius: 0, endRadius: g))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .color(moon.opacity(0.95)))
        // A few craters for texture.
        for k in 0..<4 {
            let cr = r * (0.12 + 0.1 * hash01(k, 41))
            let cx = c.x + (hash01(k, 42) - 0.5) * r * 1.0
            let cy = c.y + (hash01(k, 43) - 0.5) * r * 1.0
            ctx.fill(Path(ellipseIn: CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2)),
                     with: .color(pumpkinDark.opacity(0.25)))
        }
    }

    static func drawFog(ctx: GraphicsContext, size: CGSize, time: Double, baseY: CGFloat, bands: Int) {
        let w = size.width, h = size.height
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 24))
            for i in 0..<bands {
                let y = h * baseY + CGFloat(i) * h * 0.05
                let drift = CGFloat(fract(time * (0.01 + 0.006 * Double(i)) + Double(hash01(i, 51)))) * (w * 1.6) - w * 0.3
                let bw = w * (0.7 + 0.4 * hash01(i, 52))
                l.fill(Path(ellipseIn: CGRect(x: drift - bw / 2, y: y, width: bw, height: h * 0.07)),
                       with: .color(fog.opacity(0.22)))
            }
        }
    }

    /// A bat silhouette with flapping wings, centred on `c`, wingspan `s`.
    static func bat(at c: CGPoint, span s: CGFloat, flap: Double) -> Path {
        let f = CGFloat(sin(flap))          // -1…1 wing angle
        let tipY = c.y - s * 0.28 * f
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - s * 0.06))
        // right wing
        p.addQuadCurve(to: CGPoint(x: c.x + s * 0.5, y: tipY),
                       control: CGPoint(x: c.x + s * 0.25, y: tipY - s * 0.12))
        p.addQuadCurve(to: CGPoint(x: c.x + s * 0.32, y: c.y + s * 0.04 - s * 0.08 * f),
                       control: CGPoint(x: c.x + s * 0.4, y: c.y + s * 0.02))
        p.addQuadCurve(to: CGPoint(x: c.x + s * 0.14, y: c.y + s * 0.1),
                       control: CGPoint(x: c.x + s * 0.24, y: c.y + s * 0.14))
        p.addLine(to: CGPoint(x: c.x, y: c.y + s * 0.14))
        p.addLine(to: CGPoint(x: c.x - s * 0.14, y: c.y + s * 0.1))
        // left wing (mirror)
        p.addQuadCurve(to: CGPoint(x: c.x - s * 0.32, y: c.y + s * 0.04 - s * 0.08 * f),
                       control: CGPoint(x: c.x - s * 0.24, y: c.y + s * 0.14))
        p.addQuadCurve(to: CGPoint(x: c.x - s * 0.5, y: tipY),
                       control: CGPoint(x: c.x - s * 0.4, y: c.y + s * 0.02))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - s * 0.06),
                       control: CGPoint(x: c.x - s * 0.25, y: tipY - s * 0.12))
        // ears
        p.move(to: CGPoint(x: c.x - s * 0.05, y: c.y - s * 0.05))
        p.addLine(to: CGPoint(x: c.x - s * 0.04, y: c.y - s * 0.13))
        p.addLine(to: CGPoint(x: c.x, y: c.y - s * 0.06))
        p.addLine(to: CGPoint(x: c.x + s * 0.04, y: c.y - s * 0.13))
        p.addLine(to: CGPoint(x: c.x + s * 0.05, y: c.y - s * 0.05))
        return p
    }
}

// MARK: - Effect 1: Jack-o'-Lanterns

/// **Jack-o'-Lanterns** — a row of carved pumpkins on a moonlit night, their
/// faces flickering with candlelight, fog rolling past and sparks drifting
/// up. Stateless: everything derives from `time`.
struct JackOLanternsView: View {
    let time: Double

    var body: some View {
        Canvas { ctx, size in draw(ctx: ctx, size: size) }
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }

        HalloweenPalette.drawSky(ctx: ctx, size: size, time: time, moonX: 0.75, moonY: 0.2, moonScale: 1.0)
        HalloweenPalette.drawFog(ctx: ctx, size: size, time: time, baseY: 0.62, bands: 3)

        // Back-to-front: small far pumpkins, then big near ones.
        let far: [(CGFloat, CGFloat)] = [(0.12, 0.7), (0.38, 0.62), (0.64, 0.68), (0.9, 0.64)]
        let near: [(CGFloat, CGFloat)] = [(0.25, 1.0), (0.55, 1.25), (0.82, 0.95)]
        let unit = min(w, h)
        for (i, p) in far.enumerated() {
            pumpkin(ctx: ctx, center: CGPoint(x: w * p.0, y: h * 0.78), r: unit * 0.075 * p.1, index: i, dim: 0.7)
        }
        for (i, p) in near.enumerated() {
            pumpkin(ctx: ctx, center: CGPoint(x: w * p.0, y: h * 0.91), r: unit * 0.1 * p.1, index: i + 10, dim: 1.0)
        }

        // Sparks drifting up from the lanterns.
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            for i in 0..<28 {
                let u = HalloweenPalette.fract(time * (0.06 + 0.08 * Double(HalloweenPalette.hash01(i, 5))) + Double(HalloweenPalette.hash01(i, 6)))
                let x = HalloweenPalette.hash01(i, 7) * w + CGFloat(sin(time + Double(i) * 1.9)) * 12
                let y = h * 0.9 - CGFloat(u) * h * 0.6
                let s = (1.2 + 2 * HalloweenPalette.hash01(i, 8)) * unit / 500
                l.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                       with: .color(HalloweenPalette.glow.opacity(0.85 * (1 - u))))
            }
        }
    }

    private func pumpkin(ctx: GraphicsContext, center c: CGPoint, r: CGFloat, index: Int, dim: Double) {
        let phase = Double(HalloweenPalette.hash01(index, 9)) * 6.28
        let flicker = (0.8 + 0.14 * sin(time * 8 + phase) + 0.06 * sin(time * 15.7 + phase * 2)) * dim

        // Outer glow
        let gr = r * 2.8
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: r * 0.6))
            l.blendMode = .plusLighter
            l.fill(Path(ellipseIn: CGRect(x: c.x - gr, y: c.y - gr, width: gr * 2, height: gr * 2)),
                   with: .radialGradient(Gradient(colors: [HalloweenPalette.pumpkin.opacity(0.4 * flicker), .clear]),
                                         center: c, startRadius: 0, endRadius: gr))
        }

        // Body: three overlapping lobes for the ribbed look.
        let lobes: [(CGFloat, CGFloat)] = [(-0.5, 0.72), (0.5, 0.72), (0, 1.0)]
        for (dx, sx) in lobes {
            let rect = CGRect(x: c.x + dx * r * 0.9 - r * sx, y: c.y - r * 0.85, width: r * sx * 2, height: r * 1.7)
            ctx.fill(Path(ellipseIn: rect),
                     with: .radialGradient(Gradient(colors: [HalloweenPalette.pumpkin, HalloweenPalette.pumpkinDark]),
                                           center: CGPoint(x: rect.midX, y: rect.midY - r * 0.2),
                                           startRadius: 0, endRadius: r * 1.1))
        }
        // Stem
        var stem = Path()
        stem.move(to: CGPoint(x: c.x - r * 0.1, y: c.y - r * 0.8))
        stem.addQuadCurve(to: CGPoint(x: c.x + r * 0.22, y: c.y - r * 1.15), control: CGPoint(x: c.x - r * 0.05, y: c.y - r * 1.05))
        stem.addLine(to: CGPoint(x: c.x + r * 0.34, y: c.y - r * 1.08))
        stem.addQuadCurve(to: CGPoint(x: c.x + r * 0.12, y: c.y - r * 0.8), control: CGPoint(x: c.x + r * 0.2, y: c.y - r * 0.95))
        stem.closeSubpath()
        ctx.fill(stem, with: .color(HalloweenPalette.stem))

        // Carved face, lit from within.
        var face = Path()
        func tri(_ a: CGPoint, _ b: CGPoint, _ d: CGPoint) {
            face.move(to: a); face.addLine(to: b); face.addLine(to: d); face.closeSubpath()
        }
        // eyes
        tri(CGPoint(x: c.x - r * 0.55, y: c.y - r * 0.05), CGPoint(x: c.x - r * 0.15, y: c.y - r * 0.08), CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.42))
        tri(CGPoint(x: c.x + r * 0.15, y: c.y - r * 0.08), CGPoint(x: c.x + r * 0.55, y: c.y - r * 0.05), CGPoint(x: c.x + r * 0.35, y: c.y - r * 0.42))
        // nose
        tri(CGPoint(x: c.x - r * 0.07, y: c.y + r * 0.08), CGPoint(x: c.x + r * 0.07, y: c.y + r * 0.08), CGPoint(x: c.x, y: c.y - r * 0.04))
        // jagged mouth
        var mouth = Path()
        let mx0 = c.x - r * 0.6, mx1 = c.x + r * 0.6
        mouth.move(to: CGPoint(x: mx0, y: c.y + r * 0.25))
        let teeth = 6
        for t in 0..<teeth {
            let a = mx0 + (mx1 - mx0) * CGFloat(t) / CGFloat(teeth)
            let b = mx0 + (mx1 - mx0) * CGFloat(t + 1) / CGFloat(teeth)
            mouth.addLine(to: CGPoint(x: (a + b) / 2, y: c.y + r * (t % 2 == 0 ? 0.62 : 0.4)))
            mouth.addLine(to: CGPoint(x: b, y: c.y + r * 0.28))
        }
        mouth.closeSubpath()
        face.addPath(mouth)

        ctx.drawLayer { l in
            l.addFilter(.blur(radius: r * 0.05))
            l.blendMode = .plusLighter
            l.fill(face, with: .color(HalloweenPalette.glow.opacity(min(1, flicker))))
        }
        // Inner bloom through the carvings.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: r * 0.25))
            l.blendMode = .plusLighter
            l.fill(face, with: .color(HalloweenPalette.moon.opacity(0.6 * flicker)))
        }
    }
}

// MARK: - Effect 2: Haunted Night

/// **Haunted Night** — a moonlit graveyard sky: translucent ghosts drift and
/// bob on wavy hems, bat flocks sweep across the moon, a spider dangles and
/// bobs on its thread, and fog rolls along the ground. Stateless.
struct HauntedNightView: View {
    let time: Double

    var body: some View {
        Canvas { ctx, size in draw(ctx: ctx, size: size) }
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }
        let unit = min(w, h)

        HalloweenPalette.drawSky(ctx: ctx, size: size, time: time, moonX: 0.3, moonY: 0.24, moonScale: 1.3)

        // Bats crossing the sky at different speeds/heights.
        for i in 0..<9 {
            let speed = 0.03 + 0.03 * Double(HalloweenPalette.hash01(i, 1))
            let u = HalloweenPalette.fract(time * speed + Double(HalloweenPalette.hash01(i, 2)))
            let dirRight = i % 2 == 0
            let x = (dirRight ? CGFloat(u) : CGFloat(1 - u)) * (w * 1.2) - w * 0.1
            let y = h * (0.1 + 0.4 * HalloweenPalette.hash01(i, 3)) + CGFloat(sin(time * 1.3 + Double(i) * 2)) * h * 0.03
            let span = unit * (0.05 + 0.04 * HalloweenPalette.hash01(i, 4))
            let flap = time * (9 + 3 * Double(HalloweenPalette.hash01(i, 5))) + Double(i)
            ctx.fill(HalloweenPalette.bat(at: CGPoint(x: x, y: y), span: span, flap: flap),
                     with: .color(Color.black.opacity(0.92)))
        }

        // Ground fog behind the ghosts.
        HalloweenPalette.drawFog(ctx: ctx, size: size, time: time, baseY: 0.78, bands: 3)

        // Ghosts
        let count = 4
        for i in 0..<count {
            let baseX = (CGFloat(i) + 0.5) / CGFloat(count)
            let x = w * baseX + CGFloat(sin(time * 0.35 + Double(i) * 1.7)) * w * 0.06
            let y = h * (0.45 + 0.2 * HalloweenPalette.hash01(i, 11)) + CGFloat(sin(time * 0.8 + Double(i) * 2.3)) * h * 0.035
            let r = unit * (0.085 + 0.03 * HalloweenPalette.hash01(i, 12))
            let alpha = 0.55 + 0.2 * sin(time * 0.9 + Double(i))
            ghost(ctx: ctx, center: CGPoint(x: x, y: y), r: r, alpha: alpha, index: i)
        }

        // Spider on a thread, top right.
        let sx = w * 0.82
        let drop = h * (0.18 + 0.1 * (0.5 + 0.5 * sin(time * 0.7)))
        var thread = Path()
        thread.move(to: CGPoint(x: sx, y: 0))
        thread.addLine(to: CGPoint(x: sx, y: drop))
        ctx.stroke(thread, with: .color(HalloweenPalette.ghost.opacity(0.5)), lineWidth: 1)
        spider(ctx: ctx, center: CGPoint(x: sx, y: drop + unit * 0.02), r: unit * 0.022)

        HalloweenPalette.drawFog(ctx: ctx, size: size, time: time + 40, baseY: 0.9, bands: 2)
    }

    /// A detailed ghost: tattered rippling sheet with reaching arms, ectoplasm
    /// aura, rim light, hollow eyes with glowing pupils, brows and one of four
    /// expressions (`index % 4`), plus a trail of drifting wisps.
    private func ghost(ctx: GraphicsContext, center c: CGPoint, r: CGFloat, alpha: Double, index: Int) {
        let t = time
        let ph = Double(index) * 2.1
        let lean = CGFloat(0.12 * cos(t * 0.35 + Double(index) * 1.7))   // leans into its drift
        let place = CGAffineTransform(translationX: c.x, y: c.y).scaledBy(x: r, y: r)
        // Shear about the centre so the hem trails behind the motion.
        let shear = CGAffineTransform(a: 1, b: 0, c: lean, d: 1, tx: 0, ty: 0)
        let xf = shear.concatenating(place)

        // --- Body in unit space (r = 1, origin at head centre) ------------------
        var body = Path()
        body.move(to: CGPoint(x: -0.95, y: 0.45))
        body.addCurve(to: CGPoint(x: 0, y: -1.1),
                      control1: CGPoint(x: -1.12, y: -0.55), control2: CGPoint(x: -0.6, y: -1.1))
        body.addCurve(to: CGPoint(x: 0.95, y: 0.45),
                      control1: CGPoint(x: 0.6, y: -1.1), control2: CGPoint(x: 1.12, y: -0.55))
        body.addCurve(to: CGPoint(x: 1.0, y: 1.45),
                      control1: CGPoint(x: 0.9, y: 0.8), control2: CGPoint(x: 1.1, y: 1.1))
        // Ragged hem, right → left: alternating tails of uneven length that ripple.
        let tails = 7
        for k in stride(from: tails, to: 0, by: -1) {
            let xa = -1.0 + 2.0 * Double(k - 1) / Double(tails)
            let xm = -1.0 + 2.0 * (Double(k) - 0.5) / Double(tails)
            let len = 0.3 + 0.35 * Double(HalloweenPalette.hash01(index * 9 + k, 31))
            let rip = 0.12 * sin(t * 3 + Double(k) * 1.4 + ph)
            body.addLine(to: CGPoint(x: xm + 0.07 * sin(t * 2.4 + Double(k) + ph), y: 1.45 + len + rip))
            body.addLine(to: CGPoint(x: xa, y: 1.45 + 0.05 * Double(k % 2)))
        }
        body.addCurve(to: CGPoint(x: -0.95, y: 0.45),
                      control1: CGPoint(x: -1.1, y: 1.1), control2: CGPoint(x: -0.9, y: 0.8))
        body.closeSubpath()

        // Arms: reaching out and waving.
        let wave = 0.25 * sin(t * 1.8 + ph)
        func arm(_ side: CGFloat) -> Path {
            var a = Path()
            a.move(to: CGPoint(x: side * 0.8, y: 0.3))
            a.addCurve(to: CGPoint(x: side * 1.65, y: 0.2 + wave * side),
                       control1: CGPoint(x: side * 1.2, y: 0.55), control2: CGPoint(x: side * 1.5, y: 0.5 + wave))
            return a
        }

        let bodyP = body.applying(xf)

        // --- Aura ---------------------------------------------------------------
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: r * 0.55))
            l.blendMode = .plusLighter
            l.fill(bodyP, with: .color(HalloweenPalette.slime.opacity(0.22 * alpha)))
            l.stroke(arm(-1).applying(xf), with: .color(HalloweenPalette.slime.opacity(0.18 * alpha)), lineWidth: r * 0.4)
            l.stroke(arm(1).applying(xf), with: .color(HalloweenPalette.slime.opacity(0.18 * alpha)), lineWidth: r * 0.4)
        }

        // --- Sheet + arms in one translucent layer (no double-alpha seams) ------
        ctx.drawLayer { l in
            l.opacity = alpha
            let grad = Gradient(stops: [
                .init(color: HalloweenPalette.ghost, location: 0),
                .init(color: HalloweenPalette.ghost.opacity(0.82), location: 0.55),
                .init(color: Color(red: 0.55, green: 0.85, blue: 0.8).opacity(0.25), location: 1),
            ])
            let g = GraphicsContext.Shading.linearGradient(grad,
                        startPoint: CGPoint(x: c.x, y: c.y - r * 1.1), endPoint: CGPoint(x: c.x, y: c.y + r * 1.9))
            for s in [CGFloat(-1), CGFloat(1)] {
                l.stroke(arm(s).applying(xf), with: g,
                         style: StrokeStyle(lineWidth: r * 0.34, lineCap: .round, lineJoin: .round))
            }
            l.fill(bodyP, with: g)
        }

        // Cloth folds and a rim light along the dome.
        var folds = Path()
        for k in 0..<3 {
            let x0 = -0.5 + 0.5 * Double(k)
            folds.move(to: CGPoint(x: x0, y: 0.5))
            folds.addQuadCurve(to: CGPoint(x: x0 + 0.1 * Double(k - 1), y: 1.55),
                               control: CGPoint(x: x0 + 0.18 * sin(t * 1.2 + Double(k) + ph), y: 1.0))
        }
        ctx.stroke(folds.applying(xf), with: .color(Color(red: 0.5, green: 0.75, blue: 0.75).opacity(0.3 * alpha)), lineWidth: max(1, r * 0.03))
        var rim = Path()
        rim.move(to: CGPoint(x: -0.9, y: 0.2))
        rim.addCurve(to: CGPoint(x: 0.1, y: -1.08), control1: CGPoint(x: -1.05, y: -0.55), control2: CGPoint(x: -0.55, y: -1.05))
        ctx.stroke(rim.applying(xf), with: .color(Color.white.opacity(0.55 * alpha)), lineWidth: max(1.2, r * 0.045))

        // --- Face ---------------------------------------------------------------
        func P(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y).applying(xf) }
        let eyeY = -0.12, eyeX = 0.38
        let look = CGFloat(sin(t * 0.7 + ph)) * 0.05               // pupils wander
        let variant = index % 4
        for s in [-1.0, 1.0] {
            let ex = s * eyeX
            let ew = variant == 2 ? 0.2 : 0.15
            let eh = variant == 2 ? 0.3 : (variant == 3 ? 0.17 : 0.26)
            let eye = Path(ellipseIn: CGRect(x: P(ex, eyeY).x - r * ew, y: P(ex, eyeY).y - r * eh,
                                             width: r * ew * 2, height: r * eh * 2))
            ctx.fill(eye, with: .color(Color(red: 0.02, green: 0.03, blue: 0.06).opacity(0.9 * alpha)))
            // Glowing pupil + glint.
            let pc = CGPoint(x: P(ex, eyeY).x + look * r, y: P(ex, eyeY + (variant == 3 ? 0.02 : 0.05)).y)
            let pr = r * 0.075
            ctx.drawLayer { l in
                l.blendMode = .plusLighter
                l.addFilter(.blur(radius: r * 0.03))
                l.fill(Path(ellipseIn: CGRect(x: pc.x - pr * 1.6, y: pc.y - pr * 1.6, width: pr * 3.2, height: pr * 3.2)),
                       with: .color((variant == 3 ? Color.red : HalloweenPalette.slime).opacity(0.55 * alpha)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2)),
                     with: .color(Color.white.opacity(0.95 * alpha)))
            // Brow
            var brow = Path()
            switch variant {
            case 1, 3:  // angry
                brow.move(to: P(ex - s * 0.18, eyeY - 0.36)); brow.addLine(to: P(ex + s * 0.2, eyeY - 0.2))
            case 2:     // worried
                brow.move(to: P(ex - s * 0.18, eyeY - 0.26)); brow.addLine(to: P(ex + s * 0.18, eyeY - 0.4))
            default:    // sad
                brow.move(to: P(ex - s * 0.18, eyeY - 0.22)); brow.addLine(to: P(ex + s * 0.18, eyeY - 0.34))
            }
            ctx.stroke(brow, with: .color(Color(red: 0.05, green: 0.08, blue: 0.1).opacity(0.75 * alpha)),
                       style: StrokeStyle(lineWidth: max(1.2, r * 0.045), lineCap: .round))
        }
        // Mouth
        let dark = Color(red: 0.02, green: 0.03, blue: 0.06).opacity(0.9 * alpha)
        switch variant {
        case 0:   // long mournful wail
            let m = 0.2 + 0.1 * sin(t * 2 + ph)
            ctx.fill(Path(ellipseIn: CGRect(x: P(0, 0.5).x - r * 0.17, y: P(0, 0.5).y - r * m,
                                            width: r * 0.34, height: r * m * 2)), with: .color(dark))
        case 1:   // toothy grin
            var mouth = Path()
            mouth.move(to: P(-0.45, 0.3))
            mouth.addQuadCurve(to: P(0.45, 0.3), control: P(0, 0.95))
            mouth.closeSubpath()
            ctx.fill(mouth, with: .color(dark))
            var teeth = Path()
            for k in 0..<5 {
                let x = -0.32 + 0.16 * Double(k)
                teeth.move(to: P(x, 0.34 + 0.02 * abs(Double(k) - 2)))
                teeth.addLine(to: P(x + 0.08, 0.5)); teeth.addLine(to: P(x + 0.16, 0.34))
            }
            ctx.fill(teeth, with: .color(HalloweenPalette.ghost.opacity(0.9 * alpha)))
        case 2:   // startled "o"
            ctx.fill(Path(ellipseIn: CGRect(x: P(0, 0.5).x - r * 0.13, y: P(0, 0.5).y - r * 0.16,
                                            width: r * 0.26, height: r * 0.32)), with: .color(dark))
        default:  // sinister smirk
            var mouth = Path()
            mouth.move(to: P(-0.42, 0.42))
            mouth.addQuadCurve(to: P(0.46, 0.3), control: P(0.1, 0.78))
            ctx.stroke(mouth, with: .color(dark), style: StrokeStyle(lineWidth: max(1.5, r * 0.07), lineCap: .round))
        }

        // --- Wisps trailing off the hem -----------------------------------------
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: r * 0.08))
            l.blendMode = .plusLighter
            for k in 0..<6 {
                let u = HalloweenPalette.fract(t * 0.25 + Double(k) / 6 + Double(index) * 0.13)
                let wx = c.x + CGFloat(sin(t * 1.1 + Double(k) * 2.0 + ph)) * r * 0.7 - CGFloat(u) * r * 0.5 * (lean < 0 ? -1 : 1)
                let wy = c.y + r * 1.8 + CGFloat(u) * r * 1.1
                let wr = r * (0.07 + 0.05 * CGFloat(1 - u))
                l.fill(Path(ellipseIn: CGRect(x: wx - wr, y: wy - wr, width: wr * 2, height: wr * 2)),
                       with: .color(HalloweenPalette.slime.opacity(0.4 * (1 - u) * alpha)))
            }
        }
    }

    private func spider(ctx: GraphicsContext, center c: CGPoint, r: CGFloat) {
        let ink = Color.black.opacity(0.95)
        // Legs
        var legs = Path()
        for side in [CGFloat(-1), CGFloat(1)] {
            for k in 0..<4 {
                let y0 = c.y + (CGFloat(k) - 1.5) * r * 0.35
                let wiggle = CGFloat(sin(time * 2.2 + Double(k))) * r * 0.15
                let mid = CGPoint(x: c.x + side * r * 1.6, y: y0 - r * 0.9 + wiggle)
                let end = CGPoint(x: c.x + side * r * 2.4, y: y0 + r * 0.7 + wiggle)
                legs.move(to: CGPoint(x: c.x, y: y0))
                legs.addLine(to: mid)
                legs.addLine(to: end)
            }
        }
        ctx.stroke(legs, with: .color(ink), lineWidth: max(1, r * 0.14))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.7, y: c.y - r * 0.2, width: r * 1.4, height: r * 1.6)), with: .color(ink))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.45, y: c.y - r * 0.9, width: r * 0.9, height: r * 0.9)), with: .color(ink))
        // Glowing eyes
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            for sx in [CGFloat(-0.18), CGFloat(0.18)] {
                let e = r * 0.1
                l.fill(Path(ellipseIn: CGRect(x: c.x + sx * r - e, y: c.y - r * 0.55 - e, width: e * 2, height: e * 2)),
                       with: .color(Color.red.opacity(0.95)))
            }
        }
    }
}
