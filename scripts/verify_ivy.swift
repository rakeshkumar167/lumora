// Run: swift scripts/verify_ivy.swift
// Renders the Growing Ivy edge effect (vines crawling a surface outline,
// sprouting inward leafy branches, then an autumn fall) at three cycle phases —
// early grow / fully grown / autumn-fall — for a .rect outline. Mirrors
// GrowingIvyView in SurfaceContentView.swift (standalone scripts can't import
// the app module's private views). Writes PNGs to /tmp and asserts each frame
// is non-blank and the fully-grown frame has more lit pixels than early grow.
import AppKit
import SwiftUI

// MARK: - Shared geometry (mirrors the free functions in SurfaceContentView)

func rectOutline(_ size: CGSize) -> [CGPoint] {
    [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0),
     CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)]
}

func closedLengths(_ pts: [CGPoint]) -> (cum: [CGFloat], total: CGFloat) {
    var cum: [CGFloat] = [0]
    var total: CGFloat = 0
    for i in 0..<pts.count {
        let a = pts[i], b = pts[(i + 1) % pts.count]
        total += hypot(b.x - a.x, b.y - a.y)
        cum.append(total)
    }
    return (cum, total)
}

func pointAt(_ pts: [CGPoint], _ cum: [CGFloat], length: CGFloat) -> CGPoint {
    guard let first = pts.first else { return .zero }
    for i in 0..<pts.count {
        let segEnd = cum[i + 1]
        if segEnd >= length {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            let segStart = cum[i]
            let segLen = segEnd - segStart
            let f = segLen > 0 ? (length - segStart) / segLen : 0
            return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
        }
    }
    return first
}

func hash01(_ i: Int, _ salt: Int) -> CGFloat {
    let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
    return CGFloat(v - floor(v))
}

// MARK: - Frame (mirrors GrowingIvyView.draw for a rect outline, single cycle)

struct IvyFrame: View {
    let elapsed: Double
    let color: Color
    let accent: Color

    let growDur = 14.0, holdDur = 4.0, autumnDur = 4.0
    var period: Double { growDur + holdDur + autumnDur }

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.02)))
            let pts = rectOutline(size)
            let (cum, total) = closedLengths(pts)
            let minDim = min(size.width, size.height)
            let localT = elapsed.truncatingRemainder(dividingBy: period)
            let startArc = hash01(0, 7) * total

            let growFrac = min(localT / growDur, 1.0)
            let litLen = CGFloat(growFrac) * total
            let inAutumn = localT >= growDur + holdDur
            let autumnT = inAutumn ? (localT - growDur - holdDur) / autumnDur : 0
            let colorT = min(1, autumnT / 0.5)
            let leafColor = mix(color, accent, colorT)
            let fallT = max(0, (autumnT - 0.35) / 0.65)

            func loopPoint(_ arc: CGFloat) -> CGPoint {
                var a = arc.truncatingRemainder(dividingBy: total); if a < 0 { a += total }
                return pointAt(pts, cum, length: a)
            }

            // Main stem
            var stem = Path()
            let step = max(4, total / 400)
            var arc: CGFloat = 0, first = true
            while arc <= litLen {
                let p = loopPoint(startArc + arc)
                if first { stem.move(to: p); first = false } else { stem.addLine(to: p) }
                arc += step
            }

            // Centroid for inward branch direction
            var cx: CGFloat = 0, cy: CGFloat = 0
            for p in pts { cx += p.x; cy += p.y }
            cx /= CGFloat(pts.count); cy /= CGFloat(pts.count)

            var branches = Path()
            var leaves: [(CGPoint, CGFloat, Double)] = []
            let spacing: CGFloat = 46
            let count = max(4, min(60, Int(total / spacing)))
            for i in 0..<count {
                let salt = i
                let anchorArc = CGFloat(i) * spacing + (hash01(salt, 1) - 0.5) * spacing * 0.6
                var prog = max(0, min(1, (litLen - anchorArc) / 70))
                if localT > growDur { prog = min(1, prog + CGFloat((localT - growDur) / 1.5)) }
                if prog <= 0.001 { continue }
                let base = loopPoint(startArc + anchorArc)
                var inx = cx - base.x, iny = cy - base.y
                let ilen = max(0.0001, hypot(inx, iny)); inx /= ilen; iny /= ilen
                let length = minDim * (0.10 + 0.10 * hash01(salt, 3))
                branches.move(to: base)
                for s in 1...8 {
                    let t = CGFloat(s) / 8 * prog
                    branches.addLine(to: CGPoint(x: base.x + inx * length * t, y: base.y + iny * length * t))
                }
                for lt in [CGFloat(0.34), 0.55, 0.74, 0.92] where lt <= prog + 0.02 {
                    var center = CGPoint(x: base.x + inx * length * lt, y: base.y + iny * length * lt)
                    var opacity = 1.0
                    if fallT > 0 {
                        let personal = min(1, Double(fallT) * (0.7 + Double(hash01(i, 6)) * 0.9))
                        center.y += CGFloat(personal * personal) * minDim * 0.6
                        opacity = max(0, 1 - personal)
                    }
                    leaves.append((center, minDim * 0.03, opacity))
                }
            }

            ctx.stroke(stem, with: .color(color.opacity(0.95)),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            ctx.stroke(branches, with: .color(color.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            for (c, sz, op) in leaves where op > 0.02 {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - sz * 0.45, y: c.y - sz, width: sz * 0.9, height: sz * 2)),
                         with: .color(leafColor.opacity(op)))
            }
        }
        .frame(width: 500, height: 500)
    }

    func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let an = NSColor(a).usingColorSpace(.deviceRGB) ?? .green
        let bn = NSColor(b).usingColorSpace(.deviceRGB) ?? .orange
        let f = CGFloat(max(0, min(1, t)))
        return Color(red: Double(an.redComponent + (bn.redComponent - an.redComponent) * f),
                     green: Double(an.greenComponent + (bn.greenComponent - an.greenComponent) * f),
                     blue: Double(an.blueComponent + (bn.blueComponent - an.blueComponent) * f))
    }
}

func litPixelCount(_ image: NSImage) -> Int {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return 0 }
    var count = 0
    for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
            if lum > 0.08 { count += 1 }
        }
    }
    return count
}

func render(elapsed: Double, path: String) -> Int {
    var lit = 0
    MainActor.assumeIsolated {
        let renderer = ImageRenderer(content: IvyFrame(elapsed: elapsed,
                                                       color: Color(red: 0.25, green: 0.75, blue: 0.30),
                                                       accent: Color(red: 0.85, green: 0.45, blue: 0.10)))
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

let earlyGrow = render(elapsed: 2.0,  path: "/tmp/ivy_early_grow.png")     // stem just starting
let fullGrown = render(elapsed: 17.0, path: "/tmp/ivy_full_grown.png")     // hold phase, all leaves out
let autumnFall = render(elapsed: 21.0, path: "/tmp/ivy_autumn_fall.png")   // leaves falling

precondition(earlyGrow > 0, "early-grow frame should be non-blank")
precondition(fullGrown > 0, "full-grown frame should be non-blank")
precondition(autumnFall > 0, "autumn-fall frame should be non-blank")
precondition(fullGrown > earlyGrow, "ivy should grow: full (\(fullGrown)) > early (\(earlyGrow))")

print("PASS: ivy grows (early=\(earlyGrow) < full=\(fullGrown)); autumn frame renders (\(autumnFall))")
