import LumoraKit
import SwiftUI

/// Brighter, candy-coloured Halloween palette for the "party" scenes (violet
/// skies, hot orange, lime and pink) as opposed to the moodier `HalloweenPalette`.
enum BrightHalloween {
    static let ink = Color(red: 0.03, green: 0.01, blue: 0.07)
    static let violet = Color(red: 0.16, green: 0.04, blue: 0.38)
    static let purple = Color(red: 0.42, green: 0.10, blue: 0.55)
    static let magenta = Color(red: 0.85, green: 0.28, blue: 0.55)
    static let orange = Color(red: 1.0, green: 0.55, blue: 0.10)
    static let yellow = Color(red: 1.0, green: 0.86, blue: 0.25)
    static let lime = Color(red: 0.55, green: 1.0, blue: 0.20)
    static let pink = Color(red: 1.0, green: 0.4, blue: 0.75)
    static let cyan = Color(red: 0.35, green: 0.95, blue: 1.0)
    static let bone = Color(red: 0.98, green: 0.96, blue: 0.86)
    static let stone = Color(red: 0.52, green: 0.56, blue: 0.74)
    static let stoneDark = Color(red: 0.26, green: 0.28, blue: 0.45)

    static func h(_ i: Int, _ salt: Int) -> CGFloat { HalloweenPalette.hash01(i, salt) }
    static func fract(_ x: Double) -> Double { x - floor(x) }

    /// A glowing 4-point sparkle.
    static func sparkle(at p: CGPoint, size s: CGFloat) -> Path {
        var q = Path()
        q.move(to: CGPoint(x: p.x, y: p.y - s))
        q.addQuadCurve(to: CGPoint(x: p.x + s, y: p.y), control: CGPoint(x: p.x + s * 0.12, y: p.y - s * 0.12))
        q.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s), control: CGPoint(x: p.x + s * 0.12, y: p.y + s * 0.12))
        q.addQuadCurve(to: CGPoint(x: p.x - s, y: p.y), control: CGPoint(x: p.x - s * 0.12, y: p.y + s * 0.12))
        q.addQuadCurve(to: CGPoint(x: p.x, y: p.y - s), control: CGPoint(x: p.x - s * 0.12, y: p.y - s * 0.12))
        return q
    }
}

// MARK: - Effect 5: Witch Ride

/// **Witch Ride** — a witch and her black cat race across an enormous
/// tangerine moon on a broom, trailing a ribbon of rainbow sparkles; bats
/// circle the moon, purple clouds drift past, and a crooked tower glows on the
/// hill below. Stateless: the witch's flight is a function of `time`.
struct WitchRideView: View {
    let time: Double

    private let period = 15.0

    var body: some View {
        Canvas { ctx, size in draw(ctx: ctx, size: size) }
    }

    // MARK: Flight path

    private func witchPoint(_ sc: Double, size: CGSize) -> CGPoint {
        let w = size.width, h = size.height
        let s = -0.22 + 1.44 * sc
        let arc = sin(Double.pi * min(max(s, 0), 1))
        let x = w * CGFloat(s)
        let y = h * CGFloat(0.36 - 0.12 * arc) + CGFloat(sin(time * 2.1)) * h * 0.012
        return CGPoint(x: x, y: y)
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }
        let unit = min(w, h)

