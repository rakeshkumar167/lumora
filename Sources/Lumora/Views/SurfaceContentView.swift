import LumoraKit
import SwiftUI

/// Renders one surface's media, perspective-warped onto its quad.
///
/// The media is laid out to fill the whole canvas box, then warped so that
/// box's corners land on the surface's quad — i.e. the media's full extent
/// maps into the surface. Uses SwiftUI's native `ProjectionTransform`, driven
/// by the pure `Homography` from the model core.
struct SurfaceContentView: View {
    let surface: Surface
    let canvasSize: CGSize
    let time: Double

    var body: some View {
        let quad = surface.quadPoints(in: canvasSize)
        let transform = Homography.transform(
            from: CGRect(origin: .zero, size: canvasSize),
            to: quad
        )

        mediaContent
            .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
            .clipped()
            .opacity(surface.opacity)
            .projectionEffect(ProjectionTransform(transform))
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var mediaContent: some View {
        switch surface.media {
        case .none:
            Color.clear
        case .color(let c):
            c.color
        case .effect(let kind, let c, let accent):
            EffectView(kind: kind, color: c, accent: accent, time: time, name: surface.name)
        case .image(let url):
            ImageContent(url: url)
        case .video(let url):
            VideoContent(url: url)
        }
    }
}

/// The built-in generative animations. Effects that support a second color use
/// `accent` (see `EffectKind.usesAccent`).
private struct EffectView: View {
    let kind: EffectKind
    let color: RGBAColor
    let accent: RGBAColor
    let time: Double
    var name: String = ""

