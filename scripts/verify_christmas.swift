// Run: swift scripts/verify_christmas.swift
import AppKit
import SwiftUI

// Standalone faithful copy for visual sanity (mirrors ChristmasLights + renderer).
let palette: [Color] = [
    Color(red: 0.85, green: 0.11, blue: 0.14), Color(red: 0.11, green: 0.58, blue: 0.24),
    Color(red: 0.95, green: 0.76, blue: 0.22), Color(red: 0.16, green: 0.42, blue: 0.90),
    Color(red: 1.0, green: 0.93, blue: 0.80),
]
func strands(_ size: CGSize) -> [[CGPoint]] {
    let rs: CGFloat = 90, bs: CGFloat = 55
    let sc = max(2, Int((size.height/rs).rounded())), bc = max(3, Int((size.width/bs).rounded()))
    let sag = 0.35*rs, inset = size.width*0.06, left = inset, right = size.width-inset
    return (0..<sc).map { s in
        let y0 = size.height*(CGFloat(s)+0.5)/CGFloat(sc)
        return (0..<bc).map { i -> CGPoint in
            let t = CGFloat(i)/CGFloat(bc-1)
            return CGPoint(x: left+(right-left)*t, y: y0+sag*4*t*(1-t))
        }
    }
}

struct StringView: View {
    let time: Double; let mode: Int  // 0 chase, 1 multi, 2 twinkle
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red:0.03,green:0.04,blue:0.07)))
            for strand in strands(size) {
                var wire = Path(); wire.addLines(strand)
                ctx.stroke(wire, with: .color(.white.opacity(0.12)), lineWidth: 1.5)
                for (i, b) in strand.enumerated() {
                    let (col, br) = state(i, strand.count)
                    ctx.drawLayer { l in
                        l.addFilter(.blur(radius: 6)); l.blendMode = .plusLighter
                        let r = 4.0 + 6*br
                        l.fill(Path(ellipseIn: CGRect(x: b.x-r, y: b.y-r, width: 2*r, height: 2*r)), with: .color(col.opacity(0.5*br)))
                    }
                    ctx.fill(Path(ellipseIn: CGRect(x: b.x-4, y: b.y-4, width: 8, height: 8)), with: .color(col.opacity(0.4+0.6*br)))
                }
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
        default:
            let seed = Double((i*2654435761)%1000)/1000.0
            return (palette[i%5], 0.1+0.9*pow(0.5+0.5*sin(time*1.8+seed*6.283),2))
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
let size = CGSize(width: 560, height: 360)
render(StringView(time: 0.0, mode: 0), size, "/tmp/xmas_chase.png")
render(StringView(time: 1.3, mode: 0), size, "/tmp/xmas_chase2.png")
render(StringView(time: 0.6, mode: 1), size, "/tmp/xmas_multi.png")
render(StringView(time: 0.6, mode: 2), size, "/tmp/xmas_twinkle.png")