        // Sky: violet → plum → pink → hot orange at the horizon.
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(stops: [
                    .init(color: BrightHalloween.violet, location: 0),
                    .init(color: BrightHalloween.purple, location: 0.45),
                    .init(color: BrightHalloween.magenta, location: 0.75),
                    .init(color: BrightHalloween.orange, location: 1),
                 ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
        for i in 0..<90 {
            let tw = 0.35 + 0.65 * (0.5 + 0.5 * sin(time * (0.8 + Double(BrightHalloween.h(i, 701))) + Double(i)))
            let s = 1.0 + 2.0 * BrightHalloween.h(i, 702)
            ctx.fill(Path(ellipseIn: CGRect(x: BrightHalloween.h(i, 703) * w, y: BrightHalloween.h(i, 704) * h * 0.55, width: s, height: s)),
                     with: .color(Color.white.opacity(0.7 * tw)))
        }

        let mc = CGPoint(x: w * 0.5, y: h * 0.42)
        let mr = unit * 0.29
        drawMoon(ctx: ctx, center: mc, r: mr)
        drawBats(ctx: ctx, moon: mc, mr: mr, unit: unit)
        drawClouds(ctx: ctx, size: size, layer: 0)

        // Witch trail + witch.
        let sc = BrightHalloween.fract(time / period)
        drawTrail(ctx: ctx, size: size, sc: sc, unit: unit)
        let p = witchPoint(sc, size: size)
        let q = witchPoint(min(1, sc + 0.003), size: size)
        let ang = atan2(Double(q.y - p.y), Double(q.x - p.x))
        drawWitch(ctx: ctx, at: p, scale: unit * 0.095, angle: ang * 0.6 + 0.04 * sin(time * 3))

        drawClouds(ctx: ctx, size: size, layer: 1)
        drawGround(ctx: ctx, size: size)
    }

    // MARK: Moon

    private func drawMoon(ctx: GraphicsContext, center c: CGPoint, r: CGFloat) {
        let pulse = 0.92 + 0.08 * sin(time * 0.5)
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: r * 0.35))
            l.blendMode = .plusLighter
            let g = r * 2.1
            l.fill(Path(ellipseIn: CGRect(x: c.x - g, y: c.y - g, width: g * 2, height: g * 2)),
                   with: .radialGradient(Gradient(colors: [BrightHalloween.orange.opacity(0.65 * pulse), BrightHalloween.pink.opacity(0.15), .clear]),
                                         center: c, startRadius: r * 0.6, endRadius: g))
        }
        let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.fill(disc, with: .radialGradient(Gradient(colors: [
            Color(red: 1.0, green: 0.96, blue: 0.62), Color(red: 1.0, green: 0.78, blue: 0.28), Color(red: 1.0, green: 0.55, blue: 0.14),
        ]), center: CGPoint(x: c.x - r * 0.25, y: c.y - r * 0.25), startRadius: 0, endRadius: r * 1.25))
        // Craters and maria, with a lit rim on each.
        for k in 0..<12 {
            let a = Double(BrightHalloween.h(k, 711)) * 6.28
            let d = sqrt(BrightHalloween.h(k, 712)) * 0.8
            let cr = r * (0.04 + 0.09 * BrightHalloween.h(k, 713))
            let cp = CGPoint(x: c.x + CGFloat(cos(a) * d) * r, y: c.y + CGFloat(sin(a) * d) * r)
            ctx.fill(Path(ellipseIn: CGRect(x: cp.x - cr, y: cp.y - cr, width: cr * 2, height: cr * 2)),
                     with: .color(Color(red: 0.85, green: 0.45, blue: 0.1).opacity(0.28)))
            ctx.stroke(Path(ellipseIn: CGRect(x: cp.x - cr, y: cp.y - cr * 1.02, width: cr * 2, height: cr * 2)),
                       with: .color(Color.white.opacity(0.18)), lineWidth: max(1, cr * 0.12))
        }
        // Spooky face-like maria.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: r * 0.05))
            for (dx, dy, k) in [(-0.35, -0.2, 0.18), (0.3, -0.25, 0.14), (0.0, 0.3, 0.22)] as [(CGFloat, CGFloat, CGFloat)] {
                l.fill(Path(ellipseIn: CGRect(x: c.x + dx * r - r * k, y: c.y + dy * r - r * k * 0.8, width: r * k * 2, height: r * k * 1.6)),
                       with: .color(Color(red: 0.9, green: 0.5, blue: 0.1).opacity(0.22)))
            }
        }
    }

    // MARK: Bats

    private func drawBats(ctx: GraphicsContext, moon c: CGPoint, mr: CGFloat, unit: CGFloat) {
        var bats = Path()
        for i in 0..<16 {
            let sp = 0.25 + 0.3 * Double(BrightHalloween.h(i, 721))
            let a = time * sp * (i % 2 == 0 ? 1 : -1) + Double(BrightHalloween.h(i, 722)) * 6.28
            let rx = mr * (1.15 + 0.7 * BrightHalloween.h(i, 723))
            let ry = mr * (0.5 + 0.5 * BrightHalloween.h(i, 724))
            let pos = CGPoint(x: c.x + CGFloat(cos(a)) * rx, y: c.y + CGFloat(sin(a)) * ry - mr * 0.1)
            let span = unit * (0.035 + 0.03 * BrightHalloween.h(i, 725))
            bats.addPath(HalloweenPalette.bat(at: pos, span: span, flap: time * 11 + Double(i) * 1.3))
        }
        ctx.fill(bats, with: .color(BrightHalloween.ink))
    }

    // MARK: Clouds

    private func drawClouds(ctx: GraphicsContext, size: CGSize, layer: Int) {
        let w = size.width, h = size.height
        let unit = min(w, h)
        for i in 0..<5 {
            let seed = i + layer * 10
            let speed = 0.012 + 0.012 * Double(BrightHalloween.h(seed, 731)) + Double(layer) * 0.01
            let x = w * CGFloat(BrightHalloween.fract(time * speed + Double(BrightHalloween.h(seed, 732)))) * 1.5 - w * 0.25
            let y = h * (layer == 0 ? 0.18 + 0.4 * BrightHalloween.h(seed, 733) : 0.5 + 0.12 * BrightHalloween.h(seed, 733))
            let sc = unit * (0.1 + 0.08 * BrightHalloween.h(seed, 734)) * (layer == 0 ? 1 : 1.3)
            var cloud = Path()
            for k in 0..<6 {
                let cx = x + CGFloat(k - 3) * sc * 0.55
                let cy = y - CGFloat(sin(Double(k) * 1.4 + Double(i))) * sc * 0.14
                let rr = sc * (0.42 + 0.22 * BrightHalloween.h(seed * 7 + k, 735))
                cloud.addEllipse(in: CGRect(x: cx - rr, y: cy - rr * 0.6, width: rr * 2, height: rr * 1.2))
            }
            // Sunset-lit rim, then the dark body.
            ctx.fill(cloud.applying(CGAffineTransform(translationX: 0, y: -sc * 0.06)), with: .color(BrightHalloween.orange.opacity(layer == 0 ? 0.55 : 0.7)))
            ctx.fill(cloud, with: .color(Color(red: 0.17, green: 0.05, blue: 0.3).opacity(layer == 0 ? 0.8 : 0.92)))
        }
    }

    // MARK: Ground

    private func drawGround(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let unit = min(w, h)
        var hill = Path()
        hill.move(to: CGPoint(x: 0, y: h))
        hill.addLine(to: CGPoint(x: 0, y: h * 0.84))
        hill.addCurve(to: CGPoint(x: w, y: h * 0.8), control1: CGPoint(x: w * 0.3, y: h * 0.74), control2: CGPoint(x: w * 0.7, y: h * 0.9))
        hill.addLine(to: CGPoint(x: w, y: h))
        hill.closeSubpath()
        ctx.fill(hill, with: .color(BrightHalloween.ink))

        // Crooked tower on the left crest.
        let bx = w * 0.17, by = h * 0.8
        var tower = Path()
        tower.move(to: CGPoint(x: bx - unit * 0.06, y: by + unit * 0.02))
        tower.addLine(to: CGPoint(x: bx - unit * 0.05, y: by - unit * 0.2))
        tower.addLine(to: CGPoint(x: bx + unit * 0.07, y: by - unit * 0.21))
        tower.addLine(to: CGPoint(x: bx + unit * 0.06, y: by + unit * 0.02))
        tower.closeSubpath()
        tower.move(to: CGPoint(x: bx - unit * 0.08, y: by - unit * 0.2))
        tower.addLine(to: CGPoint(x: bx + unit * 0.01, y: by - unit * 0.37))
        tower.addLine(to: CGPoint(x: bx + unit * 0.09, y: by - unit * 0.21))
        tower.closeSubpath()
        ctx.fill(tower, with: .color(BrightHalloween.ink))
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 2))
            l.blendMode = .plusLighter
            for (i, wy) in [-0.07, -0.15].enumerated() {
                let f = 0.7 + 0.3 * sin(time * 5 + Double(i) * 2)
                l.fill(Path(roundedRect: CGRect(x: bx - unit * 0.012, y: by + CGFloat(wy) * unit, width: unit * 0.024, height: unit * 0.04), cornerRadius: unit * 0.012),
                       with: .color(BrightHalloween.lime.opacity(f)))
            }
        }
        // Gnarled tree on the right with swaying branches.
        tree(ctx: ctx, base: CGPoint(x: w * 0.84, y: h * 0.84), length: unit * 0.17, angle: -Double.pi / 2, depth: 6)
    }

    private func tree(ctx: GraphicsContext, base: CGPoint, length: CGFloat, angle: Double, depth: Int) {
        guard depth > 0 else { return }
        let sway = sin(time * 0.8 + Double(depth) * 0.9 + Double(base.x) * 0.01) * 0.03 * Double(7 - depth)
        let a = angle + sway
        let end = CGPoint(x: base.x + CGFloat(cos(a)) * length, y: base.y + CGFloat(sin(a)) * length)
        var seg = Path(); seg.move(to: base); seg.addLine(to: end)
        ctx.stroke(seg, with: .color(BrightHalloween.ink), style: StrokeStyle(lineWidth: max(1, CGFloat(depth) * 2.2), lineCap: .round))
        tree(ctx: ctx, base: end, length: length * 0.75, angle: angle - 0.5, depth: depth - 1)
        tree(ctx: ctx, base: end, length: length * 0.7, angle: angle + 0.45, depth: depth - 1)
    }

    // MARK: Trail

    private func drawTrail(ctx: GraphicsContext, size: CGSize, sc: Double, unit: CGFloat) {
        let cols: [Color] = [BrightHalloween.lime, BrightHalloween.pink, BrightHalloween.yellow, BrightHalloween.cyan, BrightHalloween.orange]
        // Soft ribbon along the recent path.
        var ribbon = Path()
        var started = false
        for k in 0...50 {
            let s2 = sc - Double(k) * 0.0035
            if s2 < 0 { break }
            let p = witchPoint(s2, size: size)
            let pt = CGPoint(x: p.x - unit * 0.1, y: p.y + unit * 0.03)
            if !started { ribbon.move(to: pt); started = true } else { ribbon.addLine(to: pt) }
        }
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: unit * 0.012))
            l.blendMode = .plusLighter
            l.stroke(ribbon, with: .color(BrightHalloween.pink.opacity(0.5)), style: StrokeStyle(lineWidth: unit * 0.02, lineCap: .round, lineJoin: .round))
            l.stroke(ribbon, with: .color(BrightHalloween.yellow.opacity(0.5)), style: StrokeStyle(lineWidth: unit * 0.007, lineCap: .round, lineJoin: .round))
        }
        // Sparkles drifting off the broom.
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            for k in 0..<80 {
                let age = Double(k) * 0.0028 + 0.002
                let s2 = sc - age
                if s2 < 0 { continue }
                let p = witchPoint(s2, size: size)
                let f = Double(k) / 80
                let jitter = CGFloat(sin(Double(k) * 12.9 + time * 2)) * unit * 0.035 * CGFloat(f + 0.1)
                let drift = CGFloat(f) * unit * 0.05
                let pt = CGPoint(x: p.x - unit * 0.12, y: p.y + unit * 0.03 + jitter + drift)
                let tw = 0.5 + 0.5 * sin(time * 9 + Double(k) * 1.7)
                let sz = unit * 0.013 * CGFloat(1 - f * 0.7) * CGFloat(0.6 + 0.6 * tw)
                l.fill(BrightHalloween.sparkle(at: pt, size: sz * 1.8), with: .color(cols[k % cols.count].opacity(0.95 * (1 - f))))
            }
        }
    }

    // MARK: Witch

    private func drawWitch(ctx: GraphicsContext, at p: CGPoint, scale u: CGFloat, angle: Double) {
        let xf = CGAffineTransform(translationX: p.x, y: p.y).rotated(by: angle).scaledBy(x: u, y: u)
        let t = time
        let ink = BrightHalloween.ink
        let flutter = CGFloat(sin(t * 7))
        let flutter2 = CGFloat(sin(t * 5 + 1.2))

        // Broom stick + bristle fan.
        var stick = Path()
        stick.move(to: CGPoint(x: -1.55, y: 0.34)); stick.addLine(to: CGPoint(x: 1.25, y: 0.3))
        ctx.stroke(stick.applying(xf), with: .color(Color(red: 0.32, green: 0.16, blue: 0.08)), style: StrokeStyle(lineWidth: u * 0.1, lineCap: .round))
        var bristles = Path()
        for k in 0..<11 {
            let dy = (CGFloat(k) - 5) * 0.075
            bristles.move(to: CGPoint(x: -1.55, y: 0.34 + dy * 0.25))
            bristles.addQuadCurve(to: CGPoint(x: -2.45 + 0.06 * flutter, y: 0.34 + dy * 1.4), control: CGPoint(x: -2.0, y: 0.34 + dy * 0.9))
        }
        ctx.stroke(bristles.applying(xf), with: .color(Color(red: 0.55, green: 0.36, blue: 0.12)), style: StrokeStyle(lineWidth: u * 0.045, lineCap: .round))
        // Binding band.
        var band = Path()
        band.move(to: CGPoint(x: -1.55, y: 0.25)); band.addLine(to: CGPoint(x: -1.55, y: 0.43))
        ctx.stroke(band.applying(xf), with: .color(BrightHalloween.orange), style: StrokeStyle(lineWidth: u * 0.07, lineCap: .butt))

        // Silhouette body: cloak, head, nose, hat.
        var body = Path()
        body.move(to: CGPoint(x: 0.12, y: -0.66))
        body.addQuadCurve(to: CGPoint(x: 0.32, y: 0.28), control: CGPoint(x: 0.5, y: -0.2))
        body.addLine(to: CGPoint(x: -0.3, y: 0.32))
        body.addQuadCurve(to: CGPoint(x: -1.35, y: 0.08 + 0.12 * flutter), control: CGPoint(x: -0.7, y: 0.6 + 0.1 * flutter2))
        body.addQuadCurve(to: CGPoint(x: -0.9, y: -0.1), control: CGPoint(x: -1.25, y: -0.12))
        body.addQuadCurve(to: CGPoint(x: 0.12, y: -0.66), control: CGPoint(x: -0.45, y: -0.5))
        body.closeSubpath()
        // Head, nose and chin.
        body.addEllipse(in: CGRect(x: 0.04, y: -1.04, width: 0.4, height: 0.42))
        body.move(to: CGPoint(x: 0.4, y: -0.9)); body.addLine(to: CGPoint(x: 0.7, y: -0.74)); body.addLine(to: CGPoint(x: 0.4, y: -0.74)); body.closeSubpath()
        body.move(to: CGPoint(x: 0.34, y: -0.66)); body.addLine(to: CGPoint(x: 0.46, y: -0.56)); body.addLine(to: CGPoint(x: 0.24, y: -0.62)); body.closeSubpath()
        // Hat brim and bendy cone.
        let bend = 0.22 * CGFloat(sin(t * 3.2))
        body.addEllipse(in: CGRect(x: -0.22, y: -1.14, width: 0.9, height: 0.17))
        body.move(to: CGPoint(x: -0.1, y: -1.06))
        body.addQuadCurve(to: CGPoint(x: -0.62 + bend, y: -1.98), control: CGPoint(x: -0.18 + bend * 0.3, y: -1.55))
        body.addQuadCurve(to: CGPoint(x: 0.52, y: -1.06), control: CGPoint(x: 0.15, y: -1.6))
        body.closeSubpath()
        // Boot.
        body.move(to: CGPoint(x: 0.0, y: 0.3))
        body.addLine(to: CGPoint(x: 0.12, y: 0.86)); body.addLine(to: CGPoint(x: 0.55, y: 0.98)); body.addLine(to: CGPoint(x: 0.5, y: 0.82))
        body.addLine(to: CGPoint(x: 0.28, y: 0.76)); body.addLine(to: CGPoint(x: 0.2, y: 0.3)); body.closeSubpath()
        // Black cat riding the tail.
        body.addEllipse(in: CGRect(x: -1.1, y: 0.0, width: 0.45, height: 0.34))
        body.addEllipse(in: CGRect(x: -0.78, y: -0.12, width: 0.27, height: 0.25))
        body.move(to: CGPoint(x: -0.76, y: -0.1)); body.addLine(to: CGPoint(x: -0.74, y: -0.26)); body.addLine(to: CGPoint(x: -0.66, y: -0.13)); body.closeSubpath()
        body.move(to: CGPoint(x: -0.63, y: -0.12)); body.addLine(to: CGPoint(x: -0.57, y: -0.26)); body.addLine(to: CGPoint(x: -0.52, y: -0.09)); body.closeSubpath()
        ctx.fill(body.applying(xf), with: .color(ink))
        ctx.stroke(body.applying(xf), with: .color(BrightHalloween.pink.opacity(0.55)), lineWidth: max(1, u * 0.025))

        // Strokes in ink: arm, leg, hair, cat tail.
        var limbs = Path()
        limbs.move(to: CGPoint(x: 0.2, y: -0.45)); limbs.addQuadCurve(to: CGPoint(x: 0.82, y: 0.28), control: CGPoint(x: 0.7, y: -0.25))
        limbs.move(to: CGPoint(x: -0.05, y: 0.3)); limbs.addLine(to: CGPoint(x: 0.12, y: 0.82))
        ctx.stroke(limbs.applying(xf), with: .color(ink), style: StrokeStyle(lineWidth: u * 0.16, lineCap: .round, lineJoin: .round))
        var hair = Path()
        for k in 0..<5 {
            let y0 = -0.95 + CGFloat(k) * 0.07
            hair.move(to: CGPoint(x: 0.1, y: y0))
            hair.addCurve(to: CGPoint(x: -0.95 + 0.1 * flutter, y: y0 + 0.25 + CGFloat(k) * 0.05),
                          control1: CGPoint(x: -0.2, y: y0 - 0.12), control2: CGPoint(x: -0.6, y: y0 + 0.3 * flutter2))
        }
        ctx.stroke(hair.applying(xf), with: .color(ink), style: StrokeStyle(lineWidth: u * 0.05, lineCap: .round))
        var tail = Path()
        tail.move(to: CGPoint(x: -1.1, y: 0.15)); tail.addCurve(to: CGPoint(x: -1.42, y: -0.38 + 0.08 * flutter), control1: CGPoint(x: -1.4, y: 0.2), control2: CGPoint(x: -1.2, y: -0.2))
        ctx.stroke(tail.applying(xf), with: .color(ink), style: StrokeStyle(lineWidth: u * 0.07, lineCap: .round))

        // Hat band, buckle, glowing eyes (cat + witch).
        var hatBand = Path()
        hatBand.move(to: CGPoint(x: -0.06, y: -1.12)); hatBand.addQuadCurve(to: CGPoint(x: 0.48, y: -1.11), control: CGPoint(x: 0.2, y: -1.0))
        ctx.stroke(hatBand.applying(xf), with: .color(BrightHalloween.purple), style: StrokeStyle(lineWidth: u * 0.07, lineCap: .butt))
        ctx.fill(Path(roundedRect: CGRect(x: 0.14, y: -1.1, width: 0.12, height: 0.09), cornerRadius: 0.02).applying(xf), with: .color(BrightHalloween.yellow))
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            let e = u * 0.035
            for ep in [CGPoint(x: 0.32, y: -0.84), CGPoint(x: -0.66, y: -0.02), CGPoint(x: -0.58, y: -0.02)] {
                let c = ep.applying(xf)
                l.fill(Path(ellipseIn: CGRect(x: c.x - e, y: c.y - e, width: e * 2, height: e * 2)),
                       with: .color(BrightHalloween.lime.opacity(0.95)))
            }
        }
    }
}