    var body: some View {
        switch kind {
        case .grid:
            // A crisp alignment grid — ideal default for a fresh surface, since
            // each cell visibly distorts under the perspective warp.
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color))
                let spacing: CGFloat = 48
                let line = color.color.opacity(0.85)
                var x: CGFloat = 0
                while x <= size.width + 0.5 {
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(p, with: .color(line), lineWidth: 1.5)
                    x += spacing
                }
                var y: CGFloat = 0
                while y <= size.height + 0.5 {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(line), lineWidth: 1.5)
                    y += spacing
                }
                // Bright border + center cross to make corner/edge alignment easy.
                ctx.stroke(Path(CGRect(origin: .zero, size: size)), with: .color(color.color), lineWidth: 3)
                var cross = Path()
                cross.move(to: CGPoint(x: size.width / 2, y: 0))
                cross.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                cross.move(to: CGPoint(x: 0, y: size.height / 2))
                cross.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                ctx.stroke(cross, with: .color(color.color.opacity(0.5)), lineWidth: 2)
            }

        case .colorWash:
            let hue = (time * 0.08).truncatingRemainder(dividingBy: 1)
            Color(hue: hue, saturation: 0.7, brightness: 0.95)

        case .breathingGlow:
            let pulse = 0.5 + 0.5 * sin(time * 1.6)
            ZStack {
                accent.color
                color.color.opacity(0.30 + 0.70 * pulse)
            }

        case .gradientSweep:
            LinearGradient(
                colors: [color.color, accent.color, color.color],
                startPoint: unitPoint(time * 0.7),
                endPoint: unitPoint(time * 0.7 + .pi)
            )

        case .rainbowSweep:
            AngularGradient(
                gradient: Gradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red]),
                center: .center,
                angle: .degrees(time * 50)
            )

        case .strobe:
            (Int(time * 3) % 2 == 0 ? color.color : accent.color)

        case .plasma:
            ZStack {
                color.color
                RadialGradient(colors: [.white.opacity(0.9), .clear],
                               center: animatedCenter(time, 0.0),
                               startRadius: 0, endRadius: 280)
                    .blendMode(.screen)
                RadialGradient(colors: [accent.color.opacity(0.95), .clear],
                               center: animatedCenter(time, 2.0),
                               startRadius: 0, endRadius: 340)
                    .blendMode(.screen)
            }

        case .radialPulse:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color.opacity(0.20)))
                let spacing: CGFloat = 70
                let phase = CGFloat(time.truncatingRemainder(dividingBy: 1)) * spacing
                let maxR = hypot(size.width, size.height)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                var r = phase
                while r < maxR {
                    let rect = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
                    ctx.stroke(Path(ellipseIn: rect), with: .color(color.color), lineWidth: 12)
                    r += spacing
                }
            }

        case .checkerboard:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color))
                let cell: CGFloat = 44
                let offset = CGFloat((time * 30).truncatingRemainder(dividingBy: Double(cell * 2)))
                var row = 0
                var y: CGFloat = -cell * 2
                while y < size.height + cell * 2 {
                    var col = 0
                    var x: CGFloat = -cell * 2
                    while x < size.width + cell * 2 {
                        if (row + col) % 2 == 0 {
                            ctx.fill(Path(CGRect(x: x + offset, y: y, width: cell, height: cell)),
                                     with: .color(color.color))
                        }
                        x += cell; col += 1
                    }
                    y += cell; row += 1
                }
            }

        case .waves:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color.opacity(0.20)))
                let bands = 5
                for b in 0..<bands {
                    var path = Path()
                    let baseY = size.height * CGFloat(b) / CGFloat(bands - 1)
                    path.move(to: CGPoint(x: 0, y: baseY))
                    var x: CGFloat = 0
                    while x <= size.width {
                        let y = baseY + CGFloat(sin(Double(x) / 40 + time * 2 + Double(b)) * 16)
                        path.addLine(to: CGPoint(x: x, y: y))
                        x += 8
                    }
                    ctx.stroke(path, with: .color(color.color), lineWidth: 5)
                }
            }

        case .sparkle:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                for i in 0..<90 {
                    let x = hash01(i, 1) * size.width
                    let y = hash01(i, 2) * size.height
                    let twinkle = 0.5 + 0.5 * sin(time * 2 + Double(i) * 1.3)
                    let s = CGFloat(2 + 3 * twinkle)
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                             with: .color(color.color.opacity(twinkle)))
                }
            }

        case .barberStripes:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color))
                let stripe: CGFloat = 42
                let offset = CGFloat((time * 45).truncatingRemainder(dividingBy: Double(stripe * 2)))
                let diag = size.width + size.height
                var d = -size.height + offset - diag
                while d < size.width + diag {
                    var p = Path()
                    p.move(to: CGPoint(x: d, y: 0))
                    p.addLine(to: CGPoint(x: d + stripe, y: 0))
                    p.addLine(to: CGPoint(x: d + stripe + size.height, y: size.height))
                    p.addLine(to: CGPoint(x: d + size.height, y: size.height))
                    p.closeSubpath()
                    ctx.fill(p, with: .color(color.color))
                    d += stripe * 2
                }
            }

        case .colorBars:
            Canvas { ctx, size in
                let bars: [Color] = [.white, .yellow, .cyan, .green,
                                     Color(red: 1, green: 0, blue: 1), .red, .blue]
                let w = size.width / CGFloat(bars.count)
                for (i, c) in bars.enumerated() {
                    let rect = CGRect(x: CGFloat(i) * w, y: 0, width: w + 1, height: size.height)
                    ctx.fill(Path(rect), with: .color(c))
                }
            }

        case .equalizer:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                let count = 16
                let gap: CGFloat = 5
                let barWidth = (size.width - gap * CGFloat(count + 1)) / CGFloat(count)
                for i in 0..<count {
                    let level = 0.15 + 0.85 * pow(abs(sin(time * 2.5 + Double(i) * 0.7)), 2)
                    let h = size.height * CGFloat(level)
                    let x = gap + CGFloat(i) * (barWidth + gap)
                    let rect = CGRect(x: x, y: size.height - h, width: barWidth, height: h)
                    let shading = GraphicsContext.Shading.linearGradient(
                        Gradient(colors: [color.color, accent.color]),
                        startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                    )
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: shading)
                }
            }

        case .starfieldWarp:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxR = Double(hypot(size.width, size.height)) / 2
                for i in 0..<130 {
                    let angle = Double(hash01(i, 1)) * .pi * 2
                    let speed = 0.25 + Double(hash01(i, 2)) * 0.6
                    let f = fract(Double(hash01(i, 3)) + time * speed)
                    let r = f * maxR
                    let streak = 6 + f * 26
                    var p = Path()
                    p.move(to: point(center, angle, r))
                    p.addLine(to: point(center, angle, r + streak))
                    ctx.stroke(p, with: .color(.white.opacity(f)), lineWidth: CGFloat(1 + f * 1.6))
                }
            }

        case .neonGrid:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.03)))
                let horizon = size.height * 0.45
                let vanishing = CGPoint(x: size.width / 2, y: horizon)
                let cols = 12
                for i in 0...cols {
                    let x = size.width * CGFloat(i) / CGFloat(cols)
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: size.height))
                    p.addLine(to: vanishing)
                    ctx.stroke(p, with: .color(color.color.opacity(0.55)), lineWidth: 1)
                }
                let rows = 12
                let scroll = fract(time * 0.6)
                for i in 0..<rows {
                    let f = (Double(i) + scroll) / Double(rows)
                    let y = horizon + (size.height - horizon) * CGFloat(f * f)
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(color.color.opacity(0.55)), lineWidth: 1)
                }
                var glow = Path()
                glow.move(to: CGPoint(x: 0, y: horizon))
                glow.addLine(to: CGPoint(x: size.width, y: horizon))
                ctx.stroke(glow, with: .color(accent.color), lineWidth: 2)
            }

        case .vortex:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color.opacity(0.12)))
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxR = Double(hypot(size.width, size.height)) / 2
                let arms = 5
                for a in 0..<arms {
                    var p = Path()
                    let base = Double(a) / Double(arms) * 2 * .pi + time * 0.8
                    var r = 0.0
                    var first = true
                    while r < maxR {
                        let pt = point(center, base + r * 0.02, r)
                        if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                        r += 6
                    }
                    let armColor = a % 2 == 0 ? color.color : accent.color
                    ctx.stroke(p, with: .color(armColor), lineWidth: 6)
                }
            }

        case .aurora:
            Canvas { ctx, size in
                let w = Double(size.width)
                let h = Double(size.height)

                // Night sky with a faint gradient.
                ctx.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.03, green: 0.04, blue: 0.11),
                            Color(red: 0.01, green: 0.02, blue: 0.05),
                        ]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )

                // Stars.
                for i in 0..<70 {
                    let sx = Double(hash01(i, 11)) * w
                    let sy = Double(hash01(i, 12)) * h * 0.92
                    let tw = 0.4 + 0.6 * abs(sin(time * 1.3 + Double(i)))
                    let s = 1.0 + Double(hash01(i, 13)) * 1.4
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: sx, y: sy, width: s, height: s)),
                        with: .color(.white.opacity(0.12 + 0.4 * tw))
                    )
                }

                // Curtains, drawn back (high, dim, purple) to front (low, bright, green).
                // Each: base height fraction, wave amplitude, curtain drop, drift
                // speed, phase, tint.
                let curtains: [(base: Double, amp: Double, drop: Double, speed: Double, phase: Double, tint: Color)] = [
                    (0.30, 24, 0.44, 0.22, 0.0, Color(red: 0.55, green: 0.25, blue: 0.85)),
                    (0.27, 30, 0.52, 0.30, 2.1, Color(red: 0.10, green: 0.80, blue: 0.80)),
                    (0.24, 36, 0.62, 0.40, 4.3, Color(red: 0.18, green: 0.98, blue: 0.50)),
                ]

                for cur in curtains {
                    let baseY = h * cur.base
                    let ch = h * cur.drop

                    // Wavy top rim of the curtain, and a parallel bottom edge.
                    func rim(_ x: Double) -> Double {
                        baseY
                            + sin(x * 0.006 + time * cur.speed + cur.phase) * cur.amp
                            + sin(x * 0.018 + time * cur.speed * 1.7 + cur.phase) * cur.amp * 0.35
                    }

                    var band = Path()
                    var bottom: [CGPoint] = []
                    var x = 0.0
                    band.move(to: CGPoint(x: 0, y: rim(0)))
                    while x <= w {
                        band.addLine(to: CGPoint(x: x, y: rim(x)))
                        bottom.append(CGPoint(x: x, y: rim(x) + ch))
                        x += 12
                    }
                    for pt in bottom.reversed() { band.addLine(to: pt) }
                    band.closeSubpath()

                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 8))
                        layer.clip(to: band)

                        // Bright top rim fading downward.
                        let fill = GraphicsContext.Shading.linearGradient(
                            Gradient(stops: [
                                .init(color: cur.tint.opacity(0.0), location: 0.0),
                                .init(color: cur.tint.opacity(0.9), location: 0.14),
                                .init(color: cur.tint.opacity(0.35), location: 0.55),
                                .init(color: cur.tint.opacity(0.0), location: 1.0),
                            ]),
                            startPoint: CGPoint(x: 0, y: baseY - cur.amp),
                            endPoint: CGPoint(x: 0, y: baseY + ch)
                        )
                        layer.fill(band, with: fill)

                        // Vertical ray striations that shimmer sideways.
                        var rx = 0.0
                        while rx <= w {
                            let bright = pow(abs(sin(rx * 0.028 + time * 1.5 + cur.phase)), 3)
                            if bright > 0.05 {
                                var ray = Path()
                                ray.move(to: CGPoint(x: rx, y: baseY - cur.amp - 6))
                                ray.addLine(to: CGPoint(x: rx, y: baseY + ch))
                                layer.stroke(ray, with: .color(cur.tint.opacity(0.5 * bright)), lineWidth: 2)
                            }
                            rx += 9
                        }
                    }
                }
            }

        case .fireflies:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.04)))
                for i in 0..<40 {
                    let x = fract(Double(hash01(i, 1)) + 0.04 * sin(time * 0.5 + Double(i))) * Double(size.width)
                    let y = fract(Double(hash01(i, 2)) + 0.04 * cos(time * 0.4 + Double(i) * 1.7)) * Double(size.height)
                    let glow = max(0.0, 0.35 + 0.65 * sin(time * 1.5 + Double(i) * 2.0))
                    let radius = 7.0
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 5))
                        layer.fill(Path(ellipseIn: rect), with: .color(color.color.opacity(glow)))
                    }
                }
            }

        case .snow:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.03)))
                for i in 0..<130 {
                    let speed = 0.15 + Double(hash01(i, 3)) * 0.45
                    let y = fract(Double(hash01(i, 2)) + time * speed) * Double(size.height)
                    let sway = 0.03 * sin(time + Double(i))
                    let x = (Double(hash01(i, 1)) + sway) * Double(size.width)
                    let s = 2.0 + Double(hash01(i, 4)) * 3.5
                    let rect = CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
                    ctx.fill(Path(ellipseIn: rect), with: .color(color.color.opacity(0.9)))
                }
            }

        case .lava:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.03)))
                ctx.addFilter(.alphaThreshold(min: 0.5, color: color.color))
                ctx.addFilter(.blur(radius: 22))
                ctx.drawLayer { layer in
                    for i in 0..<6 {
                        let x = (0.5 + 0.42 * sin(time * 0.5 + Double(i) * 1.1)) * Double(size.width)
                        let y = (0.5 + 0.42 * cos(time * 0.4 + Double(i) * 1.7)) * Double(size.height)
                        let r = 55.0 + 22.0 * sin(time + Double(i))
                        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                        layer.fill(Path(ellipseIn: rect), with: .color(.white))
                    }
                }
            }
        case .halftoneDots:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color))
                let spacing: CGFloat = 36
                var y: CGFloat = spacing / 2
                while y < size.height {
                    var x: CGFloat = spacing / 2
                    while x < size.width {
                        let wave = 0.5 + 0.5 * sin(Double(x + y) * 0.05 - time * 3)
                        let r = CGFloat(2 + 14 * wave)
                        let rect = CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)
                        ctx.fill(Path(ellipseIn: rect), with: .color(color.color))
                        x += spacing
                    }
                    y += spacing
                }
            }

        case .moire:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.03)))
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let spacing: CGFloat = 14
                var p1 = Path()
                var x: CGFloat = 0
                while x <= size.width {
                    p1.move(to: CGPoint(x: x, y: 0))
                    p1.addLine(to: CGPoint(x: x, y: size.height))
                    x += spacing
                }
                ctx.stroke(p1, with: .color(color.color.opacity(0.6)), lineWidth: 1)
                ctx.drawLayer { layer in
                    layer.translateBy(x: center.x, y: center.y)
                    layer.rotate(by: .radians(time * 0.15))
                    layer.translateBy(x: -center.x, y: -center.y)
                    var p2 = Path()
                    var xx: CGFloat = -size.width
                    while xx <= size.width * 2 {
                        p2.move(to: CGPoint(x: xx, y: -size.height))
                        p2.addLine(to: CGPoint(x: xx, y: size.height * 2))
                        xx += spacing
                    }
                    layer.stroke(p2, with: .color(color.color.opacity(0.6)), lineWidth: 1)
                }
            }
        case .truchet:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color))
                let cell: CGFloat = 40
                let cols = Int(size.width / cell) + 1
                let rows = Int(size.height / cell) + 1
                let epoch = Int(time / 2.5)
                for row in 0..<rows {
                    for col in 0..<cols {
                        let idx = row * 1000 + col
                        let flip = hash01(idx, epoch) > 0.5
                        let x = CGFloat(col) * cell
                        let y = CGFloat(row) * cell
                        var path = Path()
                        if flip {
                            path.addArc(center: CGPoint(x: x, y: y), radius: cell / 2,
                                        startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
                            path.addArc(center: CGPoint(x: x + cell, y: y + cell), radius: cell / 2,
                                        startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
                        } else {
                            path.addArc(center: CGPoint(x: x + cell, y: y), radius: cell / 2,
                                        startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
                            path.addArc(center: CGPoint(x: x, y: y + cell), radius: cell / 2,
                                        startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
                        }
                        ctx.stroke(path, with: .color(color.color), lineWidth: 3)
                    }
                }
            }

        case .concentricPolygons:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.03)))
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let rings = 6
                for i in 0..<rings {
                    let radius = 30.0 + Double(i) * 34.0
                    let speed = 0.3 + Double(i) * 0.15
                    let rotation = time * speed * (i % 2 == 0 ? 1 : -1)
                    let path = polygonPath(center: center, radius: CGFloat(radius), sides: 6, rotation: rotation)
                    let c = i % 2 == 0 ? color.color : accent.color
                    ctx.stroke(path, with: .color(c), lineWidth: 3)
                }
            }
        case .spirograph:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.03)))
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let R = 140.0, r = 60.0, d = 100.0
                var path = Path()
                var first = true
                let rotation = time * 0.1
                var t = 0.0
                while t <= .pi * 2 * 6 {
                    let px = (R - r) * cos(t) + d * cos((R - r) / r * t)
                    let py = (R - r) * sin(t) - d * sin((R - r) / r * t)
                    let angle = atan2(py, px) + rotation
                    let radius = hypot(px, py)
                    let pt = point(center, angle, radius)
                    if first { path.move(to: pt); first = false } else { path.addLine(to: pt) }
                    t += 0.1
                }
                ctx.stroke(path, with: .color(color.color), lineWidth: 2)
            }

        case .fire:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.02)))
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 12))
                    for i in 0..<28 {
                        let baseX = Double(hash01(i, 1)) * Double(size.width)
                        let speed = 0.6 + Double(hash01(i, 2)) * 0.8
                        let riseT = fract(Double(hash01(i, 3)) + time * speed)
                        let y = Double(size.height) * (1 - riseT)
                        let sway = sin(time * 2 + Double(i)) * 16
                        let x = baseX + sway
                        let r = 14.0 + 24.0 * (1 - riseT)
                        let rect = CGRect(x: CGFloat(x - r / 2), y: CGFloat(y - r / 2), width: CGFloat(r), height: CGFloat(r))
                        let tint = riseT < 0.55 ? color.color : accent.color
                        layer.fill(Path(ellipseIn: rect), with: .color(tint.opacity(1 - riseT * 0.7)))
                    }
                }
            }
        case .rain:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.03)))
                for i in 0..<120 {
                    let speed = 3.0 + Double(hash01(i, 1)) * 4.0
                    let x = Double(hash01(i, 2)) * Double(size.width)
                    let len = 14.0 + Double(hash01(i, 3)) * 20.0
                    let y = fract(Double(hash01(i, 4)) + time * speed * 0.15) * Double(size.height + CGFloat(len)) - len
                    var p = Path()
                    p.move(to: CGPoint(x: CGFloat(x), y: CGFloat(y)))
                    p.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(y + len)))
                    ctx.stroke(p, with: .color(color.color.opacity(0.7)), lineWidth: 1.5)
                }
            }

        case .lightning:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.02)))
                let period = 3.0
                let cycle = fract(time / period)
                if cycle < 0.15 {
                    let flash = 1 - cycle / 0.15
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color.opacity(0.35 * flash)))
                    let strikeIndex = Int(time / period)
                    var x = Double(hash01(strikeIndex, 1)) * Double(size.width)
                    var y = 0.0
                    var path = Path()
                    path.move(to: CGPoint(x: CGFloat(x), y: CGFloat(y)))
                    var seg = 0
                    while y < Double(size.height) {
                        let dx = (Double(hash01(strikeIndex, seg + 10)) - 0.5) * 60
                        x += dx
                        y += Double(size.height) / 12
                        path.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(y)))
                        seg += 1
                    }
                    ctx.stroke(path, with: .color(color.color.opacity(flash)), lineWidth: 3)
                }
            }
        case .bubbles:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.05)))
                for i in 0..<36 {
                    let speed = 0.15 + Double(hash01(i, 1)) * 0.3
                    let riseT = fract(Double(hash01(i, 2)) + time * speed)
                    let y = Double(size.height) * (1 - riseT)
                    let baseX = Double(hash01(i, 3)) * Double(size.width)
                    let wobble = sin(time * 1.3 + Double(i) * 2.1) * 14
                    let x = baseX + wobble
                    let r = 6.0 + Double(hash01(i, 4)) * 16.0
                    let rect = CGRect(x: CGFloat(x - r), y: CGFloat(y - r), width: CGFloat(r * 2), height: CGFloat(r * 2))
                    let tint = i % 2 == 0 ? color.color : accent.color
                    ctx.stroke(Path(ellipseIn: rect), with: .color(tint.opacity(0.6)), lineWidth: 2)
                }
            }

        case .fallingLeaves:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.05)))
                for i in 0..<30 {
                    let speed = 0.2 + Double(hash01(i, 1)) * 0.3
                    let fallT = fract(Double(hash01(i, 2)) + time * speed)
                    let y = Double(size.height) * fallT - 20
                    let baseX = Double(hash01(i, 3)) * Double(size.width)
                    let sway = sin(time * 1.1 + Double(i) * 1.7) * 30
                    let x = baseX + sway
                    let rot = time * (0.5 + Double(hash01(i, 4))) + Double(i)
                    let s: CGFloat = 8 + CGFloat(hash01(i, 5)) * 6
                    let tint = i % 2 == 0 ? color.color : accent.color
                    ctx.drawLayer { layer in
                        layer.translateBy(x: CGFloat(x), y: CGFloat(y))
                        layer.rotate(by: .radians(rot))
                        let leaf = Path(ellipseIn: CGRect(x: -s, y: -s / 2, width: s * 2, height: s))
                        layer.fill(leaf, with: .color(tint.opacity(0.85)))
                    }
                }
            }
        case .tvStatic:
            Canvas { ctx, size in
                let cell: CGFloat = 24
                let cols = Int(size.width / cell) + 1
                let rows = Int(size.height / cell) + 1
                let frame = Int(time * 20)
                for row in 0..<rows {
                    for col in 0..<cols {
                        let idx = row * 1000 + col
                        let v = hash01(idx, frame)
                        let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                        ctx.fill(Path(rect), with: .color(Color(white: Double(v))))
                    }
                }
            }

        case .crtScanlines:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color.color))
                var y: CGFloat = 0
                while y < size.height {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(Color.black.opacity(0.25)))
                    y += 3
                }
                let barY = CGFloat(fract(time * 0.2)) * size.height
                let barRect = CGRect(x: 0, y: barY - 30, width: size.width, height: 60)
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 20))
                    layer.fill(Path(barRect), with: .color(.white.opacity(0.25)))
                }
            }
        case .matrixRain:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.02)))
                let glyphs = Array("01アイウエオカキクケコ")
                let colWidth: CGFloat = 24
                let cols = Int(size.width / colWidth)
                let rowHeight: CGFloat = 20
                for c in 0..<cols {
                    let speed = 2.0 + Double(hash01(c, 1)) * 3.0
                    let colLen = 6 + Int(hash01(c, 2) * 8)
                    let headY = fract(Double(hash01(c, 3)) + time * speed * 0.1)
                        * Double(size.height + CGFloat(colLen) * rowHeight)
                    for k in 0..<colLen {
                        let y = headY - Double(k) * Double(rowHeight)
                        if y < 0 || y > Double(size.height) { continue }
                        let epoch = Int(time * 4)
                        let glyphIdx = Int(Double(hash01(c * 31 + k, epoch)) * Double(glyphs.count))
                        let glyph = String(glyphs[glyphIdx % glyphs.count])
                        let bright = k == 0
                        let tint = bright ? accent.color : color.color.opacity(max(0.15, 1 - Double(k) / Double(colLen)))
                        let text = Text(glyph).font(.system(size: 15, design: .monospaced)).foregroundColor(tint)
                        ctx.draw(text, at: CGPoint(x: CGFloat(c) * colWidth + colWidth / 2, y: CGFloat(y)))
                    }
                }
            }

        case .glitch:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black))
                let sliceH: CGFloat = 16
                var y: CGFloat = 0
                var i = 0
                let epoch = Int(time * 8)
                while y < size.height {
                    let jitter = (hash01(i, epoch) - 0.5) * 60
                    let rect = CGRect(x: jitter, y: y, width: size.width, height: sliceH)
                    if hash01(i, epoch + 500) > 0.8 {
                        ctx.fill(Path(rect), with: .color(color.color.opacity(0.5)))
                        ctx.fill(Path(rect.offsetBy(dx: 4, dy: 0)), with: .color(.red.opacity(0.35)))
                        ctx.fill(Path(rect.offsetBy(dx: -4, dy: 0)), with: .color(.cyan.opacity(0.35)))
                    } else {
                        ctx.fill(Path(rect), with: .color(color.color.opacity(0.15)))
                    }
                    y += sliceH; i += 1
                }
            }
        case .pixelDissolve:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black))
                let cell: CGFloat = 30
                let cols = Int(size.width / cell) + 1
                let rows = Int(size.height / cell) + 1
                for row in 0..<rows {
                    for col in 0..<cols {
                        let idx = row * 1000 + col
                        let phase = Double(hash01(idx, 7))
                        let t = 0.5 + 0.5 * sin(time * 1.2 + phase * 6.28)
                        let mix = t > 0.5 ? accent.color : color.color
                        let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell - 2, height: cell - 2)
                        ctx.fill(Path(rect), with: .color(mix.opacity(0.6 + 0.4 * t)))
                    }
                }
            }

        case .tunnel:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black))
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let maxR = Double(hypot(size.width, size.height)) / 2
                let rings = 14
                let speed = 0.5
                for i in 0..<rings {
                    let f = fract(Double(i) / Double(rings) + time * speed)
                    let r = f * maxR
                    let rect = CGRect(x: center.x - CGFloat(r), y: center.y - CGFloat(r), width: CGFloat(r * 2), height: CGFloat(r * 2))
                    let c = i % 2 == 0 ? color.color : accent.color
                    ctx.stroke(Path(ellipseIn: rect), with: .color(c.opacity(0.2 + 0.8 * f)), lineWidth: CGFloat(4 + f * 10))
                }
            }
        case .pendulumWave:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.03)))
                let count = 20
                let originY = size.height * 0.15
                let length = size.height * 0.6
                for i in 0..<count {
                    let x = size.width * (CGFloat(i) + 0.5) / CGFloat(count)
                    let period = 1.4 + Double(i) * 0.05
                    let angle = sin(time * 2 * .pi / period) * 0.5
                    let dotX = x + CGFloat(sin(angle)) * 50
                    let dotY = originY + length * CGFloat(cos(angle))
                    var line = Path()
                    line.move(to: CGPoint(x: x, y: originY))
                    line.addLine(to: CGPoint(x: dotX, y: dotY))
                    ctx.stroke(line, with: .color(color.color.opacity(0.3)), lineWidth: 1)
                    let r: CGFloat = 8
                    ctx.fill(Path(ellipseIn: CGRect(x: dotX - r, y: dotY - r, width: r * 2, height: r * 2)),
                             with: .color(color.color))
                }
            }

        case .dvdBounce:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black))
                let w: CGFloat = 90, h: CGFloat = 60
                let rangeX = Double(size.width - w)
                let rangeY = Double(size.height - h)
                let rawX = time * 90.0
                let rawY = time * 70.0
                let cycleX = rawX.truncatingRemainder(dividingBy: rangeX * 2)
                let cycleY = rawY.truncatingRemainder(dividingBy: rangeY * 2)
                let posX = cycleX <= rangeX ? cycleX : rangeX * 2 - cycleX
                let posY = cycleY <= rangeY ? cycleY : rangeY * 2 - cycleY
                let bounceCountX = Int(rawX / rangeX)
                let bounceCountY = Int(rawY / rangeY)
                let tint = (bounceCountX + bounceCountY) % 2 == 0 ? color.color : accent.color
                let rect = CGRect(x: CGFloat(posX), y: CGFloat(posY), width: w, height: h)
                ctx.fill(Path(rect), with: .color(tint))
            }
        case .kaleidoscope:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.black))
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let segments = 8
                let maxR = Double(min(size.width, size.height)) / 2
                var basePattern = Path()
                for i in 0..<5 {
                    let angle = 0.3 + Double(i) * 0.35 + sin(time * 0.6 + Double(i)) * 0.15
                    let r = maxR * (0.2 + 0.15 * Double(i)) * (0.7 + 0.3 * sin(time + Double(i) * 1.3))
                    let pt = point(.zero, angle, r)
                    let s: CGFloat = 14
                    basePattern.addEllipse(in: CGRect(x: pt.x - s, y: pt.y - s, width: s * 2, height: s * 2))
                }
                for seg in 0..<segments {
                    let baseAngle = Double(seg) / Double(segments) * 2 * .pi + time * 0.1
                    ctx.drawLayer { layer in
                        layer.translateBy(x: center.x, y: center.y)
                        layer.rotate(by: .radians(baseAngle))
                        if seg % 2 == 1 {
                            layer.scaleBy(x: -1, y: 1)
                        }
                        let tint = seg % 2 == 0 ? color.color : accent.color
                        layer.fill(basePattern, with: .color(tint.opacity(0.85)))
                    }
                }
            }

        case .marqueeText:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(accent.color))
                let label = (name.isEmpty ? "LUMORA" : name.uppercased()) + "     "
                let text = Text(label)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundColor(color.color)
                let resolved = ctx.resolve(text)
                let textWidth = max(resolved.measure(in: CGSize(width: 10000, height: 100)).width, 1)
                let scrollSpeed: CGFloat = 120
                let offset = CGFloat(time) * scrollSpeed
                var x = -offset.truncatingRemainder(dividingBy: textWidth)
                if x > 0 { x -= textWidth }
                let y = size.height / 2
                while x < size.width {
                    ctx.draw(text, at: CGPoint(x: x + textWidth / 2, y: y))
                    x += textWidth
                }
            }
        }
    }

    private func polygonPath(center: CGPoint, radius: CGFloat, sides: Int, rotation: Double) -> Path {
        var path = Path()
        for i in 0...sides {
            let angle = rotation + Double(i) / Double(sides) * 2 * .pi
            let pt = point(center, angle, Double(radius))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        return path
    }

    private func unitPoint(_ radians: Double) -> UnitPoint {
        UnitPoint(x: 0.5 + 0.5 * cos(radians), y: 0.5 + 0.5 * sin(radians))
    }

    private func point(_ c: CGPoint, _ angle: Double, _ radius: Double) -> CGPoint {
        CGPoint(x: c.x + CGFloat(cos(angle) * radius), y: c.y + CGFloat(sin(angle) * radius))
    }

    private func fract(_ v: Double) -> Double { v - floor(v) }

    private func animatedCenter(_ t: Double, _ phase: Double) -> UnitPoint {
        UnitPoint(x: 0.5 + 0.3 * cos(t * 0.8 + phase), y: 0.5 + 0.3 * sin(t * 0.6 + phase))
    }

    private func hash01(_ i: Int, _ salt: Int) -> CGFloat {
        let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return CGFloat(v - floor(v))
    }
}

/// A still image loaded from disk, scaled to fill the surface.
private struct ImageContent: View {
    let url: URL

    var body: some View {
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color(white: 0.2)
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.white)
            }
        }
    }
}
