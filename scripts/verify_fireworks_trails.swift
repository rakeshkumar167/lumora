// Run: swift scripts/verify_fireworks_trails.swift
// One burst rendered with OLD vs NEW trail params, to confirm trails are
// longer/brighter with the new tuning.
import AppKit
import SwiftUI

func hash01(_ a: Int, _ b: Int) -> Double {
    var h = UInt64(bitPattern: Int64(a &* 374761393 &+ b &* 668265263))
    h = (h ^ (h >> 13)) &* 1274126177
    return Double(h % 10000) / 10000.0
}

struct Burst: View {
    let isNew: Bool
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            ctx.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.addFilter(.blur(radius: 3))
                let w = Double(size.width), h = Double(size.height)
                let minDim = min(w, h)
                let launchX = w * 0.5, burstY = h * 0.42
                let bt = 0.35
                let dragPow = 3.0
                let expand = 1 - pow(1 - bt, dragPow)
                let btPrev = max(0, bt - (isNew ? 0.12 : 0.05))
                let expandPrev = 1 - pow(1 - btPrev, dragPow)
                let maxR = minDim * 0.26
                let gravity = minDim * 0.22
                let drop = gravity * bt * bt, dropPrev = gravity * btPrev * btPrev
                let fade = pow(max(0, 1 - bt), isNew ? 1.05 : 1.3)
                let seed = 7, hue = 0.08, particles = 70
                for pI in 0..<particles {
                    let ang = Double(pI)/Double(particles)*2*(.pi) + hash01(seed, pI+10)*0.22
                    let spd = 0.28 + hash01(seed, pI+50)*0.72
                    let dist = maxR*spd*expand, distPrev = maxR*spd*expandPrev
                    let px = launchX + cos(ang)*dist, py = burstY + sin(ang)*dist + drop
                    let pxP = launchX + cos(ang)*distPrev, pyP = burstY + sin(ang)*distPrev + dropPrev
                    let ph = hue + (hash01(seed, pI)-0.5)*0.1
                    let alpha = fade * (0.72 + 0.28*sin(Double(pI)*1.3))
                    let col = Color(hue: ph, saturation: isNew ? 0.82 : 0.85, brightness: 1)
                    let lwid = (isNew ? 2.4 : 1.7) * (isNew ? (0.5+0.5*fade) : (0.4+0.6*fade))
                    var streak = Path(); streak.move(to: CGPoint(x: pxP, y: pyP)); streak.addLine(to: CGPoint(x: px, y: py))
                    layer.stroke(streak, with: .color(col.opacity(isNew ? min(1, alpha*1.15) : alpha*0.8)), style: StrokeStyle(lineWidth: lwid, lineCap: .round))
                    let hr = lwid * (isNew ? 0.95 : 0.85)
                    layer.fill(Path(ellipseIn: CGRect(x: px-hr, y: py-hr, width: hr*2, height: hr*2)), with: .color(col.opacity(alpha)))
                }
            }
            ctx.draw(Text(isNew ? "NEW" : "OLD").foregroundStyle(.white).font(.caption), at: CGPoint(x: 30, y: 16))
        }
    }
}

struct Board: View {
    var body: some View {
        HStack(spacing: 8) {
            Burst(isNew: false).frame(width: 380, height: 380)
            Burst(isNew: true).frame(width: 380, height: 380)
        }.background(Color.black)
    }
}

MainActor.assumeIsolated {
    let r = ImageRenderer(content: Board()); r.scale = 2
    if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "/tmp/fireworks_trails.png")); print("wrote /tmp/fireworks_trails.png")
    }
}
