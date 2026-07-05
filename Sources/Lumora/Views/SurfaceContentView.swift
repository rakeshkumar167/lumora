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
            EffectView(kind: kind, color: c, accent: accent, time: time)
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

    var body: some View {
        switch kind {
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
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.02)))
                let hues: [Color] = [.green, .teal, .blue, .purple]
                for b in 0..<hues.count {
                    var path = Path()
                    let baseX = size.width * (0.25 + 0.18 * CGFloat(b))
                    let amp = 45.0
                    path.move(to: CGPoint(x: baseX, y: 0))
                    var y = 0.0
                    while y <= Double(size.height) {
                        let x = Double(baseX) + sin(y * 0.011 + time * 0.7 + Double(b) * 1.4) * amp
                        path.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(y)))
                        y += 10
                    }
                    ctx.drawLayer { layer in
                        layer.addFilter(.blur(radius: 34))
                        layer.stroke(path, with: .color(hues[b].opacity(0.5)), lineWidth: 70)
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
        }
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
