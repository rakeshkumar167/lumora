// Run: swift scripts/verify_bubbles.swift
// OLD (metallic, additive saturated orbs) vs NEW (transparent soap bubbles with
// iridescent rim). Mirrors drawBubbles in SurfaceContentView.
import AppKit
import SwiftUI

func hash01(_ a: Int, _ b: Int) -> Double {
    var h = UInt64(bitPattern: Int64(a &* 374761393 &+ b &* 668265263))
    h = (h ^ (h >> 13)) &* 1274126177
    return Double(h % 10000) / 10000.0
}
func fract(_ x: Double) -> Double { x - floor(x) }

struct Bubbles: View {
    let isNew: Bool
    let time: Double = 0.7
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: isNew ? 0.05 : 0.04)))
            if !isNew {
                ctx.drawLayer { layer in
                    layer.blendMode = .plusLighter
                    for i in 0..<36 {
                        let speed = 0.15 + hash01(i, 1) * 0.3
                        let riseT = fract(hash01(i, 2) + time * speed)
                        let y = Double(size.height) * (1 - riseT)
                        let x = hash01(i, 3) * Double(size.width) + sin(time * 1.3 + Double(i) * 2.1) * 14
                        let r = 6.0 + hash01(i, 4) * 16.0
                        let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                        let hue = fract(hash01(i, 5) + time * 0.05)
                        let body = Color(hue: hue, saturation: 0.85, brightness: 1.0)
                        layer.fill(Path(ellipseIn: rect), with: .radialGradient(
                            Gradient(colors: [.white.opacity(0.55), body.opacity(0.7), body.opacity(0.15)]),
                            center: CGPoint(x: x - r * 0.3, y: y - r * 0.3), startRadius: 0, endRadius: r * 1.2))
                        layer.stroke(Path(ellipseIn: rect), with: .color(body.opacity(0.9)), lineWidth: 1.5)
                        let gr = r * 0.28
                        layer.fill(Path(ellipseIn: CGRect(x: x - r * 0.35 - gr, y: y - r * 0.35 - gr, width: gr * 2, height: gr * 2)),
                                   with: .color(.white.opacity(0.7)))
                    }
                }
                return
            }
            for i in 0..<34 {
                let speed = 0.12 + hash01(i, 1) * 0.26
                let riseT = fract(hash01(i, 2) + time * speed)
                let y = Double(size.height) * (1 - riseT)
                let x = hash01(i, 3) * Double(size.width) + sin(time * 1.1 + Double(i) * 2.1) * 12
                let r = 7.0 + hash01(i, 4) * 20.0
                let cx = CGFloat(x), cy = CGFloat(y)
                let rect = CGRect(x: cx - CGFloat(r), y: cy - CGFloat(r), width: CGFloat(r * 2), height: CGFloat(r * 2))
                let hueShift = hash01(i, 5)
                let tint = Color(hue: fract(0.55 + hueShift * 0.25), saturation: 0.22, brightness: 1.0)
                ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(stops: [
                        .init(color: .white.opacity(0.015), location: 0.0),
                        .init(color: tint.opacity(0.05), location: 0.65),
                        .init(color: tint.opacity(0.16), location: 0.93),
                        .init(color: .white.opacity(0.06), location: 1.0),
                    ]),
                    center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: CGFloat(r)))
                let irid = Gradient(colors: [
                    Color(hue: 0.95, saturation: 0.32, brightness: 1), Color(hue: 0.55, saturation: 0.32, brightness: 1),
                    Color(hue: 0.33, saturation: 0.30, brightness: 1), Color(hue: 0.75, saturation: 0.32, brightness: 1),
                    Color(hue: 0.08, saturation: 0.28, brightness: 1), Color(hue: 0.95, saturation: 0.32, brightness: 1),
                ])
                ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 1, dy: 1)),
                           with: .conicGradient(irid, center: CGPoint(x: cx, y: cy), angle: .radians(time * 0.5 + hueShift * 6.28)),
                           lineWidth: max(1, CGFloat(r * 0.11)))
                ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.16)), lineWidth: 1)
                ctx.drawLayer { layer in
                    layer.blendMode = .plusLighter
                    let gx = cx - CGFloat(r * 0.38), gy = cy - CGFloat(r * 0.38), gr = CGFloat(r * 0.5)
                    layer.fill(Path(ellipseIn: CGRect(x: gx - gr, y: gy - gr, width: gr * 2, height: gr * 2)),
                               with: .radialGradient(Gradient(colors: [.white.opacity(0.7), .white.opacity(0)]),
                                                     center: CGPoint(x: gx, y: gy), startRadius: 0, endRadius: gr))
                    let sr = CGFloat(r * 0.1)
                    layer.fill(Path(ellipseIn: CGRect(x: gx - sr, y: gy - sr, width: sr * 2, height: sr * 2)), with: .color(.white.opacity(0.85)))
                    let lx = cx + CGFloat(r * 0.4), ly = cy + CGFloat(r * 0.45), lr = CGFloat(r * 0.14)
                    layer.fill(Path(ellipseIn: CGRect(x: lx - lr, y: ly - lr, width: lr * 2, height: lr * 2)), with: .color(.white.opacity(0.18)))
                }
            }
        }
    }
}

struct Board: View {
    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .topLeading) { Bubbles(isNew: false); Text(" OLD").foregroundStyle(.white).font(.caption) }.frame(width: 420, height: 460)
            ZStack(alignment: .topLeading) { Bubbles(isNew: true); Text(" NEW").foregroundStyle(.white).font(.caption) }.frame(width: 420, height: 460)
        }.background(Color.black)
    }
}

MainActor.assumeIsolated {
    let r = ImageRenderer(content: Board()); r.scale = 2
    if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "/tmp/bubbles.png")); print("wrote /tmp/bubbles.png")
    }
}
