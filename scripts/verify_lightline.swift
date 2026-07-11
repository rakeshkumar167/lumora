// Run: swift scripts/verify_lightline.swift
// Renders a fork network at several fill fronts to /tmp PNGs for inspection.
import AppKit
import SwiftUI

struct Seg { let a: Int; let b: Int }
let joints: [CGPoint] = [
    CGPoint(x: 0.10, y: 0.50), // 0 source
    CGPoint(x: 0.45, y: 0.50), // 1 fork
    CGPoint(x: 0.85, y: 0.25), // 2
    CGPoint(x: 0.85, y: 0.75), // 3
]
let segs = [Seg(a: 0, b: 1), Seg(a: 1, b: 2), Seg(a: 1, b: 3)]
let size = CGSize(width: 600, height: 400)

// Distances from source (joint 0) along edges.
func dist() -> [Double] {
    var d = [Double](repeating: .greatestFiniteMagnitude, count: joints.count)
    d[0] = 0
    // Simple relaxation (graph is a tree).
    for _ in 0..<joints.count {
        for s in segs {
            let w = Double(hypot(joints[s.b].x - joints[s.a].x, joints[s.b].y - joints[s.a].y))
            if d[s.a] + w < d[s.b] { d[s.b] = d[s.a] + w }
            if d[s.b] + w < d[s.a] { d[s.a] = d[s.b] + w }
        }
    }
    return d
}
let d = dist()
let maxD = d.max() ?? 1

struct Frame: View {
    let front: Double
    var body: some View {
        Canvas { ctx, sz in
            ctx.fill(Path(CGRect(origin: .zero, size: sz)), with: .color(.black))
            func pt(_ i: Int) -> CGPoint { CGPoint(x: joints[i].x * sz.width, y: joints[i].y * sz.height) }
            var lit = Path(); var heads: [CGPoint] = []
            for s in segs {
                let near = Swift.min(d[s.a], d[s.b])
                let segLen = Double(hypot(joints[s.b].x - joints[s.a].x, joints[s.b].y - joints[s.a].y))
                let f = segLen > 0 ? Swift.min(Swift.max((front - near) / segLen, 0), 1) : 0
                if f <= 0 { continue }
                let (p0, p1) = d[s.a] <= d[s.b] ? (pt(s.a), pt(s.b)) : (pt(s.b), pt(s.a))
                let e = CGPoint(x: p0.x + (p1.x - p0.x) * f, y: p0.y + (p1.y - p0.y) * f)
                lit.move(to: p0); lit.addLine(to: e)
                if f < 1 { heads.append(e) }
            }
            ctx.drawLayer { l in l.addFilter(.blur(radius: 16)); l.blendMode = .plusLighter
                l.stroke(lit, with: .color(.cyan.opacity(0.5)), style: StrokeStyle(lineWidth: 18, lineCap: .round)) }
            ctx.stroke(lit, with: .color(.cyan), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            for h in heads { ctx.fill(Path(ellipseIn: CGRect(x: h.x-4, y: h.y-4, width: 8, height: 8)), with: .color(.white)) }
        }
        .frame(width: size.width, height: size.height)
    }
}

MainActor.assumeIsolated {
    for (i, frac) in [0.0, 0.4, 0.7, 1.0].enumerated() {
        let renderer = ImageRenderer(content: Frame(front: frac * maxD))
        renderer.scale = 2
        if let img = renderer.nsImage,
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            let url = URL(fileURLWithPath: "/tmp/lightline_\(i).png")
            try? png.write(to: url)
            print("wrote \(url.path)")
        }
    }
}
