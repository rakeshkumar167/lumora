// Run: swift scripts/verify_hilbert.swift
// Renders the Hilbert Curve effect (order-6 space-filling curve, rainbow
// arc-length coloring, glowing pen head) at early/mid/near-complete draw
// progress, mirroring HilbertCurveView in SurfaceContentView.swift. Writes
// PNGs to /tmp and asserts each frame has lit pixels, with later frames
// having strictly more lit pixels than earlier ones (the curve builds up).
import AppKit
import SwiftUI

// Mirrors LumoraKit's HilbertCurve.points(order:).
enum HilbertCurve {
    static func points(order: Int) -> [CGPoint] {
        let n = 1 << max(0, order)
        var result: [CGPoint] = []
        result.reserveCapacity(n * n)
        for d in 0..<(n * n) {
            var rx = 0, ry = 0, t = d, x = 0, y = 0
            var s = 1
            while s < n {
                rx = 1 & (t / 2)
                ry = 1 & (t ^ rx)
                if ry == 0 {
                    if rx == 1 { x = s - 1 - x; y = s - 1 - y }
                    swap(&x, &y)
                }
                x += s * rx; y += s * ry
                t /= 4
                s <<= 1
            }
            result.append(CGPoint(x: x, y: y))
        }
        return result
    }
}

let order = 6
let gridSpan = 1 << order
let curvePoints = HilbertCurve.points(order: order)
let bandCount = 32

// Mirrors HilbertCurveView.draw's mapping + banding + glow, minus the
// hold/fade cycle timing (this script drives `headFrac` directly).
struct HilbertFrame: View {
    let headFrac: Double
    let mirrored: Bool
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.02)))
            let total = curvePoints.count
            let litCount = max(1, Int(headFrac * Double(total)))

            let margin = min(size.width, size.height) * 0.08
            let boxSize = min(size.width, size.height) - margin * 2
            let ox = (size.width - boxSize) / 2
            let oy = (size.height - boxSize) / 2
            let cell = boxSize / CGFloat(gridSpan - 1)
            func mapPoint(_ p: CGPoint) -> CGPoint {
                let gx = mirrored ? CGFloat(gridSpan - 1) - p.x : p.x
                return CGPoint(x: ox + gx * cell, y: oy + p.y * cell)
            }

            var bands = [Path](repeating: Path(), count: bandCount)
            for i in 1..<litCount {
                let a = mapPoint(curvePoints[i - 1])
                let b = mapPoint(curvePoints[i])
                let frac = Double(i) / Double(total)
                let bi = min(bandCount - 1, Int(frac * Double(bandCount)))
                bands[bi].move(to: a)
                bands[bi].addLine(to: b)
            }
            func bandColor(_ bi: Int) -> Color {
                Color(hue: (Double(bi) + 0.5) / Double(bandCount), saturation: 0.9, brightness: 1)
            }

            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 9))
                layer.blendMode = .plusLighter
                for bi in bands.indices where !bands[bi].isEmpty {
                    layer.stroke(bands[bi], with: .color(bandColor(bi).opacity(0.5)),
                                 style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                }
            }
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 3))
                layer.blendMode = .plusLighter
                for bi in bands.indices where !bands[bi].isEmpty {
                    layer.stroke(bands[bi], with: .color(bandColor(bi).opacity(0.75)),
                                 style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
            for bi in bands.indices where !bands[bi].isEmpty {
                ctx.stroke(bands[bi], with: .color(bandColor(bi)),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }

            if headFrac < 1.0 {
                let headIdx = min(litCount, total - 1)
                let head = mapPoint(curvePoints[headIdx])
                let r: CGFloat = 6
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: 6))
                    layer.blendMode = .plusLighter
                    layer.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: r * 2, height: r * 2)),
                               with: .color(.white))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: head.x - 3, y: head.y - 3, width: 6, height: 6)),
                         with: .color(.white))
            }
        }
        .frame(width: 500, height: 500)
    }
}

/// Counts pixels brighter than a small threshold (i.e. not the dark backdrop).
func litPixelCount(_ image: NSImage) -> Int {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return 0 }
    var count = 0
    let w = rep.pixelsWide, h = rep.pixelsHigh
    for y in stride(from: 0, to: h, by: 2) {
        for x in stride(from: 0, to: w, by: 2) {
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
            if lum > 0.08 { count += 1 }
        }
    }
    return count
}

func render(headFrac: Double, mirrored: Bool, path: String) -> Int {
    var lit = 0
    MainActor.assumeIsolated {
        let renderer = ImageRenderer(content: HilbertFrame(headFrac: headFrac, mirrored: mirrored))
        renderer.scale = 2
        guard let img = renderer.nsImage else { print("FAIL: no image for \(path)"); return }
        lit = litPixelCount(img)
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) (lit pixels: \(lit))")
        }
    }
    return lit
}

let early = render(headFrac: 0.08, mirrored: false, path: "/tmp/hilbert_early.png")
let mid = render(headFrac: 0.45, mirrored: false, path: "/tmp/hilbert_mid.png")
let near = render(headFrac: 0.95, mirrored: false, path: "/tmp/hilbert_near_complete.png")
let mirroredFull = render(headFrac: 1.0, mirrored: true, path: "/tmp/hilbert_full_mirrored.png")

precondition(early > 0, "early frame should have lit pixels")
precondition(mid > 0, "mid frame should have lit pixels")
precondition(near > 0, "near-complete frame should have lit pixels")
precondition(mirroredFull > 0, "mirrored full frame should have lit pixels")
precondition(mid > early, "curve should build up: mid (\(mid)) > early (\(early))")
precondition(near > mid, "curve should build up: near-complete (\(near)) > mid (\(mid))")

print("PASS: curve builds up over progress (early=\(early) < mid=\(mid) < near=\(near)); mirrored frame renders too (\(mirroredFull))")
