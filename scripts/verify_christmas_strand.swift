// Run: swift scripts/verify_christmas_strand.swift
// Replicates ChristmasLights.strands geometry to confirm bulb count, sag count,
// top-pinning, and height-independence (short vs tall surface).
import AppKit
import SwiftUI

struct Cfg { var bulbCount: Int; var sagCount: Int }

func strand(_ size: CGSize, _ cfg: Cfg) -> [CGPoint] {
    guard size.width > 0, size.height > 0 else { return [] }
    let bulbCount = max(2, cfg.bulbCount)
    let sagCount = max(1, cfg.sagCount)
    let inset = size.width * 0.06
    let left = inset, right = size.width - inset
    let span = max(1, right - left)
    let sagSpan = span / CGFloat(sagCount)
    let sagDepth = sagSpan * 0.28
    let pinY = sagDepth * 0.45 + size.width * 0.012
    var bulbs: [CGPoint] = []
    for i in 0..<bulbCount {
        let t = bulbCount == 1 ? 0.5 : CGFloat(i) / CGFloat(bulbCount - 1)
        let x = left + span * t
        let localT = (t * CGFloat(sagCount)).truncatingRemainder(dividingBy: 1)
        let y = pinY + sagDepth * 4 * localT * (1 - localT)
        bulbs.append(CGPoint(x: x, y: y))
    }
    return bulbs
}

struct Panel: View {
    let title: String; let size: CGSize; let cfg: Cfg
    var body: some View {
        Canvas { ctx, sz in
            ctx.fill(Path(CGRect(origin: .zero, size: sz)), with: .color(Color(red: 0.03, green: 0.04, blue: 0.07)))
            let bulbs = strand(sz, cfg)
            var wire = Path(); wire.addLines(bulbs)
            ctx.stroke(wire, with: .color(Color(white: 0.35)), lineWidth: 1.5)
            let spacing = bulbs.count > 1 ? hypot(bulbs[1].x - bulbs[0].x, bulbs[1].y - bulbs[0].y) : 20
            let r = min(spacing * 0.34, sz.width * 0.045)
            let cols: [Color] = [.red, .green, .yellow, .blue, .white]
            for (i, b) in bulbs.enumerated() {
                ctx.fill(Path(ellipseIn: CGRect(x: b.x - r, y: b.y, width: r * 2, height: r * 2)),
                         with: .color(cols[i % cols.count]))
            }
            ctx.draw(Text(title).font(.caption2).foregroundColor(.white), at: CGPoint(x: 6, y: sz.height - 10), anchor: .bottomLeading)
        }
        .frame(width: size.width, height: size.height)
        .border(Color.white.opacity(0.25))
    }
}

struct Board: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Panel(title: "16 bulbs, 1 sag", size: CGSize(width: 380, height: 150), cfg: Cfg(bulbCount: 16, sagCount: 1))
                Panel(title: "30 bulbs, 3 sags", size: CGSize(width: 380, height: 150), cfg: Cfg(bulbCount: 30, sagCount: 3))
            }
            HStack(alignment: .top, spacing: 10) {
                Panel(title: "same, SHORT (h=120)", size: CGSize(width: 380, height: 120), cfg: Cfg(bulbCount: 20, sagCount: 2))
                Panel(title: "same, TALL (h=340) — lights stay at top", size: CGSize(width: 380, height: 340), cfg: Cfg(bulbCount: 20, sagCount: 2))
            }
        }.padding(14).background(Color.black)
    }
}

MainActor.assumeIsolated {
    let r = ImageRenderer(content: Board()); r.scale = 2
    if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "/tmp/christmas_strand.png")); print("wrote /tmp/christmas_strand.png")
    }
}
