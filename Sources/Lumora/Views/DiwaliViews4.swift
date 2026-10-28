import LumoraKit
import SwiftUI

// MARK: - Effect 7: Happy Deepawali Placard

/// **Happy Deepawali** — a gilded signboard hanging on swaying chains. Two
/// rings of multicolour bulbs chase around its frame, the lettering glows and
/// shimmers, rosettes sit in the corners, and a row of diyas burns beneath it
/// while golden sparkles drift past. Stateless.
struct DeepawaliPlacardView: View {
    let time: Double

    private let bulbColors: [Color] = [
        Color(red: 1.0, green: 0.30, blue: 0.55),   // pink
        Color(red: 1.0, green: 0.58, blue: 0.10),   // orange
        Color(red: 1.0, green: 0.88, blue: 0.20),   // yellow
        Color(red: 0.45, green: 1.0, blue: 0.35),   // green
        Color(red: 0.25, green: 0.90, blue: 1.0),   // cyan
        Color(red: 0.70, green: 0.40, blue: 1.0),   // violet
    ]
    private let gold = Color(red: 1.0, green: 0.80, blue: 0.28)
    private let goldDark = Color(red: 0.62, green: 0.38, blue: 0.06)

    var body: some View {
        Canvas { ctx, size in draw(ctx: ctx, size: size) }
    }

    // MARK: Perimeter sampling

    /// Point at distance `d` along the perimeter of a rounded rect, clockwise from the top-left straight.
    private func perimeterPoint(_ dist: CGFloat, rect: CGRect, rc: CGFloat) -> CGPoint {
        let sw = rect.width - 2 * rc, sh = rect.height - 2 * rc
        let arc = rc * CGFloat.pi / 2
        let total = 2 * sw + 2 * sh + 4 * arc
        var d = dist.truncatingRemainder(dividingBy: total)
        if d < 0 { d += total }
        func arcPt(_ cx: CGFloat, _ cy: CGFloat, _ a0: Double, _ len: CGFloat) -> CGPoint {
            let a = a0 + Double(len / rc)
            return CGPoint(x: cx + CGFloat(cos(a)) * rc, y: cy + CGFloat(sin(a)) * rc)
        }
        if d < sw { return CGPoint(x: rect.minX + rc + d, y: rect.minY) }; d -= sw
        if d < arc { return arcPt(rect.maxX - rc, rect.minY + rc, -Double.pi / 2, d) }; d -= arc
        if d < sh { return CGPoint(x: rect.maxX, y: rect.minY + rc + d) }; d -= sh
        if d < arc { return arcPt(rect.maxX - rc, rect.maxY - rc, 0, d) }; d -= arc
        if d < sw { return CGPoint(x: rect.maxX - rc - d, y: rect.maxY) }; d -= sw
        if d < arc { return arcPt(rect.minX + rc, rect.maxY - rc, Double.pi / 2, d) }; d -= arc
        if d < sh { return CGPoint(x: rect.minX, y: rect.maxY - rc - d) }; d -= sh
        return arcPt(rect.minX + rc, rect.minY + rc, Double.pi, d)
    }

    private func perimeter(_ rect: CGRect, rc: CGFloat) -> CGFloat {
        2 * (rect.width - 2 * rc) + 2 * (rect.height - 2 * rc) + 4 * rc * CGFloat.pi / 2
    }

    // MARK: Draw