// MARK: - Effect 6: Graveyard Party

/// **Graveyard Party** — a candy-bright cemetery: carved tombstones with moss
/// and candles, an iron fence, a gnarled tree with a swinging jack-o'-lantern
/// and a blinking owl, a zombie hand clawing out of the earth, ghosts rising
/// from graves, glowing pumpkins, bats and lime ground fog. Stateless.
struct GraveyardPartyView: View {
    let time: Double

    var body: some View {
        Canvas { ctx, size in draw(ctx: ctx, size: size) }
    }

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }
        let unit = min(w, h)
        let horizon = h * 0.6

        // Sky and acid-lime moon.
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(stops: [
                    .init(color: Color(red: 0.10, green: 0.04, blue: 0.32), location: 0),
                    .init(color: Color(red: 0.38, green: 0.12, blue: 0.55), location: 0.5),
                    .init(color: Color(red: 0.95, green: 0.4, blue: 0.35), location: 1),
                 ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon + h * 0.1)))
        for i in 0..<70 {
            let tw = 0.4 + 0.6 * (0.5 + 0.5 * sin(time * (0.9 + Double(BrightHalloween.h(i, 801))) + Double(i)))
            ctx.fill(Path(ellipseIn: CGRect(x: BrightHalloween.h(i, 802) * w, y: BrightHalloween.h(i, 803) * horizon * 0.8, width: 1.8, height: 1.8)),
                     with: .color(Color.white.opacity(0.7 * tw)))
        }
        let mc = CGPoint(x: w * 0.72, y: h * 0.22)
        let mr = unit * 0.1
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: mr * 0.6))
            l.blendMode = .plusLighter
            let g = mr * 3
            l.fill(Path(ellipseIn: CGRect(x: mc.x - g, y: mc.y - g, width: g * 2, height: g * 2)),
                   with: .radialGradient(Gradient(colors: [BrightHalloween.lime.opacity(0.5), .clear]), center: mc, startRadius: 0, endRadius: g))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: mc.x - mr, y: mc.y - mr, width: mr * 2, height: mr * 2)),
                 with: .radialGradient(Gradient(colors: [Color(red: 1, green: 1, blue: 0.7), Color(red: 0.75, green: 1, blue: 0.35)]),
                                       center: CGPoint(x: mc.x - mr * 0.3, y: mc.y - mr * 0.3), startRadius: 0, endRadius: mr * 1.3))

        // Bats.
        var bats = Path()
        for i in 0..<8 {
            let u = BrightHalloween.fract(time * (0.03 + 0.02 * Double(BrightHalloween.h(i, 811))) + Double(BrightHalloween.h(i, 812)))
            let x = (i % 2 == 0 ? CGFloat(u) : CGFloat(1 - u)) * w * 1.2 - w * 0.1
            let y = h * (0.08 + 0.3 * BrightHalloween.h(i, 813)) + CGFloat(sin(time * 1.5 + Double(i))) * h * 0.03
            bats.addPath(HalloweenPalette.bat(at: CGPoint(x: x, y: y), span: unit * (0.04 + 0.03 * BrightHalloween.h(i, 814)), flap: time * 10 + Double(i)))
        }
        ctx.fill(bats, with: .color(BrightHalloween.ink))

        // Far hill, fence, ground.
        var farHill = Path()
        farHill.move(to: CGPoint(x: 0, y: horizon + h * 0.02))
        farHill.addCurve(to: CGPoint(x: w, y: horizon), control1: CGPoint(x: w * 0.3, y: horizon - h * 0.06), control2: CGPoint(x: w * 0.7, y: horizon + h * 0.04))
        farHill.addLine(to: CGPoint(x: w, y: h)); farHill.addLine(to: CGPoint(x: 0, y: h)); farHill.closeSubpath()
        ctx.fill(farHill, with: .color(Color(red: 0.16, green: 0.05, blue: 0.3)))
        drawFence(ctx: ctx, size: size, y: horizon + h * 0.015)
        drawTree(ctx: ctx, size: size, base: CGPoint(x: w * 0.88, y: horizon + h * 0.08))

        var ground = Path()
        ground.move(to: CGPoint(x: 0, y: horizon + h * 0.06))
        ground.addCurve(to: CGPoint(x: w, y: horizon + h * 0.05), control1: CGPoint(x: w * 0.35, y: horizon + h * 0.02), control2: CGPoint(x: w * 0.65, y: horizon + h * 0.1))
        ground.addLine(to: CGPoint(x: w, y: h)); ground.addLine(to: CGPoint(x: 0, y: h)); ground.closeSubpath()
        ctx.fill(ground, with: .linearGradient(Gradient(colors: [Color(red: 0.22, green: 0.1, blue: 0.4), Color(red: 0.06, green: 0.02, blue: 0.12)]),
                                               startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))

        // Tombstones back-to-front with their ghosts, candles and pumpkins.
        let stones: [(CGFloat, CGFloat, Int)] = [(0.1, 0.72, 0), (0.33, 0.7, 1), (0.52, 0.73, 2), (0.7, 0.71, 3), (0.2, 0.84, 2), (0.46, 0.88, 0), (0.78, 0.86, 1)]
        let ordered = stones.sorted { $0.1 < $1.1 }
        for (i, s) in ordered.enumerated() {
            let pos = CGPoint(x: w * s.0, y: h * s.1)
            let depth = (s.1 - 0.6) / 0.4
            tombstone(ctx: ctx, base: pos, size: unit * (0.09 + 0.07 * depth), kind: s.2, index: i)
        }
        for i in 0..<3 {
            let src = ordered[(i * 2 + 1) % ordered.count]
            ghost(ctx: ctx, from: CGPoint(x: w * src.0, y: h * src.1), unit: unit, index: i)
        }
        zombieHand(ctx: ctx, base: CGPoint(x: w * 0.62, y: h * 0.93), size: unit * 0.1)
        pumpkin(ctx: ctx, c: CGPoint(x: w * 0.04, y: h * 0.93), r: unit * 0.07, index: 0)
        pumpkin(ctx: ctx, c: CGPoint(x: w * 0.38, y: h * 0.94), r: unit * 0.05, index: 1)
        pumpkin(ctx: ctx, c: CGPoint(x: w * 0.94, y: h * 0.92), r: unit * 0.08, index: 2)
        pumpkin(ctx: ctx, c: CGPoint(x: w * 0.27, y: h * 0.77), r: unit * 0.035, index: 3)

        // Lime fog and drifting wisps in front.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 26))
            l.blendMode = .plusLighter
            for i in 0..<5 {
                let x = w * CGFloat(BrightHalloween.fract(time * (0.012 + 0.006 * Double(i)) + Double(BrightHalloween.h(i, 821)))) * 1.6 - w * 0.3
                let y = h * (0.78 + 0.04 * CGFloat(i))
                l.fill(Path(ellipseIn: CGRect(x: x - w * 0.25, y: y, width: w * 0.5, height: h * 0.08)),
                       with: .color(BrightHalloween.lime.opacity(0.13)))
            }
        }
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 2))
            l.blendMode = .plusLighter
            for i in 0..<18 {
                let u = BrightHalloween.fract(time * (0.04 + 0.04 * Double(BrightHalloween.h(i, 831))) + Double(BrightHalloween.h(i, 832)))
                let x = BrightHalloween.h(i, 833) * w + CGFloat(sin(time * 0.8 + Double(i))) * 18
                let y = h * (0.95 - 0.35 * CGFloat(u))
                let r = unit * 0.006 * CGFloat(0.5 + BrightHalloween.h(i, 834))
                l.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                       with: .color(BrightHalloween.lime.opacity(0.8 * sin(u * Double.pi))))
            }
        }
    }

    // MARK: Fence

    private func drawFence(ctx: GraphicsContext, size: CGSize, y: CGFloat) {
        let w = size.width, unit = min(size.width, size.height)
        let bars = 60
        let ht = unit * 0.1
        var p = Path()
        for i in 0...bars {
            let x = w * CGFloat(i) / CGFloat(bars)
            p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x, y: y - ht))
            p.move(to: CGPoint(x: x - 2.2, y: y - ht)); p.addLine(to: CGPoint(x: x, y: y - ht - unit * 0.02)); p.addLine(to: CGPoint(x: x + 2.2, y: y - ht))
        }
        p.move(to: CGPoint(x: 0, y: y - ht * 0.25)); p.addLine(to: CGPoint(x: w, y: y - ht * 0.25))
        p.move(to: CGPoint(x: 0, y: y - ht * 0.78)); p.addLine(to: CGPoint(x: w, y: y - ht * 0.78))
        ctx.stroke(p, with: .color(BrightHalloween.ink), style: StrokeStyle(lineWidth: max(1.2, unit * 0.003)))
        // Stone pillars with ball caps.
        for fx in [CGFloat(0.06), 0.3, 0.55, 0.8] {
            let x = w * fx, pw = unit * 0.022
            ctx.fill(Path(CGRect(x: x - pw, y: y - ht * 1.3, width: pw * 2, height: ht * 1.3)), with: .color(BrightHalloween.stoneDark))
            ctx.fill(Path(ellipseIn: CGRect(x: x - pw * 0.9, y: y - ht * 1.3 - pw * 1.6, width: pw * 1.8, height: pw * 1.8)), with: .color(BrightHalloween.stone))
        }
    }

    // MARK: Tree with lantern and owl

    private func drawTree(ctx: GraphicsContext, size: CGSize, base: CGPoint) {
        let unit = min(size.width, size.height)
        func branch(_ b: CGPoint, _ len: CGFloat, _ ang: Double, _ depth: Int) {
            guard depth > 0 else { return }
            let sway = sin(time * 0.7 + Double(depth) * 0.8) * 0.02 * Double(7 - depth)
            let a = ang + sway
            let e = CGPoint(x: b.x + CGFloat(cos(a)) * len, y: b.y + CGFloat(sin(a)) * len)
            var s = Path(); s.move(to: b); s.addLine(to: e)
            ctx.stroke(s, with: .color(BrightHalloween.ink), style: StrokeStyle(lineWidth: max(1, CGFloat(depth) * 2.4), lineCap: .round))
            branch(e, len * 0.76, ang - 0.5, depth - 1)
            branch(e, len * 0.72, ang + 0.48, depth - 1)
        }
        branch(base, unit * 0.2, -Double.pi / 2 - 0.1, 6)

        // Owl on the lowest left limb.
        let oc = CGPoint(x: base.x - unit * 0.1, y: base.y - unit * 0.3)
        let blink = BrightHalloween.fract(time * 0.25) > 0.94
        ctx.fill(Path(ellipseIn: CGRect(x: oc.x - unit * 0.022, y: oc.y - unit * 0.03, width: unit * 0.044, height: unit * 0.06)), with: .color(BrightHalloween.ink))
        var ears = Path()
        ears.move(to: CGPoint(x: oc.x - unit * 0.02, y: oc.y - unit * 0.02)); ears.addLine(to: CGPoint(x: oc.x - unit * 0.016, y: oc.y - unit * 0.045)); ears.addLine(to: CGPoint(x: oc.x - unit * 0.004, y: oc.y - unit * 0.028))
        ears.move(to: CGPoint(x: oc.x + unit * 0.02, y: oc.y - unit * 0.02)); ears.addLine(to: CGPoint(x: oc.x + unit * 0.016, y: oc.y - unit * 0.045)); ears.addLine(to: CGPoint(x: oc.x + unit * 0.004, y: oc.y - unit * 0.028))
        ctx.fill(ears, with: .color(BrightHalloween.ink))
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            for s in [CGFloat(-1), CGFloat(1)] {
                let er = unit * 0.008
                l.fill(Path(ellipseIn: CGRect(x: oc.x + s * unit * 0.01 - er, y: oc.y - unit * 0.012 - (blink ? er * 0.15 : er), width: er * 2, height: blink ? er * 0.3 : er * 2)),
                       with: .color(BrightHalloween.yellow))
            }
        }

        // Hanging jack-o'-lantern swinging from a right branch.
        let hx = base.x + unit * 0.09, hy = base.y - unit * 0.28
        let swing = CGFloat(sin(time * 1.3)) * unit * 0.025
        let lc = CGPoint(x: hx + swing, y: hy + unit * 0.14)
        var rope = Path(); rope.move(to: CGPoint(x: hx, y: hy)); rope.addLine(to: CGPoint(x: lc.x, y: lc.y - unit * 0.035))
        ctx.stroke(rope, with: .color(BrightHalloween.ink), lineWidth: 1.5)
        pumpkin(ctx: ctx, c: lc, r: unit * 0.04, index: 7)
    }

    // MARK: Tombstones

    private func tombstone(ctx: GraphicsContext, base: CGPoint, size s: CGFloat, kind: Int, index: Int) {
        let w = s, hgt = s * 1.35
        var shape = Path()
        switch kind {
        case 0:   // rounded arch
            shape.move(to: CGPoint(x: base.x - w / 2, y: base.y))
            shape.addLine(to: CGPoint(x: base.x - w / 2, y: base.y - hgt * 0.72))
            shape.addArc(center: CGPoint(x: base.x, y: base.y - hgt * 0.72), radius: w / 2, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            shape.addLine(to: CGPoint(x: base.x + w / 2, y: base.y))
        case 1:   // cross
            let t = w * 0.2
            shape.addRect(CGRect(x: base.x - t, y: base.y - hgt * 1.15, width: t * 2, height: hgt * 1.15))
            shape.addRect(CGRect(x: base.x - w * 0.42, y: base.y - hgt * 0.85, width: w * 0.84, height: t * 1.8))
        case 2:   // leaning chunky slab with bevelled top
            let lean = w * 0.12
            shape.move(to: CGPoint(x: base.x - w / 2, y: base.y))
            shape.addLine(to: CGPoint(x: base.x - w / 2 + lean, y: base.y - hgt * 0.8))
            shape.addLine(to: CGPoint(x: base.x - w * 0.3 + lean, y: base.y - hgt * 0.95))
            shape.addLine(to: CGPoint(x: base.x + w * 0.3 + lean, y: base.y - hgt * 0.95))
            shape.addLine(to: CGPoint(x: base.x + w / 2 + lean, y: base.y - hgt * 0.8))
            shape.addLine(to: CGPoint(x: base.x + w / 2, y: base.y))
        default:  // obelisk
            shape.move(to: CGPoint(x: base.x - w * 0.32, y: base.y))
            shape.addLine(to: CGPoint(x: base.x - w * 0.22, y: base.y - hgt * 1.0))
            shape.addLine(to: CGPoint(x: base.x, y: base.y - hgt * 1.3))
            shape.addLine(to: CGPoint(x: base.x + w * 0.22, y: base.y - hgt * 1.0))
            shape.addLine(to: CGPoint(x: base.x + w * 0.32, y: base.y))
        }
        shape.closeSubpath()
        ctx.fill(shape, with: .linearGradient(Gradient(colors: [BrightHalloween.stone, BrightHalloween.stoneDark]),
                                              startPoint: CGPoint(x: base.x, y: base.y - hgt), endPoint: base))
        ctx.stroke(shape, with: .color(Color.white.opacity(0.35)), lineWidth: max(1, s * 0.02))
        // Mound at the foot.
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - w * 0.7, y: base.y - s * 0.08, width: w * 1.4, height: s * 0.2)), with: .color(Color(red: 0.12, green: 0.05, blue: 0.2)))

        // Engraving.
        if kind == 0 || kind == 2 {
            ctx.draw(Text("R.I.P").font(.system(size: max(6, s * 0.2), weight: .heavy, design: .serif)).foregroundColor(BrightHalloween.stoneDark),
                     at: CGPoint(x: base.x + (kind == 2 ? w * 0.12 : 0), y: base.y - hgt * 0.58), anchor: .center)
            var line = Path()
            line.move(to: CGPoint(x: base.x - w * 0.22, y: base.y - hgt * 0.4)); line.addLine(to: CGPoint(x: base.x + w * 0.22, y: base.y - hgt * 0.4))
            ctx.stroke(line, with: .color(BrightHalloween.stoneDark), lineWidth: max(1, s * 0.025))
        }
        // Cracks, moss and grass tufts.
        var crack = Path()
        crack.move(to: CGPoint(x: base.x + w * 0.15, y: base.y - hgt * 0.3)); crack.addLine(to: CGPoint(x: base.x + w * 0.05, y: base.y - hgt * 0.18)); crack.addLine(to: CGPoint(x: base.x + w * 0.12, y: base.y - hgt * 0.08))
        ctx.stroke(crack, with: .color(BrightHalloween.stoneDark.opacity(0.8)), lineWidth: max(1, s * 0.02))
        for k in 0..<4 {
            let mx = base.x - w * 0.4 + w * 0.8 * BrightHalloween.h(index * 5 + k, 841)
            let mr = s * (0.05 + 0.07 * BrightHalloween.h(index * 5 + k, 842))
            ctx.fill(Path(ellipseIn: CGRect(x: mx - mr, y: base.y - mr * 1.2 - s * 0.02, width: mr * 2, height: mr * 1.1)), with: .color(BrightHalloween.lime.opacity(0.75)))
        }
        var grass = Path()
        for k in 0..<8 {
            let gx = base.x - w * 0.75 + w * 1.5 * CGFloat(k) / 7
            let sway = CGFloat(sin(time * 1.5 + Double(k) + Double(index))) * s * 0.03
            grass.move(to: CGPoint(x: gx, y: base.y + s * 0.02)); grass.addQuadCurve(to: CGPoint(x: gx + sway, y: base.y - s * 0.16), control: CGPoint(x: gx, y: base.y - s * 0.08))
        }
        ctx.stroke(grass, with: .color(Color(red: 0.3, green: 0.7, blue: 0.2)), style: StrokeStyle(lineWidth: max(1, s * 0.015), lineCap: .round))

        // A flickering candle beside every other stone.
        if index % 2 == 0 {
            let cp = CGPoint(x: base.x + w * 0.62, y: base.y + s * 0.02)
            let ch = s * 0.18
            ctx.fill(Path(roundedRect: CGRect(x: cp.x - s * 0.03, y: cp.y - ch, width: s * 0.06, height: ch), cornerRadius: 1), with: .color(BrightHalloween.bone))
            let f = 0.8 + 0.15 * sin(time * 9 + Double(index) * 2)
            ctx.drawLayer { l in
                l.blendMode = .plusLighter
                let g = s * 0.35
                l.fill(Path(ellipseIn: CGRect(x: cp.x - g, y: cp.y - ch - g, width: g * 2, height: g * 2)),
                       with: .radialGradient(Gradient(colors: [BrightHalloween.orange.opacity(0.5 * f), .clear]), center: CGPoint(x: cp.x, y: cp.y - ch), startRadius: 0, endRadius: g))
                var flame = Path()
                flame.move(to: CGPoint(x: cp.x, y: cp.y - ch))
                flame.addQuadCurve(to: CGPoint(x: cp.x, y: cp.y - ch - s * 0.12 * CGFloat(f)), control: CGPoint(x: cp.x - s * 0.04, y: cp.y - ch - s * 0.05))
                flame.addQuadCurve(to: CGPoint(x: cp.x, y: cp.y - ch), control: CGPoint(x: cp.x + s * 0.04, y: cp.y - ch - s * 0.05))
                l.fill(flame, with: .color(BrightHalloween.yellow))
            }
        }
    }

    // MARK: Ghost rising

    private func ghost(ctx: GraphicsContext, from src: CGPoint, unit: CGFloat, index: Int) {
        let period = 7.0 + Double(index)
        let u = BrightHalloween.fract((time + Double(index) * 2.3) / period)
        let r = unit * 0.045
        let rise = unit * 0.26 * CGFloat(u)
        let c = CGPoint(x: src.x + CGFloat(sin(time * 0.9 + Double(index) * 2)) * unit * 0.03 * CGFloat(u + 0.3), y: src.y - unit * 0.12 - rise)
        let a = sin(u * Double.pi) * 0.85
        guard a > 0.02 else { return }
        var body = Path()
        body.move(to: CGPoint(x: c.x - r, y: c.y + r * 1.6))
        body.addLine(to: CGPoint(x: c.x - r, y: c.y))
        body.addArc(center: c, radius: r, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        body.addLine(to: CGPoint(x: c.x + r, y: c.y + r * 1.6))
        for k in stride(from: 4, to: 0, by: -1) {
            let xa = c.x - r + r * 2 * CGFloat(k - 1) / 4
            let xm = c.x - r + r * 2 * (CGFloat(k) - 0.5) / 4
            body.addQuadCurve(to: CGPoint(x: xa, y: c.y + r * 1.6), control: CGPoint(x: xm, y: c.y + r * (2.1 + 0.25 * CGFloat(sin(time * 4 + Double(k) + Double(index))))))
        }
        body.closeSubpath()
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: r * 0.7))
            l.blendMode = .plusLighter
            l.fill(body, with: .color(BrightHalloween.cyan.opacity(0.4 * a)))
        }
        ctx.fill(body, with: .linearGradient(Gradient(colors: [Color.white.opacity(0.95 * a), BrightHalloween.cyan.opacity(0.35 * a)]),
                                             startPoint: CGPoint(x: c.x, y: c.y - r), endPoint: CGPoint(x: c.x, y: c.y + r * 2)))
        let dark = BrightHalloween.ink.opacity(0.85 * a)
        for s in [CGFloat(-1), CGFloat(1)] {
            ctx.fill(Path(ellipseIn: CGRect(x: c.x + s * r * 0.38 - r * 0.15, y: c.y - r * 0.3, width: r * 0.3, height: r * 0.5)), with: .color(dark))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.17, y: c.y + r * 0.35, width: r * 0.34, height: r * 0.45)), with: .color(dark))
    }

    // MARK: Zombie hand

    private func zombieHand(ctx: GraphicsContext, base: CGPoint, size s: CGFloat) {
        let skin = Color(red: 0.55, green: 0.85, blue: 0.35)
        let skinDark = Color(red: 0.3, green: 0.55, blue: 0.2)
        // Disturbed earth.
        ctx.fill(Path(ellipseIn: CGRect(x: base.x - s * 0.9, y: base.y - s * 0.15, width: s * 1.8, height: s * 0.4)), with: .color(Color(red: 0.2, green: 0.1, blue: 0.14)))
        let cycle = 6.0
        let u = BrightHalloween.fract(time / cycle)
        let rise = CGFloat(min(1, u * 3) * (u > 0.85 ? max(0, 1 - (u - 0.85) / 0.15) : 1))      // claws up, holds, sinks
        guard rise > 0.02 else { return }
        let wobble = CGFloat(sin(time * 3)) * s * 0.06
        let wrist = CGPoint(x: base.x + wobble, y: base.y - s * 1.4 * rise)
        // Forearm with a torn sleeve.
        var arm = Path(); arm.move(to: CGPoint(x: base.x, y: base.y)); arm.addQuadCurve(to: wrist, control: CGPoint(x: base.x + s * 0.25, y: base.y - s * 0.7 * rise))
        ctx.stroke(arm, with: .color(skinDark), style: StrokeStyle(lineWidth: s * 0.34, lineCap: .round))
        ctx.stroke(arm, with: .color(skin), style: StrokeStyle(lineWidth: s * 0.26, lineCap: .round))
        // Palm and wriggling, jointed fingers.
        ctx.fill(Path(ellipseIn: CGRect(x: wrist.x - s * 0.24, y: wrist.y - s * 0.2, width: s * 0.48, height: s * 0.4)), with: .color(skin))
        var fingers = Path()
        for k in 0..<5 {
            let spread = (CGFloat(k) - 2) * 0.38
            let base0 = CGPoint(x: wrist.x + (CGFloat(k) - 2) * s * 0.09, y: wrist.y - s * 0.12)
            let curl = CGFloat(sin(time * 4 + Double(k) * 0.9)) * 0.3
            let a1 = -Double.pi / 2 + Double(spread) + Double(curl) * 0.5
            let j1 = CGPoint(x: base0.x + CGFloat(cos(a1)) * s * 0.22, y: base0.y + CGFloat(sin(a1)) * s * 0.22)
            let a2 = a1 + Double(curl) * 1.2 + 0.3 * (k < 2 ? -1 : 1)
            let j2 = CGPoint(x: j1.x + CGFloat(cos(a2)) * s * 0.2, y: j1.y + CGFloat(sin(a2)) * s * 0.2)
            fingers.move(to: base0); fingers.addLine(to: j1); fingers.addLine(to: j2)
        }
        ctx.stroke(fingers, with: .color(skinDark), style: StrokeStyle(lineWidth: s * 0.13, lineCap: .round, lineJoin: .round))
        ctx.stroke(fingers, with: .color(skin), style: StrokeStyle(lineWidth: s * 0.085, lineCap: .round, lineJoin: .round))
        // Glow so it pops.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: s * 0.2))
            l.blendMode = .plusLighter
            l.fill(Path(ellipseIn: CGRect(x: wrist.x - s * 0.6, y: wrist.y - s * 0.7, width: s * 1.2, height: s * 1.2)), with: .color(BrightHalloween.lime.opacity(0.18)))
        }
    }

    // MARK: Pumpkin

    private func pumpkin(ctx: GraphicsContext, c: CGPoint, r: CGFloat, index: Int) {
        let f = 0.8 + 0.15 * sin(time * 8 + Double(index) * 1.9) + 0.05 * sin(time * 17 + Double(index))
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: r * 0.7))
            l.blendMode = .plusLighter
            let g = r * 2.4
            l.fill(Path(ellipseIn: CGRect(x: c.x - g, y: c.y - g, width: g * 2, height: g * 2)),
                   with: .radialGradient(Gradient(colors: [BrightHalloween.orange.opacity(0.5 * f), .clear]), center: c, startRadius: 0, endRadius: g))
        }
        for (dx, sx) in [(CGFloat(-0.5), CGFloat(0.72)), (0.5, 0.72), (0, 1.0)] {
            let rect = CGRect(x: c.x + dx * r * 0.9 - r * sx, y: c.y - r * 0.85, width: r * sx * 2, height: r * 1.7)
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [Color(red: 1.0, green: 0.62, blue: 0.1), Color(red: 0.8, green: 0.28, blue: 0.05)]),
                                                                    center: CGPoint(x: rect.midX, y: rect.midY - r * 0.2), startRadius: 0, endRadius: r * 1.1))
        }
        var stem = Path()
        stem.move(to: CGPoint(x: c.x - r * 0.1, y: c.y - r * 0.8)); stem.addQuadCurve(to: CGPoint(x: c.x + r * 0.2, y: c.y - r * 1.2), control: CGPoint(x: c.x - r * 0.05, y: c.y - r * 1.05))
        stem.addLine(to: CGPoint(x: c.x + r * 0.34, y: c.y - r * 1.1)); stem.addQuadCurve(to: CGPoint(x: c.x + r * 0.12, y: c.y - r * 0.8), control: CGPoint(x: c.x + r * 0.2, y: c.y - r * 0.95)); stem.closeSubpath()
        ctx.fill(stem, with: .color(Color(red: 0.3, green: 0.6, blue: 0.12)))
        var face = Path()
        func tri(_ a: CGPoint, _ b: CGPoint, _ d: CGPoint) { face.move(to: a); face.addLine(to: b); face.addLine(to: d); face.closeSubpath() }
        tri(CGPoint(x: c.x - r * 0.55, y: c.y - r * 0.05), CGPoint(x: c.x - r * 0.15, y: c.y - r * 0.08), CGPoint(x: c.x - r * 0.35, y: c.y - r * 0.42))
        tri(CGPoint(x: c.x + r * 0.15, y: c.y - r * 0.08), CGPoint(x: c.x + r * 0.55, y: c.y - r * 0.05), CGPoint(x: c.x + r * 0.35, y: c.y - r * 0.42))
        var mouth = Path()
        mouth.move(to: CGPoint(x: c.x - r * 0.6, y: c.y + r * 0.25))
        for t in 0..<6 {
            let a = c.x - r * 0.6 + r * 1.2 * CGFloat(t) / 6, b = c.x - r * 0.6 + r * 1.2 * CGFloat(t + 1) / 6
            mouth.addLine(to: CGPoint(x: (a + b) / 2, y: c.y + r * (t % 2 == 0 ? 0.62 : 0.4))); mouth.addLine(to: CGPoint(x: b, y: c.y + r * 0.28))
        }
        mouth.closeSubpath()
        face.addPath(mouth)
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            l.fill(face, with: .color(BrightHalloween.yellow.opacity(min(1, f))))
        }
    }
}
