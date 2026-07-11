// Run: swift scripts/verify_christmas.swift
import AppKit
import SwiftUI

// Standalone faithful copy for visual sanity (mirrors ChristmasLights + renderer).
let palette: [Color] = [
    Color(red: 0.85, green: 0.11, blue: 0.14), Color(red: 0.11, green: 0.58, blue: 0.24),
    Color(red: 0.95, green: 0.76, blue: 0.22), Color(red: 0.16, green: 0.42, blue: 0.90),
    Color(red: 1.0, green: 0.93, blue: 0.80),
]
func strand(_ size: CGSize) -> [CGPoint] {
    let bs: CGFloat = 55
    let bc = max(3, Int((size.width/bs).rounded()))
    let y0 = 0.42*size.height, sag = 0.13*size.height, inset = size.width*0.06
    let left = inset, right = size.width-inset
    return (0..<bc).map { i -> CGPoint in
        let t = CGFloat(i)/CGFloat(bc-1)
        return CGPoint(x: left+(right-left)*t, y: y0+sag*4*t*(1-t))
    }
}

func drawBulb(_ ctx: GraphicsContext, at p: CGPoint, color: Color, brightness: Double, radius r: CGFloat, round: Bool) {
    let capW = r*0.75, capH = r*0.55
    ctx.fill(Path(roundedRect: CGRect(x: p.x-capW/2, y: p.y-capH*0.35, width: capW, height: capH),
                  cornerSize: CGSize(width: capH*0.3, height: capH*0.3)), with: .color(Color(white: 0.32)))
    let halfH: CGFloat = round ? r : r*1.18, halfW: CGFloat = round ? r : r*0.82
    let cy = p.y + capH*0.5 + halfH, center = CGPoint(x: p.x, y: cy)
    let bodyRect = CGRect(x: center.x-halfW, y: center.y-halfH, width: 2*halfW, height: 2*halfH)
    ctx.drawLayer { l in
        l.addFilter(.blur(radius: r*1.3)); l.blendMode = .plusLighter
        let hr = halfH*(1.3+0.8*brightness)
        l.fill(Path(ellipseIn: CGRect(x: center.x-hr, y: center.y-hr, width: 2*hr, height: 2*hr)), with: .color(color.opacity(0.55*brightness)))
    }
    let body = Path(ellipseIn: bodyRect)
    ctx.fill(body, with: .color(color.opacity(0.55+0.45*brightness)))
    ctx.stroke(body, with: .color(.black.opacity(0.18)), lineWidth: max(0.6, r*0.06))
    let hlR = halfW*0.34, hl = CGPoint(x: center.x-halfW*0.32, y: center.y-halfH*0.4)
    ctx.fill(Path(ellipseIn: CGRect(x: hl.x-hlR, y: hl.y-hlR, width: 2*hlR, height: 2*hlR)),
             with: .color(.white.opacity(0.55*max(0.4,brightness))))
}

struct StringView: View {
    let time: Double; let mode: Int  // 0 chase, 1 multi, 2 twinkle, 3 warm
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red:0.03,green:0.04,blue:0.07)))
            let round = (mode == 3)
            let b = strand(size)
            var wire = Path(); wire.addLines(b)
            ctx.stroke(wire, with: .color(Color(white:0.35).opacity(0.6)), lineWidth: max(1.2, size.width*0.0018))
            let spacing = hypot(b[1].x-b[0].x, b[1].y-b[0].y)
            let r = min(spacing*(round ? 0.34 : 0.30), size.height*0.12)
            for (i, pt) in b.enumerated() {
                let (col, br) = state(i, b.count)
                drawBulb(ctx, at: pt, color: col, brightness: br, radius: r, round: round)
            }
        }
    }
    func state(_ i: Int, _ n: Int) -> (Color, Double) {
        switch mode {
        case 0:
            let pos = Double(i)/Double(max(n-1,1)), head = (time*0.5).truncatingRemainder(dividingBy: 1)
            let d = abs(pos-head), w = min(d, 1-d); return (palette[(i+Int(time))%5], 0.15+0.85*max(0,1-w*6))
        case 1:
            return (palette[i%5], 0.75+0.25*sin(time*1.5+Double(i)*0.9))
        case 2:
            let seed = Double((i*2654435761)%1000)/1000.0
            return (palette[i%5], 0.1+0.9*pow(0.5+0.5*sin(time*1.8+seed*6.283),2))
        default:
            return (Color(red:1.0,green:0.82,blue:0.52), 0.82+0.18*sin(time*1.1+Double(i)*1.3))
        }
    }
}

func render<V: View>(_ v: V, _ size: CGSize, _ path: String) {
    MainActor.assumeIsolated {
        let r = ImageRenderer(content: v.frame(width: size.width, height: size.height)); r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)); print("wrote \(path)") }
    }
}
let size = CGSize(width: 560, height: 220)
render(StringView(time: 1.3, mode: 0), size, "/tmp/xmas_chase.png")
render(StringView(time: 0.6, mode: 1), size, "/tmp/xmas_multi.png")
render(StringView(time: 0.6, mode: 2), size, "/tmp/xmas_twinkle.png")
render(StringView(time: 0.6, mode: 3), size, "/tmp/xmas_warm.png")
