import SwiftUI

/// Figure styles for **Rangoli Bloom**: one large figurative motif (a royal
/// peacock, a glowing diya) drawn inside the effect's decorative border.
/// Stateless: everything is a function of `t`, and `reveal` (0…1) stages the
/// figure in as the build cycle progresses. Coordinates are in units of `R`
/// (the mandala radius) about `center`.
enum RangoliFigures {

    private static func smooth(_ v: Double, _ a: Double, _ b: Double) -> Double {
        let x = min(max((v - a) / (b - a), 0), 1)
        return x * x * (3 - 2 * x)
    }

    private static func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - rx, y: c.y - ry, width: rx * 2, height: ry * 2))
    }

    // MARK: Royal Peacock

    /// A peacock in profile with its tail fanned behind it. The fan unfolds
    /// during the build, breathes open and shut, shivers now and then, and a
    /// shimmer runs across the feather eyes; the head bobs and the crest twinkles.
    static func peacock(ctx: GraphicsContext, center: CGPoint, R: CGFloat, colors: [Color], reveal: Double, t: Double, motion: Double) {
        func col(_ i: Int) -> Color { colors[i % colors.count] }
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: center.x + x * R, y: center.y + y * R) }

        let bodyIn = smooth(reveal, 0, 0.3)
        let fanIn = smooth(reveal, 0.22, 1.0)

        // The whole bird sways gently about its feet.
        var g = ctx
        let feet = p(0, 0.6)
        g.translateBy(x: feet.x, y: feet.y)
        g.rotate(by: .radians(motion * 0.025 * sin(t * 0.7)))
        g.translateBy(x: -feet.x, y: -feet.y)

        let gold = DiwaliPalette.gold
        let eyeMid = Color(red: 0.05, green: 0.78, blue: 0.68)
        let eyeInner = Color(red: 0.12, green: 0.32, blue: 0.95)
        let navy = Color(red: 0.02, green: 0.05, blue: 0.24)

        // Tail fan: two rows of feathers radiating from behind the body.
        let pivot = p(0, 0.24)
        let spread = (0.92 + 0.08 * motion * sin(t * 0.8)) * fanIn
        let shiver = motion * 0.014 * pow(max(0, sin(t * 0.45)), 10)
        let rows: [(n: Int, len: CGFloat, w: CGFloat, half: Double, ca: Int, cb: Int)] = [
            (17, 0.72, 0.064, 1.52, 0, 2),
            (13, 0.52, 0.056, 1.40, 3, 1),
        ]
        for (ri, row) in rows.enumerated() {
            var vaneA = Path(), vaneB = Path(), barbs = Path(), eGold = Path(), eMid = Path(), eIn = Path(), pupil = Path()
            let L = R * row.len * CGFloat(0.4 + 0.6 * fanIn)
            let w = R * row.w
            var highlights: [(Path, Double)] = []
            for i in 0..<row.n {
                let f = Double(i) / Double(row.n - 1) * 2 - 1
                let a = -Double.pi / 2 + f * row.half * spread + shiver * sin(t * 31 + Double(i) * 1.7)
                let xf = CGAffineTransform(translationX: pivot.x, y: pivot.y).rotated(by: a)
                var v = Path()
                v.move(to: CGPoint(x: L * 0.16, y: 0))
                v.addCurve(to: CGPoint(x: L, y: 0), control1: CGPoint(x: L * 0.5, y: w * 0.9), control2: CGPoint(x: L * 1.03, y: w * 1.2))
                v.addCurve(to: CGPoint(x: L * 0.16, y: 0), control1: CGPoint(x: L * 1.03, y: -w * 1.2), control2: CGPoint(x: L * 0.5, y: -w * 0.9))
                if i % 2 == 0 { vaneA.addPath(v, transform: xf) } else { vaneB.addPath(v, transform: xf) }
                var b = Path()
                b.move(to: .zero); b.addLine(to: CGPoint(x: L * 0.74, y: 0))
                for j in 0..<5 {
                    let x = L * (0.3 + 0.09 * CGFloat(j))
                    let s = w * (0.45 + 0.12 * CGFloat(j))
                    b.move(to: CGPoint(x: x, y: 0)); b.addLine(to: CGPoint(x: x + w * 0.5, y: s))
                    b.move(to: CGPoint(x: x, y: 0)); b.addLine(to: CGPoint(x: x + w * 0.5, y: -s))
                }
                barbs.addPath(b, transform: xf)
                let ec = CGPoint(x: L * 0.84, y: 0)
                eGold.addPath(ellipse(ec, L * 0.12, w * 0.95), transform: xf)
                eMid.addPath(ellipse(CGPoint(x: L * 0.85, y: 0), L * 0.085, w * 0.68), transform: xf)
                eIn.addPath(ellipse(CGPoint(x: L * 0.86, y: 0), L * 0.058, w * 0.46), transform: xf)
                pupil.addPath(ellipse(CGPoint(x: L * 0.865, y: 0), L * 0.03, w * 0.24), transform: xf)
                let pulse = pow(max(0, sin(t * 1.5 - Double(i) * 0.45 - Double(ri) * 0.8)), 6) * (0.3 + 0.7 * motion)
                if pulse > 0.03 {
                    highlights.append((ellipse(ec, L * 0.1, w * 0.8).applying(xf), pulse))
                }
            }
            let al = fanIn
            g.fill(vaneA, with: .color(col(row.ca).opacity(0.9 * al)))
            g.fill(vaneB, with: .color(col(row.cb).opacity(0.9 * al)))
            g.stroke(barbs, with: .color(gold.opacity(0.7 * al)), lineWidth: max(0.7, R * 0.004))
            g.fill(eGold, with: .color(gold.opacity(al)))
            g.fill(eMid, with: .color(eyeMid.opacity(al)))
            g.fill(eIn, with: .color(eyeInner.opacity(al)))
            g.fill(pupil, with: .color(navy.opacity(al)))
            for (h, pulse) in highlights {
                g.fill(h, with: .color(Color.white.opacity(0.45 * pulse * al)))
            }
        }

        // Short gold petals fringing the base of the fan.
        var fringe = Path()
        for i in 0..<11 {
            let a = -Double.pi / 2 + (Double(i) / 10 * 2 - 1) * 1.3 * spread
            let xf = CGAffineTransform(translationX: pivot.x, y: pivot.y).rotated(by: a)
            let l = R * 0.24, hw = R * 0.03
            var v = Path()
            v.move(to: .zero)
            v.addQuadCurve(to: CGPoint(x: l, y: 0), control: CGPoint(x: l * 0.5, y: hw * 2))
            v.addQuadCurve(to: .zero, control: CGPoint(x: l * 0.5, y: -hw * 2))
            fringe.addPath(v, transform: xf)
        }
        g.fill(fringe, with: .color(gold.opacity(0.85 * fanIn)))

        // Body, neck and head (bobbing).
        guard bodyIn > 0.001 else { return }
        var b = g
        let anchor = p(0, 0.4)
        let sc = CGFloat(0.6 + 0.4 * bodyIn)
        b.translateBy(x: anchor.x, y: anchor.y); b.scaleBy(x: sc, y: sc); b.translateBy(x: -anchor.x, y: -anchor.y)
        b.opacity = bodyIn
        let bob = CGFloat(motion * 0.014 * sin(t * 1.9))

        // Wing behind/along the body.
        var wing = Path()
        wing.move(to: p(-0.02, 0.17))
        wing.addCurve(to: p(-0.25, 0.52), control1: p(-0.13, 0.21), control2: p(-0.25, 0.37))
        wing.addCurve(to: p(-0.02, 0.17), control1: p(-0.10, 0.50), control2: p(0.03, 0.34))
        var body = Path()
        body.move(to: p(0, 0.48))
        body.addQuadCurve(to: p(0.13, 0.30), control: p(0.14, 0.48))
        body.addQuadCurve(to: p(0.06, 0.12), control: p(0.13, 0.18))
        body.addCurve(to: p(0.13 + bob, -0.15), control1: p(0.0, 0.02), control2: p(0.15 + bob, -0.05))
        body.addLine(to: p(0.06 + bob, -0.20))
        body.addCurve(to: p(-0.03, 0.10), control1: p(0.0 + bob, -0.08), control2: p(-0.08, 0.02))
        body.addQuadCurve(to: p(-0.13, 0.30), control: p(-0.12, 0.15))
        body.addQuadCurve(to: p(0, 0.48), control: p(-0.14, 0.48))
        body.closeSubpath()
        let blue = Color(red: 0.10, green: 0.42, blue: 1.0), deep = Color(red: 0.02, green: 0.16, blue: 0.58)
        b.fill(body, with: .linearGradient(Gradient(colors: [blue, deep]), startPoint: p(0.1, -0.2), endPoint: p(-0.1, 0.48)))

        // Feather scales on the breast, clipped to the body.
        b.drawLayer { l in
            l.clip(to: body)
            var scales = Path()
            var row = 0
            var y: CGFloat = 0.06
            while y < 0.47 {
                var x: CGFloat = -0.16 + (row % 2 == 0 ? 0 : 0.022)
                while x < 0.16 {
                    let c = p(x, y)
                    scales.addArc(center: c, radius: R * 0.02, startAngle: .degrees(20), endAngle: .degrees(160), clockwise: false)
                    x += 0.044
                }
                y += 0.034; row += 1
            }
            l.stroke(scales, with: .color(eyeMid.opacity(0.55)), lineWidth: max(0.7, R * 0.004))
        }
        b.stroke(body, with: .color(gold.opacity(0.8)), lineWidth: max(1, R * 0.006))

        b.fill(wing, with: .linearGradient(Gradient(colors: [col(1), col(3)]), startPoint: p(-0.02, 0.17), endPoint: p(-0.25, 0.52)))
        var stripes = Path()
        for k in 1...3 {
            let s = CGFloat(k) * 0.045
            stripes.move(to: p(-0.03 - s * 0.3, 0.2 + s * 0.4))
            stripes.addQuadCurve(to: p(-0.22 + s * 0.4, 0.5 - s * 0.2), control: p(-0.16 + s * 0.2, 0.3 + s * 0.6))
        }
        b.stroke(stripes, with: .color(gold.opacity(0.8)), lineWidth: max(0.8, R * 0.005))
        b.stroke(wing, with: .color(gold), lineWidth: max(1, R * 0.006))

        // Head, beak, eye.
        let hc = p(0.105 + bob, -0.205)
        b.fill(ellipse(hc, R * 0.052, R * 0.048), with: .color(blue))
        b.stroke(ellipse(hc, R * 0.052, R * 0.048), with: .color(gold.opacity(0.8)), lineWidth: max(1, R * 0.005))
        var beak = Path()
        beak.move(to: p(0.148 + bob, -0.222)); beak.addLine(to: p(0.215 + bob, -0.198)); beak.addLine(to: p(0.148 + bob, -0.182))
        beak.closeSubpath()
        b.fill(beak, with: .color(gold))
        b.fill(ellipse(p(0.118 + bob, -0.212), R * 0.018, R * 0.012), with: .color(.white))
        b.fill(ellipse(p(0.121 + bob, -0.212), R * 0.008, R * 0.008), with: .color(navy))

        // Crest: fan of stems tipped with twinkling beads.
        var stems = Path()
        for i in 0..<5 {
            let a = -Double.pi / 2 + (Double(i) - 2) * 0.22 + motion * 0.05 * sin(t * 2.3 + Double(i))
            let base = p(0.09 + bob, -0.245)
            let tip = CGPoint(x: base.x + CGFloat(cos(a)) * R * 0.1, y: base.y + CGFloat(sin(a)) * R * 0.1)
            stems.move(to: base); stems.addLine(to: tip)
            let tw = 0.7 + 0.3 * sin(t * 3 + Double(i) * 1.3)
            b.fill(ellipse(tip, R * 0.016, R * 0.016), with: .color(gold.opacity(tw)))
            b.fill(ellipse(tip, R * 0.008, R * 0.008), with: .color(eyeMid))
        }
        b.stroke(stems, with: .color(gold), lineWidth: max(1, R * 0.005))

        // Legs and a dotted ground line.
        var legs = Path()
        for x: CGFloat in [-0.035, 0.045] {
            legs.move(to: p(x, 0.46)); legs.addLine(to: p(x - 0.005, 0.6))
            for d: CGFloat in [-0.03, 0, 0.03] {
                legs.move(to: p(x - 0.005, 0.6)); legs.addLine(to: p(x - 0.005 + d, 0.625))
            }
        }
        b.stroke(legs, with: .color(gold), style: StrokeStyle(lineWidth: max(1.2, R * 0.009), lineCap: .round))
        for i in 0..<13 {
            let x = CGFloat(i - 6) * 0.04
            b.fill(ellipse(p(x, 0.65), R * 0.011, R * 0.011), with: .color((i % 2 == 0 ? gold : col(i)).opacity(0.9)))
        }
    }

    // MARK: Glowing Diya

    /// A large oil lamp on a stand: an aura of lotus petals and light rays
    /// unfurls behind it, then the flame ignites, flickers and sheds sparks.
    static func diya(ctx: GraphicsContext, center: CGPoint, R: CGFloat, colors: [Color], reveal: Double, t: Double, motion: Double) {
        func col(_ i: Int) -> Color { colors[i % colors.count] }
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: center.x + x * R, y: center.y + y * R) }

        let baseIn = smooth(reveal, 0, 0.35)
        let auraIn = smooth(reveal, 0.25, 0.75)
        let flameIn = smooth(reveal, 0.55, 1.0)
        let gold = DiwaliPalette.gold
        let m = 0.35 + 0.65 * motion
        let flicker = 1 + m * (0.05 * sin(t * 7.3) + 0.04 * sin(t * 11.1 + 0.6))
        let auraC = p(0, -0.12)

        // Light rays, rotating slowly behind everything.
        if auraIn > 0.001 {
            var raysA = Path(), raysB = Path()
            for i in 0..<28 {
                let a = Double(i) / 28 * 2 * .pi + t * 0.05
                let r1 = R * (i % 2 == 0 ? 0.62 : 0.5) * CGFloat(auraIn)
                let da = 0.035
                var ray = Path()
                ray.move(to: CGPoint(x: auraC.x + CGFloat(cos(a - da)) * R * 0.16, y: auraC.y + CGFloat(sin(a - da)) * R * 0.16))
                ray.addLine(to: CGPoint(x: auraC.x + CGFloat(cos(a)) * r1, y: auraC.y + CGFloat(sin(a)) * r1))
                ray.addLine(to: CGPoint(x: auraC.x + CGFloat(cos(a + da)) * R * 0.16, y: auraC.y + CGFloat(sin(a + da)) * R * 0.16))
                ray.closeSubpath()
                if i % 2 == 0 { raysA.addPath(ray) } else { raysB.addPath(ray) }
            }
            let rp = 0.75 + 0.25 * sin(t * 1.2) * m
            ctx.fill(raysA, with: .color(gold.opacity(0.35 * auraIn * rp)))
            ctx.fill(raysB, with: .color(col(1).opacity(0.3 * auraIn)))

            // Lotus aura: two counter-rotating petal rings plus a bead ring.
            for (k, ring) in [(n: 16, r0: 0.30, r1: 0.52, rot: t * 0.04), (n: 12, r0: 0.24, r1: 0.38, rot: -t * 0.06 + 0.13)].enumerated() {
                var pa = Path(), pb = Path(), veins = Path()
                let open = CGFloat(1 + motion * 0.12 * sin(t * 1.6 - Double(k)))
                for i in 0..<ring.n {
                    let a = Double(i) / Double(ring.n) * 2 * .pi + ring.rot
                    let xf = CGAffineTransform(translationX: auraC.x, y: auraC.y).rotated(by: a)
                    let r0 = R * CGFloat(ring.r0), r1 = R * CGFloat(ring.r0 + (ring.r1 - ring.r0) * auraIn)
                    let hw = R * 0.06 * open * CGFloat(auraIn)
                    var v = Path()
                    v.move(to: CGPoint(x: r0, y: 0))
                    v.addCurve(to: CGPoint(x: r1, y: 0), control1: CGPoint(x: r0 + (r1 - r0) * 0.3, y: hw * 1.3), control2: CGPoint(x: r1 - (r1 - r0) * 0.2, y: hw * 0.6))
                    v.addCurve(to: CGPoint(x: r0, y: 0), control1: CGPoint(x: r1 - (r1 - r0) * 0.2, y: -hw * 0.6), control2: CGPoint(x: r0 + (r1 - r0) * 0.3, y: -hw * 1.3))
                    if i % 2 == 0 { pa.addPath(v, transform: xf) } else { pb.addPath(v, transform: xf) }
                    var vein = Path()
                    vein.move(to: CGPoint(x: r0 + (r1 - r0) * 0.15, y: 0)); vein.addLine(to: CGPoint(x: r1 - (r1 - r0) * 0.1, y: 0))
                    veins.addPath(vein, transform: xf)
                }
                ctx.fill(pa, with: .color(col(k == 0 ? 0 : 3).opacity(0.9 * auraIn)))
                ctx.fill(pb, with: .color(col(k == 0 ? 2 : 4).opacity(0.9 * auraIn)))
                ctx.stroke(pa, with: .color(gold.opacity(0.8 * auraIn)), lineWidth: max(0.8, R * 0.004))
                ctx.stroke(pb, with: .color(gold.opacity(0.8 * auraIn)), lineWidth: max(0.8, R * 0.004))
                ctx.stroke(veins, with: .color(gold.opacity(0.7 * auraIn)), lineWidth: max(0.6, R * 0.003))
            }
            for i in 0..<36 {
                let a = Double(i) / 36 * 2 * .pi - t * 0.05
                let c = CGPoint(x: auraC.x + CGFloat(cos(a)) * R * 0.565, y: auraC.y + CGFloat(sin(a)) * R * 0.565)
                ctx.fill(ellipse(c, R * 0.012, R * 0.012), with: .color((i % 2 == 0 ? gold : col(1)).opacity(auraIn)))
            }
        }

        guard baseIn > 0.001 else { return }
        var b = ctx
        b.opacity = baseIn
        let lift = CGFloat(1 - baseIn) * R * 0.08
        b.translateBy(x: 0, y: lift)

        // Stand: pedestal and base plate.
        var ped = Path()
        ped.move(to: p(-0.07, 0.32)); ped.addLine(to: p(0.07, 0.32))
        ped.addLine(to: p(0.13, 0.5)); ped.addLine(to: p(-0.13, 0.5)); ped.closeSubpath()
        b.fill(ped, with: .linearGradient(Gradient(colors: [col(2), col(3)]), startPoint: p(0, 0.32), endPoint: p(0, 0.5)))
        b.stroke(ped, with: .color(gold), lineWidth: max(1, R * 0.005))
        let plate = ellipse(p(0, 0.52), R * 0.25, R * 0.05)
        b.fill(plate, with: .color(col(1)))
        b.stroke(plate, with: .color(gold), lineWidth: max(1, R * 0.006))
        for i in 0..<14 {
            let a = Double(i) / 14 * 2 * .pi
            let c = p(CGFloat(cos(a)) * 0.2, 0.52 + CGFloat(sin(a)) * 0.032)
            b.fill(ellipse(c, R * 0.009, R * 0.009), with: .color(gold))
        }

        // Bowl with an oil-filled rim.
        var bowl = Path()
        bowl.move(to: p(-0.40, 0.10))
        bowl.addQuadCurve(to: p(0, 0.35), control: p(-0.38, 0.34))
        bowl.addQuadCurve(to: p(0.40, 0.10), control: p(0.38, 0.34))
        bowl.addQuadCurve(to: p(-0.40, 0.10), control: p(0, 0.17))
        b.fill(bowl, with: .linearGradient(Gradient(colors: [col(0), DiwaliPalette.clayDark]), startPoint: p(0, 0.1), endPoint: p(0, 0.35)))
        b.stroke(bowl, with: .color(gold), lineWidth: max(1.2, R * 0.007))
        let rim = ellipse(p(0, 0.10), R * 0.40, R * 0.055)
        b.fill(rim, with: .color(Color(red: 0.28, green: 0.10, blue: 0.02)))
        b.stroke(rim, with: .color(gold), lineWidth: max(1.2, R * 0.007))
        // Decoration: scallops and dots across the bowl.
        var scal = Path()
        for i in 0..<9 {
            let x = -0.30 + CGFloat(i) * 0.075
            scal.addArc(center: p(x, 0.175), radius: R * 0.0375, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        }
        b.stroke(scal, with: .color(gold.opacity(0.9)), lineWidth: max(0.8, R * 0.005))
        for i in 0..<7 {
            let x = -0.225 + CGFloat(i) * 0.075
            let y = 0.255 + abs(x) * 0.12
            b.fill(ellipse(p(x, y), R * 0.016, R * 0.016), with: .color(col(i + 2)))
            b.fill(ellipse(p(x, y), R * 0.007, R * 0.007), with: .color(gold))
        }

        // Flame, glow and sparks.
        guard flameIn > 0.001 else { return }
        let base = p(0, 0.09)
        let H = R * 0.40 * CGFloat(flameIn) * CGFloat(1 + m * (0.07 * sin(t * 5.7 + 1) + 0.05 * sin(t * 13.3)))
        let W = R * 0.085 * CGFloat(flicker)
        let sway = R * CGFloat(m * (0.03 * sin(t * 3.1) + 0.02 * sin(t * 7.7)))
        func flame(_ s: CGFloat) -> Path {
            let h = H * s, w = W * s
            let tip = CGPoint(x: base.x + sway * s, y: base.y - h)
            var f = Path()
            f.move(to: base)
            f.addCurve(to: tip, control1: CGPoint(x: base.x + w * 1.5, y: base.y - h * 0.1), control2: CGPoint(x: base.x + w * 0.4 + sway * 0.5 * s, y: base.y - h * 0.62))
            f.addCurve(to: base, control1: CGPoint(x: base.x - w * 0.4 + sway * 0.5 * s, y: base.y - h * 0.62), control2: CGPoint(x: base.x - w * 1.5, y: base.y - h * 0.1))
            return f
        }
        b.drawLayer { l in
            l.addFilter(.blur(radius: R * 0.08))
            l.blendMode = .plusLighter
            let gr = R * 0.42 * CGFloat(flicker)
            l.fill(ellipse(CGPoint(x: base.x, y: base.y - H * 0.45), gr, gr),
                   with: .color(DiwaliPalette.saffron.opacity(0.45 * flameIn)))
        }
        b.fill(flame(1.35), with: .color(DiwaliPalette.flame.opacity(0.55 * flameIn)))
        b.fill(flame(1.0), with: .color(DiwaliPalette.saffron.opacity(flameIn)))
        b.fill(flame(0.68), with: .color(gold.opacity(flameIn)))
        b.fill(flame(0.36), with: .color(Color.white.opacity(0.95 * flameIn)))
        var wick = Path()
        wick.move(to: base); wick.addLine(to: CGPoint(x: base.x, y: base.y - R * 0.03))
        b.stroke(wick, with: .color(Color.black.opacity(0.8)), lineWidth: max(1, R * 0.008))

        b.drawLayer { l in
            l.blendMode = .plusLighter
            for i in 0..<16 {
                let h1 = Double(DiwaliPalette.hash01(i, 301)), h2 = Double(DiwaliPalette.hash01(i, 302))
                let v = DiwaliPalette.fract(t * (0.18 + 0.12 * h1) + h2)
                let x = base.x + CGFloat(sin(t * 1.3 + Double(i) * 2.1) * v) * R * 0.1
                let y = base.y - H * 0.9 - CGFloat(v) * R * 0.38
                let s = R * 0.008 * CGFloat(1 - v * 0.6)
                l.fill(ellipse(CGPoint(x: x, y: y), s, s), with: .color(gold.opacity((1 - v) * flameIn * 0.9)))
            }
        }
    }

}