    private func draw(ctx base: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        guard w > 1, h > 1 else { return }
        var ctx = base

        // Backdrop: deep maroon with warm bokeh.
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .radialGradient(Gradient(colors: [Color(red: 0.32, green: 0.05, blue: 0.10), Color(red: 0.06, green: 0.01, blue: 0.05)]),
                                       center: CGPoint(x: w / 2, y: h * 0.45), startRadius: 0, endRadius: max(w, h) * 0.8))
        let unit = min(w, h)
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 16))
            l.blendMode = .plusLighter
            for i in 0..<20 {
                let r = unit * (0.02 + 0.05 * BrightHalloween.h(i, 1001))
                let u = BrightHalloween.fract(time * (0.01 + 0.015 * Double(BrightHalloween.h(i, 1002))) + Double(BrightHalloween.h(i, 1003)))
                let x = BrightHalloween.h(i, 1004) * w, y = h * (1.05 - 1.1 * CGFloat(u))
                l.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                       with: .color(bulbColors[i % 6].opacity(0.16 * sin(u * Double.pi))))
            }
        }

        // Placard geometry.
        let pw = min(w * 0.86, h * 1.75)
        let ph = min(pw * 0.52, h * 0.56)
        let pcx = w / 2, ptop = h * 0.14
        let panel = CGRect(x: pcx - pw / 2, y: ptop, width: pw, height: ph)
        let rc = ph * 0.14

        // Chains up to the top edge, then the whole board sways from its hooks.
        for sx in [panel.minX + pw * 0.1, panel.maxX - pw * 0.1] {
            var chain = Path()
            chain.move(to: CGPoint(x: sx, y: ptop)); chain.addLine(to: CGPoint(x: pcx, y: -4))
            ctx.stroke(chain, with: .color(goldDark), style: StrokeStyle(lineWidth: ph * 0.028))
            ctx.stroke(chain, with: .color(gold), style: StrokeStyle(lineWidth: ph * 0.02, dash: [ph * 0.03, ph * 0.025]))
        }
        let sway = 0.012 * sin(time * 0.9)
        ctx.translateBy(x: pcx, y: 0)
        ctx.rotate(by: .radians(sway))
        ctx.translateBy(x: -pcx, y: 0)

        // Drop shadow + glow behind the board.
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: ph * 0.1))
            l.blendMode = .plusLighter
            l.fill(Path(roundedRect: panel.insetBy(dx: -ph * 0.04, dy: -ph * 0.04), cornerRadius: rc),
                   with: .color(Color(red: 1, green: 0.5, blue: 0.15).opacity(0.25)))
        }

        // Gilded frame, dark face, inner line.
        let framePath = Path(roundedRect: panel, cornerRadius: rc)
        ctx.fill(framePath, with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.9, blue: 0.5), gold, goldDark]),
                                                  startPoint: CGPoint(x: panel.minX, y: panel.minY), endPoint: CGPoint(x: panel.maxX, y: panel.maxY)))
        let faceRect = panel.insetBy(dx: ph * 0.065, dy: ph * 0.065)
        let face = Path(roundedRect: faceRect, cornerRadius: rc * 0.7)
        ctx.fill(face, with: .radialGradient(Gradient(colors: [Color(red: 0.42, green: 0.06, blue: 0.22), Color(red: 0.14, green: 0.02, blue: 0.16)]),
                                             center: CGPoint(x: panel.midX, y: panel.midY), startRadius: 0, endRadius: pw * 0.55))
        ctx.stroke(face, with: .color(gold.opacity(0.9)), lineWidth: max(1.5, ph * 0.012))
        let innerLine = Path(roundedRect: faceRect.insetBy(dx: ph * 0.025, dy: ph * 0.025), cornerRadius: rc * 0.55)
        ctx.stroke(innerLine, with: .color(gold.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

        drawBulbs(ctx: ctx, panel: panel, rc: rc, ph: ph)
        drawCorners(ctx: ctx, faceRect: faceRect, ph: ph)
        drawLettering(ctx: ctx, faceRect: faceRect, ph: ph)

        // Diyas burning on a shelf beneath.
        let shelfY = panel.maxY + ph * 0.2
        let count = 7
        for i in 0..<count {
            let x = panel.minX + pw * (0.1 + 0.8 * CGFloat(i) / CGFloat(count - 1))
            let mid = abs(CGFloat(i) - CGFloat(count - 1) / 2) / (CGFloat(count - 1) / 2)
            drawDiya(ctx: ctx, at: CGPoint(x: x, y: shelfY + mid * ph * 0.04), r: ph * (0.055 - 0.01 * mid), phase: Double(i))
        }

        // Golden sparkles drifting up the whole scene.
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            for i in 0..<40 {
                let u = BrightHalloween.fract(time * (0.05 + 0.06 * Double(BrightHalloween.h(i, 1011))) + Double(BrightHalloween.h(i, 1012)))
                let x = BrightHalloween.h(i, 1013) * w + CGFloat(sin(time * 0.9 + Double(i))) * 12
                let y = h * (1.02 - 1.04 * CGFloat(u))
                let tw = 0.4 + 0.6 * abs(sin(time * 4 + Double(i) * 1.3))
                l.fill(BrightHalloween.sparkle(at: CGPoint(x: x, y: y), size: unit * 0.012 * CGFloat(0.5 + BrightHalloween.h(i, 1014)) * CGFloat(tw + 0.3)),
                       with: .color(gold.opacity(0.9 * sin(u * Double.pi))))
            }
        }
    }

    // MARK: Bulbs

    private func drawBulbs(ctx: GraphicsContext, panel: CGRect, rc: CGFloat, ph: CGFloat) {
        let ring1 = panel.insetBy(dx: ph * 0.032, dy: ph * 0.032)
        let rc1 = rc - ph * 0.032
        let total1 = perimeter(ring1, rc: rc1)
        let n1 = Int(total1 / (ph * 0.085))
        let shift = Int(floor(time * 5))

        struct Bulb { var p: CGPoint; var c: Color; var b: Double; var r: CGFloat }
        var bulbs: [Bulb] = []
        for i in 0..<n1 {
            let p = perimeterPoint(total1 * CGFloat(i) / CGFloat(n1) + CGFloat(time) * ph * 0.0, rect: ring1, rc: rc1)
            let b = 0.45 + 0.55 * pow(0.5 + 0.5 * sin(time * 6 - Double(i) * 0.55), 2)
            bulbs.append(Bulb(p: p, c: bulbColors[(i + shift) % 6], b: b, r: ph * 0.028))
        }
        // Inner ring of smaller bulbs chasing the other way.
        let ring2 = panel.insetBy(dx: ph * 0.1, dy: ph * 0.1)
        let rc2 = max(ph * 0.04, rc * 0.7 - ph * 0.035)
        let total2 = perimeter(ring2, rc: rc2)
        let n2 = Int(total2 / (ph * 0.06))
        for i in 0..<n2 {
            let p = perimeterPoint(total2 * CGFloat(i) / CGFloat(n2), rect: ring2, rc: rc2)
            let b = 0.4 + 0.6 * pow(0.5 + 0.5 * sin(time * 5 + Double(i) * 0.7), 2)
            bulbs.append(Bulb(p: p, c: bulbColors[((i * 5 - shift) % 6 + 6) % 6], b: b, r: ph * 0.016))
        }

        // Sockets, then halos, then lit cores.
        for bu in bulbs {
            let s = bu.r * 1.35
            ctx.fill(Path(ellipseIn: CGRect(x: bu.p.x - s, y: bu.p.y - s, width: s * 2, height: s * 2)), with: .color(goldDark))
        }
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: ph * 0.02))
            l.blendMode = .plusLighter
            for bu in bulbs {
                let g = bu.r * 3
                l.fill(Path(ellipseIn: CGRect(x: bu.p.x - g, y: bu.p.y - g, width: g * 2, height: g * 2)), with: .color(bu.c.opacity(0.45 * bu.b)))
            }
        }
        for bu in bulbs {
            let r = bu.r
            ctx.fill(Path(ellipseIn: CGRect(x: bu.p.x - r, y: bu.p.y - r, width: r * 2, height: r * 2)), with: .color(bu.c.opacity(0.35 + 0.65 * bu.b)))
            ctx.fill(Path(ellipseIn: CGRect(x: bu.p.x - r * 0.45, y: bu.p.y - r * 0.55, width: r * 0.8, height: r * 0.7)), with: .color(Color.white.opacity(0.35 + 0.6 * bu.b)))
        }
    }

    // MARK: Corner rosettes

    private func drawCorners(ctx: GraphicsContext, faceRect: CGRect, ph: CGFloat) {
        let inset = ph * 0.11
        let pts = [CGPoint(x: faceRect.minX + inset, y: faceRect.minY + inset), CGPoint(x: faceRect.maxX - inset, y: faceRect.minY + inset),
                   CGPoint(x: faceRect.minX + inset, y: faceRect.maxY - inset), CGPoint(x: faceRect.maxX - inset, y: faceRect.maxY - inset)]
        for (i, c) in pts.enumerated() {
            let r = ph * 0.065
            let spin = time * 0.5 * (i % 2 == 0 ? 1 : -1)
            var outer = Path(), inner = Path()
            for k in 0..<8 {
                let a = spin + Double(k) / 8 * 2 * Double.pi
                let p0 = CGPoint(x: c.x + CGFloat(cos(a)) * r * 0.25, y: c.y + CGFloat(sin(a)) * r * 0.25)
                let p1 = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
                let side = a + Double.pi / 2
                let wdt = r * 0.2
                outer.move(to: p0)
                outer.addQuadCurve(to: p1, control: CGPoint(x: (p0.x + p1.x) / 2 + CGFloat(cos(side)) * wdt * 2, y: (p0.y + p1.y) / 2 + CGFloat(sin(side)) * wdt * 2))
                outer.addQuadCurve(to: p0, control: CGPoint(x: (p0.x + p1.x) / 2 - CGFloat(cos(side)) * wdt * 2, y: (p0.y + p1.y) / 2 - CGFloat(sin(side)) * wdt * 2))
                let p2 = CGPoint(x: c.x + CGFloat(cos(a + Double.pi / 8)) * r * 0.6, y: c.y + CGFloat(sin(a + Double.pi / 8)) * r * 0.6)
                inner.addEllipse(in: CGRect(x: p2.x - r * 0.08, y: p2.y - r * 0.08, width: r * 0.16, height: r * 0.16))
            }
            ctx.fill(outer, with: .color(bulbColors[(i * 2) % 6].opacity(0.9)))
            ctx.stroke(outer, with: .color(gold), lineWidth: 1)
            ctx.fill(inner, with: .color(gold))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.14, y: c.y - r * 0.14, width: r * 0.28, height: r * 0.28)), with: .color(Color.white))
        }
    }

    // MARK: Lettering

    private func drawLettering(ctx: GraphicsContext, faceRect: CGRect, ph: CGFloat) {
        let cx = faceRect.midX
        let cy = faceRect.midY

        // "Happy" in script above, "Deepawali" in glowing bold serif below.
        let happyFont = Font.custom("Snell Roundhand", size: ph * 0.26).weight(.bold)
        var happy = ctx.resolve(Text("Happy").font(happyFont).foregroundColor(Color.white))
        happy.shading = .color(Color.white)
        let hs = happy.measure(in: CGSize(width: 2000, height: 2000))
        let happyPt = CGPoint(x: cx, y: cy - ph * 0.17)
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: ph * 0.03))
            l.blendMode = .plusLighter
            l.draw(ctx.resolve(Text("Happy").font(happyFont).foregroundColor(bulbColors[Int(time * 1.2) % 6].opacity(0.8))), at: happyPt, anchor: .center)
        }
        ctx.draw(ctx.resolve(Text("Happy").font(happyFont).foregroundColor(Color(red: 1, green: 0.95, blue: 0.85))), at: happyPt, anchor: .center)
        _ = hs

        let word = Array("Deepawali")
        var fs = ph * 0.3
        let measure: (CGFloat) -> [CGFloat] = { size in
            word.map { ch in
                ctx.resolve(Text(String(ch)).font(.system(size: size, weight: .black, design: .serif))).measure(in: CGSize(width: 2000, height: 2000)).width
            }
        }
        var widths = measure(fs)
        let maxW = faceRect.width * 0.86
        let total = widths.reduce(0, +)
        if total > maxW { fs *= maxW / total; widths = measure(fs) }
        let totalW = widths.reduce(0, +)
        let baseY = cy + ph * 0.1
        var x = cx - totalW / 2
        let font = Font.system(size: fs, weight: .black, design: .serif)

        // Glow pass, extrusion, gold face, shimmer.
        var positions: [CGPoint] = []
        for wd in widths { positions.append(CGPoint(x: x + wd / 2, y: baseY)); x += wd }
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: ph * 0.035))
            l.blendMode = .plusLighter
            for (i, ch) in word.enumerated() {
                let bob = CGFloat(sin(time * 2.2 - Double(i) * 0.6)) * ph * 0.008
                let col = bulbColors[(i + Int(time * 2)) % 6]
                l.draw(l.resolve(Text(String(ch)).font(font).foregroundColor(col.opacity(0.85))), at: CGPoint(x: positions[i].x, y: positions[i].y + bob), anchor: .center)
            }
        }
        for (i, ch) in word.enumerated() {
            let bob = CGFloat(sin(time * 2.2 - Double(i) * 0.6)) * ph * 0.008
            let p = CGPoint(x: positions[i].x, y: positions[i].y + bob)
            for e in stride(from: 4, through: 1, by: -1) {
                ctx.draw(ctx.resolve(Text(String(ch)).font(font).foregroundColor(goldDark)), at: CGPoint(x: p.x + CGFloat(e) * ph * 0.0045, y: p.y + CGFloat(e) * ph * 0.0045), anchor: .center)
            }
            // A bright shimmer that sweeps left to right across the word.
            let sweep = BrightHalloween.fract(time * 0.28) * 1.6 - 0.3
            let near = max(0, 1 - abs(Double(i) / Double(word.count - 1) - sweep) * 4.5)
            let face = Color(red: 1.0, green: 0.82 + 0.15 * near, blue: 0.3 + 0.6 * near)
            ctx.draw(ctx.resolve(Text(String(ch)).font(font).foregroundColor(face)), at: p, anchor: .center)
        }

        // Divider with diamonds.
        let dy = cy + ph * 0.29
        var line = Path()
        line.move(to: CGPoint(x: cx - totalW * 0.42, y: dy)); line.addLine(to: CGPoint(x: cx - ph * 0.04, y: dy))
        line.move(to: CGPoint(x: cx + ph * 0.04, y: dy)); line.addLine(to: CGPoint(x: cx + totalW * 0.42, y: dy))
        ctx.stroke(line, with: .color(gold.opacity(0.85)), lineWidth: max(1, ph * 0.006))
        var dia = Path()
        for (dx, s) in [(CGFloat(0), ph * 0.03), (-totalW * 0.43, ph * 0.016), (totalW * 0.43, ph * 0.016)] {
            dia.move(to: CGPoint(x: cx + dx, y: dy - s)); dia.addLine(to: CGPoint(x: cx + dx + s, y: dy)); dia.addLine(to: CGPoint(x: cx + dx, y: dy + s)); dia.addLine(to: CGPoint(x: cx + dx - s, y: dy)); dia.closeSubpath()
        }
        ctx.fill(dia, with: .color(gold))
    }

    // MARK: Diya

    private func drawDiya(ctx: GraphicsContext, at c: CGPoint, r: CGFloat, phase: Double) {
        let flick = 0.82 + 0.12 * sin(time * 9 + phase * 1.9) + 0.06 * sin(time * 17 + phase)
        let sway = CGFloat(sin(time * 2.6 + phase)) * r * 0.1
        let g = r * 3.4
        let gc = CGPoint(x: c.x, y: c.y - r * 0.8)
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: r * 0.8))
            l.blendMode = .plusLighter
            l.fill(Path(ellipseIn: CGRect(x: gc.x - g, y: gc.y - g, width: g * 2, height: g * 2)),
                   with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.55, blue: 0.12).opacity(0.5 * flick), .clear]), center: gc, startRadius: 0, endRadius: g))
        }
        var bowl = Path()
        bowl.move(to: CGPoint(x: c.x - r, y: c.y))
        bowl.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x, y: c.y + r * 1.15))
        bowl.addQuadCurve(to: CGPoint(x: c.x + r * 1.35, y: c.y - r * 0.18), control: CGPoint(x: c.x + r * 1.2, y: c.y - r * 0.02))
        bowl.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x, y: c.y - r * 0.28))
        ctx.fill(bowl, with: .linearGradient(Gradient(colors: [DiwaliPalette.clay, DiwaliPalette.clayDark]), startPoint: CGPoint(x: c.x, y: c.y - r * 0.3), endPoint: CGPoint(x: c.x, y: c.y + r * 1.1)))
        let rim = CGRect(x: c.x - r, y: c.y - r * 0.2, width: r * 2, height: r * 0.4)
        ctx.fill(Path(ellipseIn: rim), with: .color(DiwaliPalette.saffron.opacity(0.6 * flick)))
        ctx.stroke(Path(ellipseIn: rim), with: .color(gold), lineWidth: max(1, r * 0.06))
        let fh = r * 1.6 * flick
        let base = CGPoint(x: c.x, y: c.y - r * 0.05)
        let tip = CGPoint(x: base.x + sway, y: base.y - fh)
        var flame = Path()
        flame.move(to: base)
        flame.addQuadCurve(to: tip, control: CGPoint(x: base.x - r * 0.65 + sway * 0.4, y: base.y - fh * 0.45))
        flame.addQuadCurve(to: base, control: CGPoint(x: base.x + r * 0.65 + sway * 0.4, y: base.y - fh * 0.45))
        ctx.drawLayer { l in
            l.blendMode = .plusLighter
            l.fill(flame, with: .linearGradient(Gradient(colors: [gold, Color(red: 1, green: 0.35, blue: 0.08).opacity(0.9)]), startPoint: base, endPoint: tip))
            l.fill(flame.applying(CGAffineTransform(translationX: -base.x, y: -base.y).scaledBy(x: 0.45, y: 0.6).translatedBy(x: base.x / 0.45 * 0 + 0, y: 0).concatenating(CGAffineTransform(translationX: base.x, y: base.y))),
                   with: .color(Color.white.opacity(0.9)))
        }
    }
}
