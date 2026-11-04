import LumoraKit
import SwiftUI

// MARK: - Effect 8: Dancing Skeletons

/// **Dancing Skeletons** — three bright-boned skeletons party on a neon
/// checker dance floor under a mirror ball and sweeping coloured spotlights:
/// a disco pointer in sunglasses and top hat, a twisting party-hat dancer, and
/// a roof-raiser in a bow tie. Every joint is driven by the beat. Stateless.
struct DancingSkeletonsView: View {
    let time: Double

    private let bpm = 50.0

    var body: some View {
        Canvas { ctx, size in draw(ctx: ctx, size: size) }
    }

    private var beat: Double { time * bpm / 60 }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }
        let unit = min(w, h)
        let floorY = h * 0.66

        // Back wall.
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.12, green: 0.03, blue: 0.3), Color(red: 0.5, green: 0.1, blue: 0.5), Color(red: 0.9, green: 0.3, blue: 0.4)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: floorY)))
        drawSpotlights(ctx: ctx, size: size, floorY: floorY)
        drawFloor(ctx: ctx, size: size, floorY: floorY)
        drawDiscoBall(ctx: ctx, size: size)

        // Dancers, back to front.
        let hipY = h * 0.64
        let dancers: [(CGFloat, CGFloat, Int, Color)] = [
            (0.22, 0.9, 0, BrightHalloween.lime), (0.78, 0.9, 2, BrightHalloween.cyan), (0.5, 1.0, 1, BrightHalloween.pink),
        ]
        for (fx, scale, style, eye) in dancers {
            let s = unit * 0.36 * scale
            let root = CGPoint(x: w * fx, y: hipY + (style == 1 ? h * 0.05 : 0.0))
            drawSkeleton(ctx: ctx, hip: root, s: s, style: style, eye: eye)
        }

        // Confetti and bats in front.
        for i in 0..<60 {
            let sp = 0.06 + 0.08 * Double(BrightHalloween.h(i, 951))
            let u = BrightHalloween.fract(time * sp + Double(BrightHalloween.h(i, 952)))
            let x = BrightHalloween.h(i, 953) * w + CGFloat(sin(time * 1.2 + Double(i))) * 14
            let y = -h * 0.03 + CGFloat(u) * h * 1.06
            let cols: [Color] = [BrightHalloween.orange, BrightHalloween.lime, BrightHalloween.pink, BrightHalloween.cyan, BrightHalloween.yellow]
            let rot = time * (2 + Double(BrightHalloween.h(i, 954)) * 3) + Double(i)
            let cw = unit * 0.014, ch = unit * 0.007 * CGFloat(0.3 + abs(cos(rot * 0.7)))
            let xf = CGAffineTransform(translationX: x, y: y).rotated(by: rot)
            ctx.fill(Path(CGRect(x: -cw, y: -ch, width: cw * 2, height: ch * 2)).applying(xf), with: .color(cols[i % 5].opacity(0.95)))
        }
        var bats = Path()
        for i in 0..<5 {
            let u = BrightHalloween.fract(time * (0.04 + 0.02 * Double(i)) + Double(i) * 0.2)
            let x = (i % 2 == 0 ? CGFloat(u) : CGFloat(1 - u)) * w * 1.2 - w * 0.1
            let y = h * (0.1 + 0.15 * CGFloat(i)) + CGFloat(sin(time * 1.5 + Double(i))) * h * 0.02
            bats.addPath(HalloweenPalette.bat(at: CGPoint(x: x, y: y), span: unit * 0.05, flap: time * 10 + Double(i)))
        }
        ctx.fill(bats, with: .color(BrightHalloween.ink))
    }

    // MARK: Lights

    private func drawSpotlights(ctx: GraphicsContext, size: CGSize, floorY: CGFloat) {
        let w = size.width
        let cols: [Color] = [BrightHalloween.orange, BrightHalloween.lime, BrightHalloween.pink, BrightHalloween.cyan]
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 10))
            l.blendMode = .plusLighter
            for i in 0..<4 {
                let src = CGPoint(x: w * (0.12 + 0.25 * CGFloat(i)), y: -5)
                let sweep = sin(time * 0.6 + Double(i) * 1.7) * 0.5
                let tx = w * (0.15 + 0.23 * CGFloat(i)) + CGFloat(sweep) * w * 0.3
                let tgt = CGPoint(x: tx, y: floorY + size.height * 0.1)
                let half = size.width * 0.05
                var cone = Path()
                cone.move(to: CGPoint(x: src.x - 6, y: src.y)); cone.addLine(to: CGPoint(x: src.x + 6, y: src.y))
                cone.addLine(to: CGPoint(x: tgt.x + half, y: tgt.y)); cone.addLine(to: CGPoint(x: tgt.x - half, y: tgt.y)); cone.closeSubpath()
                l.fill(cone, with: .linearGradient(Gradient(colors: [cols[i].opacity(0.5), cols[i].opacity(0.08)]), startPoint: src, endPoint: tgt))
                l.fill(Path(ellipseIn: CGRect(x: tgt.x - half, y: tgt.y - half * 0.2, width: half * 2, height: half * 0.4)), with: .color(cols[i].opacity(0.5)))
            }
        }
    }

    private func drawFloor(ctx: GraphicsContext, size: CGSize, floorY: CGFloat) {
        let w = size.width, h = size.height
        let rows = 7, cols = 14
        let pulse = 0.65 + 0.35 * abs(sin(Double.pi * beat))
        let palette: [Color] = [BrightHalloween.orange, BrightHalloween.purple, BrightHalloween.lime, BrightHalloween.pink, BrightHalloween.cyan]
        func rowY(_ r: Int) -> CGFloat {
            let f = CGFloat(r) / CGFloat(rows)
            return floorY + (h - floorY) * (f * f * 0.6 + f * 0.4)
        }
        for r in 0..<rows {
            let y0 = rowY(r), y1 = rowY(r + 1)
            let s0 = 0.55 + 0.9 * CGFloat(r) / CGFloat(rows), s1 = 0.55 + 0.9 * CGFloat(r + 1) / CGFloat(rows)
            for c in 0..<cols {
                let u0 = CGFloat(c) / CGFloat(cols) - 0.5, u1 = CGFloat(c + 1) / CGFloat(cols) - 0.5
                var q = Path()
                q.move(to: CGPoint(x: w / 2 + u0 * w * s0, y: y0)); q.addLine(to: CGPoint(x: w / 2 + u1 * w * s0, y: y0))
                q.addLine(to: CGPoint(x: w / 2 + u1 * w * s1, y: y1)); q.addLine(to: CGPoint(x: w / 2 + u0 * w * s1, y: y1)); q.closeSubpath()
                let idx = (r + c + Int(floor(beat))) % 5
                let lit = (r + c) % 2 == 0
                let col = lit ? palette[idx] : Color(red: 0.08, green: 0.02, blue: 0.18)
                ctx.fill(q, with: .color(col.opacity(lit ? 0.55 + 0.4 * pulse : 1)))
                ctx.stroke(q, with: .color(Color.white.opacity(0.18)), lineWidth: 0.8)
            }
        }
        // Reflective sheen.
        ctx.fill(Path(CGRect(x: 0, y: floorY, width: w, height: (h - floorY) * 0.3)),
                 with: .linearGradient(Gradient(colors: [Color.white.opacity(0.12), .clear]), startPoint: CGPoint(x: 0, y: floorY), endPoint: CGPoint(x: 0, y: floorY + (h - floorY) * 0.3)))
    }

    private func drawDiscoBall(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let unit = min(w, h)
        let c = CGPoint(x: w * 0.5, y: h * 0.13)
        let r = unit * 0.06
        var rope = Path(); rope.move(to: CGPoint(x: c.x, y: 0)); rope.addLine(to: CGPoint(x: c.x, y: c.y - r))
        ctx.stroke(rope, with: .color(Color.white.opacity(0.7)), lineWidth: 2)
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: r * 0.6))
            l.blendMode = .plusLighter
            l.fill(Path(ellipseIn: CGRect(x: c.x - r * 2.5, y: c.y - r * 2.5, width: r * 5, height: r * 5)), with: .color(Color.white.opacity(0.18)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .radialGradient(Gradient(colors: [Color.white, Color(red: 0.65, green: 0.7, blue: 0.85), Color(red: 0.3, green: 0.3, blue: 0.5)]),
                                       center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.3), startRadius: 0, endRadius: r * 1.3))
        // Mirror tiles sliding across the sphere.
        var tiles = Path()
        let spin = time * 1.4
        for row in -3...3 {
            let lat = Double(row) / 4.0 * 1.2
            let rowR = r * CGFloat(cos(lat))
            for k in 0..<12 {
                let lon = Double(k) / 12 * 2 * Double.pi + spin
                if cos(lon) < 0 { continue }
                let x = c.x + rowR * CGFloat(sin(lon)), y = c.y + r * CGFloat(sin(lat))
                let sz = r * 0.14 * CGFloat(cos(lon)) + 1
                tiles.addRect(CGRect(x: x - sz, y: y - sz * 0.8, width: sz * 2, height: sz * 1.6))
            }
        }
        ctx.stroke(tiles, with: .color(Color(red: 0.2, green: 0.2, blue: 0.4).opacity(0.7)), lineWidth: 0.8)
        // Light specks cast around the room.
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            let cols: [Color] = [BrightHalloween.orange, BrightHalloween.lime, BrightHalloween.pink, BrightHalloween.cyan, BrightHalloween.yellow]
            for i in 0..<36 {
                let a = time * 0.9 + Double(i) * 0.7 + Double(BrightHalloween.h(i, 961)) * 6.28
                let d = unit * (0.15 + 0.7 * Double(BrightHalloween.h(i, 962)))
                let p = CGPoint(x: c.x + CGFloat(cos(a)) * CGFloat(d) * 1.4, y: c.y + CGFloat(abs(sin(a))) * CGFloat(d) * 0.9 + r)
                let tw = 0.4 + 0.6 * abs(sin(time * 3 + Double(i)))
                l.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(cols[i % 5].opacity(0.75 * tw)))
            }
        }
    }

    // MARK: Skeleton

    private func dir(_ a: Double) -> CGVector { CGVector(dx: cos(a), dy: sin(a)) }
    private func step(_ p: CGPoint, _ a: Double, _ d: CGFloat) -> CGPoint { CGPoint(x: p.x + CGFloat(cos(a)) * d, y: p.y + CGFloat(sin(a)) * d) }

    private func drawSkeleton(ctx: GraphicsContext, hip hip0: CGPoint, s: CGFloat, style: Int, eye: Color) {
        let th = Double.pi * 2 * beat + Double(style) * 1.3        // one dance cycle per beat
        let bone = BrightHalloween.bone
        let edge = Color(red: 0.25, green: 0.08, blue: 0.4)

        // Bounce on the beat.
        let bounce = CGFloat(abs(sin(th / 2))) * s * 0.06
        let hip = CGPoint(x: hip0.x + CGFloat(sin(th / 2)) * s * (style == 1 ? 0.1 : 0.04), y: hip0.y - bounce)
        let torsoAng = -Double.pi / 2 + 0.12 * sin(th / 2) + (style == 1 ? 0.22 * sin(th) : 0)
        let shoulderC = step(hip, torsoAng, s * 0.42)
        let neck = step(shoulderC, torsoAng, s * 0.06)
        let headBang = style == 2 ? 0.45 * sin(th) : 0.12 * sin(th)
        let skullAng = torsoAng + headBang
        let skull = step(neck, skullAng, s * 0.14)
        let perp = torsoAng + Double.pi / 2
        let shL = step(shoulderC, perp, -s * 0.13), shR = step(shoulderC, perp, s * 0.13)
        let hipL = step(hip, perp, -s * 0.07), hipR = step(hip, perp, s * 0.07)

        // Arm angles (absolute, from +x, y down) per dance style.
        var upL = 0.0, foL = 0.0, upR = 0.0, foR = 0.0
        switch style {
        case 0:   // disco point: right arm to the sky, left hand on hip
            upR = -1.15 + 0.25 * sin(th); foR = -0.95 + 0.3 * sin(th + 1)
            upL = 2.2 + 0.15 * sin(th); foL = 0.7
        case 1:   // twist: arms swing opposite to the hips
            upL = 2.3 + 0.8 * sin(th); foL = 2.6 + 0.9 * sin(th + 0.8)
            upR = 0.8 - 0.8 * sin(th); foR = 0.5 - 0.9 * sin(th + 0.8)
        default:  // raise the roof
            upL = -Double.pi / 2 - 0.55 + 0.2 * sin(th); foL = -Double.pi / 2 - 0.2 + 0.5 * sin(th * 2)
            upR = -Double.pi / 2 + 0.55 - 0.2 * sin(th); foR = -Double.pi / 2 + 0.2 - 0.5 * sin(th * 2)
        }
        let elL = step(shL, upL, s * 0.3), wrL = step(elL, foL, s * 0.28)
        let elR = step(shR, upR, s * 0.3), wrR = step(elR, foR, s * 0.28)

        // Legs: alternating steps / kicks.
        let kick = style == 0 ? 0.55 : 0.35
        let thL = Double.pi / 2 + kick * sin(th), thR = Double.pi / 2 - kick * sin(th)
        let shinL = thL - 0.15 - 0.55 * max(0, sin(th + 1.2)), shinR = thR - 0.15 - 0.55 * max(0, -sin(th + 1.2))
        let knL = step(hipL, thL, s * 0.34), anL = step(knL, shinL, s * 0.34)
        let knR = step(hipR, thR, s * 0.34), anR = step(knR, shinR, s * 0.34)

        // Glow behind the whole dancer.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: s * 0.1))
            l.blendMode = .plusLighter
            let g = s * 0.75
            l.fill(Path(ellipseIn: CGRect(x: hip.x - g * 0.5, y: hip.y - g * 1.1, width: g, height: g * 1.5)), with: .color(eye.opacity(0.22)))
        }

        func limb(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint?, width: CGFloat) {
            var p = Path(); p.move(to: a); p.addLine(to: b); if let c { p.addLine(to: c) }
            ctx.stroke(p, with: .color(edge), style: StrokeStyle(lineWidth: width + max(2, s * 0.012), lineCap: .round, lineJoin: .round))
            ctx.stroke(p, with: .color(bone), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }
        func joint(_ p: CGPoint, _ r: CGFloat) {
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(bone)); ctx.stroke(Path(ellipseIn: rect), with: .color(edge), lineWidth: max(1, s * 0.008))
        }

        // Back leg and arm first, then the torso, then the near limbs.
        limb(hipR, knR, anR, width: s * 0.045); joint(knR, s * 0.03)
        footBones(ctx: ctx, ankle: anR, ang: shinR, s: s, bone: bone, edge: edge)
        limb(shR, elR, wrR, width: s * 0.04); joint(elR, s * 0.027); hand(ctx: ctx, wrist: wrR, ang: foR, s: s, bone: bone, edge: edge, wave: th)

        // Spine, ribs, pelvis.
        for k in 0..<8 {
            let f = CGFloat(k) / 7
            let p = CGPoint(x: hip.x + (shoulderC.x - hip.x) * f, y: hip.y + (shoulderC.y - hip.y) * f)
            let r = s * 0.02
            let rect = CGRect(x: p.x - r, y: p.y - r * 0.8, width: r * 2, height: r * 1.6)
            ctx.fill(Path(roundedRect: rect, cornerRadius: r * 0.5), with: .color(bone))
            ctx.stroke(Path(roundedRect: rect, cornerRadius: r * 0.5), with: .color(edge), lineWidth: 0.8)
        }
        var ribs = Path()
        for k in 0..<5 {
            let f = 0.42 + 0.12 * CGFloat(k)
            let sp = CGPoint(x: hip.x + (shoulderC.x - hip.x) * f, y: hip.y + (shoulderC.y - hip.y) * f)
            let wdt = s * (0.14 - 0.012 * CGFloat(k)) * (k == 0 ? 0.8 : 1)
            for sd in [CGFloat(-1), CGFloat(1)] {
                let tip = CGPoint(x: sp.x + CGFloat(cos(perp)) * sd * wdt, y: sp.y + CGFloat(sin(perp)) * sd * wdt + s * 0.03)
                let ctl = CGPoint(x: sp.x + CGFloat(cos(perp)) * sd * wdt * 0.9, y: sp.y + CGFloat(sin(perp)) * sd * wdt * 0.9 - s * 0.045)
                ribs.move(to: sp); ribs.addQuadCurve(to: tip, control: ctl)
            }
        }
        ctx.stroke(ribs, with: .color(edge), style: StrokeStyle(lineWidth: max(3.2, s * 0.03), lineCap: .round))
        ctx.stroke(ribs, with: .color(bone), style: StrokeStyle(lineWidth: max(2, s * 0.02), lineCap: .round))
        var clav = Path(); clav.move(to: shL); clav.addLine(to: shR)
        ctx.stroke(clav, with: .color(edge), style: StrokeStyle(lineWidth: s * 0.04 + 2, lineCap: .round))
        ctx.stroke(clav, with: .color(bone), style: StrokeStyle(lineWidth: s * 0.04, lineCap: .round))
        var pelvis = Path(); pelvis.move(to: hipL); pelvis.addQuadCurve(to: hipR, control: step(hip, perp + Double.pi / 2 * 0 + 1.2, s * 0.08))
        pelvis.addEllipse(in: CGRect(x: hip.x - s * 0.06, y: hip.y - s * 0.03, width: s * 0.12, height: s * 0.08))
        ctx.stroke(pelvis, with: .color(edge), lineWidth: s * 0.05 + 2)
        ctx.stroke(pelvis, with: .color(bone), lineWidth: s * 0.05)
        ctx.fill(pelvis, with: .color(bone))

        // Near leg and arm.
        limb(hipL, knL, anL, width: s * 0.045); joint(knL, s * 0.03)
        footBones(ctx: ctx, ankle: anL, ang: shinL, s: s, bone: bone, edge: edge)
        limb(shL, elL, wrL, width: s * 0.04); joint(elL, s * 0.027); hand(ctx: ctx, wrist: wrL, ang: foL, s: s, bone: bone, edge: edge, wave: th + 1)
        joint(shL, s * 0.03); joint(shR, s * 0.03); joint(hipL, s * 0.03); joint(hipR, s * 0.03)

        drawSkull(ctx: ctx, center: skull, ang: skullAng, s: s, eye: eye, style: style, th: th)
    }

    private func footBones(ctx: GraphicsContext, ankle: CGPoint, ang: Double, s: CGFloat, bone: Color, edge: Color) {
        var f = Path(); f.move(to: ankle)
        f.addLine(to: step(ankle, ang + 1.1, s * 0.1)); f.addLine(to: step(step(ankle, ang + 1.1, s * 0.1), ang + 0.0, s * 0.04))
        ctx.stroke(f, with: .color(edge), style: StrokeStyle(lineWidth: s * 0.035 + 2, lineCap: .round, lineJoin: .round))
        ctx.stroke(f, with: .color(bone), style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round, lineJoin: .round))
    }

    private func hand(ctx: GraphicsContext, wrist: CGPoint, ang: Double, s: CGFloat, bone: Color, edge: Color, wave: Double) {
        var f = Path()
        for k in 0..<4 {
            let spread = (Double(k) - 1.5) * 0.3 + 0.12 * sin(wave * 2 + Double(k))
            let a = ang + spread
            f.move(to: wrist); f.addLine(to: step(wrist, a, s * 0.085))
        }
        ctx.stroke(f, with: .color(edge), style: StrokeStyle(lineWidth: max(2.5, s * 0.016) + 1.5, lineCap: .round))
        ctx.stroke(f, with: .color(bone), style: StrokeStyle(lineWidth: max(2.5, s * 0.016), lineCap: .round))
    }

    private func drawSkull(ctx: GraphicsContext, center c: CGPoint, ang: Double, s: CGFloat, eye: Color, style: Int, th: Double) {
        let bone = BrightHalloween.bone
        let edge = Color(red: 0.25, green: 0.08, blue: 0.4)
        let up = ang                       // direction from neck toward the crown
        let xf = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: up + Double.pi / 2)   // local +y faces down the face
        let r = s * 0.12
        let jawOpen = r * (0.08 + 0.35 * CGFloat(abs(sin(th))) * (style == 2 ? 1.2 : 0.8))

        // Jaw first so the cranium overlaps it.
        var jaw = Path()
        jaw.move(to: CGPoint(x: -r * 0.65, y: r * 0.55 + jawOpen * 0.2))
        jaw.addQuadCurve(to: CGPoint(x: r * 0.65, y: r * 0.55 + jawOpen * 0.2), control: CGPoint(x: 0, y: r * 1.55 + jawOpen))
        jaw.closeSubpath()
        ctx.fill(jaw.applying(xf), with: .color(bone)); ctx.stroke(jaw.applying(xf), with: .color(edge), lineWidth: max(1, s * 0.01))
        var teeth = Path()
        for k in -3...3 {
            let x = CGFloat(k) * r * 0.17
            teeth.move(to: CGPoint(x: x, y: r * 0.6 + jawOpen * 0.2)); teeth.addLine(to: CGPoint(x: x, y: r * 0.95 + jawOpen * 0.7))
        }
        ctx.stroke(teeth.applying(xf), with: .color(edge), lineWidth: max(1, s * 0.008))

        let cranium = Path(ellipseIn: CGRect(x: -r, y: -r * 1.05, width: r * 2, height: r * 1.8)).applying(xf)
        ctx.fill(cranium, with: .radialGradient(Gradient(colors: [Color.white, bone]), center: CGPoint(x: c.x - r * 0.3, y: c.y - r * 0.4), startRadius: 0, endRadius: r * 1.4))
        ctx.stroke(cranium, with: .color(edge), lineWidth: max(1.2, s * 0.012))

        // Eye sockets with glowing pupils, nose cavity, cheek cracks.
        for sd in [CGFloat(-1), CGFloat(1)] {
            let ec = CGPoint(x: sd * r * 0.42, y: -r * 0.05).applying(xf)
            let sock = Path(ellipseIn: CGRect(x: -r * 0.28, y: -r * 0.28, width: r * 0.56, height: r * 0.6)).applying(CGAffineTransform(translationX: ec.x, y: ec.y).rotated(by: up + Double.pi / 2))
            ctx.fill(sock, with: .color(BrightHalloween.ink))
            ctx.drawLayer { l in
                l.blendMode = .plusLighter
                l.addFilter(.blur(radius: r * 0.05))
                let pr = r * 0.11 * (0.8 + 0.3 * CGFloat(sin(time * 5 + Double(sd))))
                l.fill(Path(ellipseIn: CGRect(x: ec.x - pr, y: ec.y - pr, width: pr * 2, height: pr * 2)), with: .color(eye))
            }
        }
        var nose = Path()
        nose.move(to: CGPoint(x: 0, y: r * 0.18)); nose.addLine(to: CGPoint(x: -r * 0.1, y: r * 0.45)); nose.addLine(to: CGPoint(x: r * 0.1, y: r * 0.45)); nose.closeSubpath()
        ctx.fill(nose.applying(xf), with: .color(BrightHalloween.ink))
        var crack = Path()
        crack.move(to: CGPoint(x: r * 0.3, y: -r * 0.95)); crack.addLine(to: CGPoint(x: r * 0.18, y: -r * 0.65)); crack.addLine(to: CGPoint(x: r * 0.3, y: -r * 0.5))
        ctx.stroke(crack.applying(xf), with: .color(edge.opacity(0.6)), lineWidth: max(1, s * 0.008))

        // Accessories.
        switch style {
        case 0:
            // Neon sunglasses + top hat.
            var shades = Path()
            shades.addRoundedRect(in: CGRect(x: -r * 0.78, y: -r * 0.28, width: r * 0.68, height: r * 0.42), cornerSize: CGSize(width: r * 0.1, height: r * 0.1))
            shades.addRoundedRect(in: CGRect(x: r * 0.1, y: -r * 0.28, width: r * 0.68, height: r * 0.42), cornerSize: CGSize(width: r * 0.1, height: r * 0.1))
            shades.move(to: CGPoint(x: -r * 0.1, y: -r * 0.12)); shades.addLine(to: CGPoint(x: r * 0.1, y: -r * 0.12))
            ctx.fill(shades.applying(xf), with: .color(BrightHalloween.pink.opacity(0.9)))
            ctx.stroke(shades.applying(xf), with: .color(BrightHalloween.ink), lineWidth: max(1.2, s * 0.012))
            var hat = Path()
            hat.addRoundedRect(in: CGRect(x: -r * 1.2, y: -r * 1.22, width: r * 2.4, height: r * 0.2), cornerSize: CGSize(width: r * 0.08, height: r * 0.08))
            hat.addRoundedRect(in: CGRect(x: -r * 0.7, y: -r * 2.1, width: r * 1.4, height: r * 0.95), cornerSize: CGSize(width: r * 0.08, height: r * 0.08))
            ctx.fill(hat.applying(xf), with: .color(Color(red: 0.12, green: 0.04, blue: 0.2)))
            ctx.fill(Path(CGRect(x: -r * 0.7, y: -r * 1.3, width: r * 1.4, height: r * 0.18)).applying(xf), with: .color(BrightHalloween.orange))
        case 1:
            // Party hat with a pompom.
            var cone = Path()
            cone.move(to: CGPoint(x: -r * 0.6, y: -r * 0.85)); cone.addLine(to: CGPoint(x: 0, y: -r * 2.2)); cone.addLine(to: CGPoint(x: r * 0.6, y: -r * 0.85)); cone.closeSubpath()
            ctx.fill(cone.applying(xf), with: .linearGradient(Gradient(colors: [BrightHalloween.yellow, BrightHalloween.magenta]),
                                                              startPoint: CGPoint(x: c.x, y: c.y - r * 2), endPoint: CGPoint(x: c.x, y: c.y - r)))
            ctx.stroke(cone.applying(xf), with: .color(edge), lineWidth: 1.2)
            let pc = CGPoint(x: 0, y: -r * 2.25).applying(xf)
            ctx.fill(Path(ellipseIn: CGRect(x: pc.x - r * 0.18, y: pc.y - r * 0.18, width: r * 0.36, height: r * 0.36)), with: .color(BrightHalloween.cyan))
        default:
            // Bow tie under the jaw is drawn with the skull for simplicity.
            var bow = Path()
            bow.move(to: CGPoint(x: 0, y: r * 1.35)); bow.addLine(to: CGPoint(x: -r * 0.55, y: r * 1.1)); bow.addLine(to: CGPoint(x: -r * 0.55, y: r * 1.65)); bow.closeSubpath()
            bow.move(to: CGPoint(x: 0, y: r * 1.35)); bow.addLine(to: CGPoint(x: r * 0.55, y: r * 1.1)); bow.addLine(to: CGPoint(x: r * 0.55, y: r * 1.65)); bow.closeSubpath()
            ctx.fill(bow.applying(xf), with: .color(BrightHalloween.orange))
            ctx.stroke(bow.applying(xf), with: .color(edge), lineWidth: 1)
            let kc = CGPoint(x: 0, y: r * 1.35).applying(xf)
            ctx.fill(Path(ellipseIn: CGRect(x: kc.x - r * 0.1, y: kc.y - r * 0.1, width: r * 0.2, height: r * 0.2)), with: .color(BrightHalloween.yellow))
        }
    }
}
