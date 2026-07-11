// Run: swift scripts/verify_contour_rainbow.swift
// Traces two synthetic shapes (circle + square) concatenated, with rainbow
// banding, near full sweep — confirming the gradient and both shapes present.
import AppKit
import SwiftUI

let bandCount = 24
func hue(_ b: Int) -> Double { (Double(b) + 0.5) / Double(bandCount) }
func rainbowBand(length: CGFloat, total: CGFloat, phase: Double) -> Int {
    guard total > 0 else { return 0 }
    let frac = Double(length/total) + phase, w = frac - floor(frac)
    return min(max(Int(w * Double(bandCount)), 0), bandCount - 1)
}

// Two closed polylines (normalized 0…1) as stand-in "contours": a circle then a square.
func circle(cx: CGFloat, cy: CGFloat, r: CGFloat, n: Int) -> [CGPoint] {
    (0...n).map { i in let a = CGFloat(i)/CGFloat(n)*2*(.pi); return CGPoint(x: cx+r*cos(a), y: cy+r*sin(a)) }
}
func square(cx: CGFloat, cy: CGFloat, s: CGFloat) -> [CGPoint] {
    [CGPoint(x:cx-s,y:cy-s),CGPoint(x:cx+s,y:cy-s),CGPoint(x:cx+s,y:cy+s),CGPoint(x:cx-s,y:cy+s),CGPoint(x:cx-s,y:cy-s)]
}
func lens(_ pts: [CGPoint]) -> [CGFloat] {
    var l: [CGFloat] = [0]; var a: CGFloat = 0
    for k in 1..<pts.count { a += hypot(pts[k].x-pts[k-1].x, pts[k].y-pts[k-1].y); l.append(a) }
    return l
}
let shapes = [circle(cx:0.32,cy:0.4,r:0.22,n:80), square(cx:0.68,cy:0.6,s:0.18)]
let contours = shapes.map { ($0, lens($0)) }
let total = contours.reduce(CGFloat(0)) { $0 + ($1.1.last ?? 0) }

struct V: View {
    let sweepP: CGFloat
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.02)))
            let w = size.width, h = size.height
            func sp(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x*w, y: p.y*h) }
            let drawn = sweepP * total
            var acc: CGFloat = 0
            var bands = [Path](repeating: Path(), count: bandCount)
            func band(_ m: CGFloat) -> Int { rainbowBand(length: m, total: total, phase: 0) }
            for (pts, ls) in contours {
                let ctotal = ls.last ?? 0
                if drawn >= acc + ctotal {
                    for k in 1..<pts.count { let bi = band(acc+(ls[k-1]+ls[k])/2); bands[bi].move(to: sp(pts[k-1])); bands[bi].addLine(to: sp(pts[k])) }
                    acc += ctotal
                } else if drawn > acc {
                    let target = drawn - acc
                    for k in 1..<pts.count {
                        if ls[k] <= target { let bi = band(acc+(ls[k-1]+ls[k])/2); bands[bi].move(to: sp(pts[k-1])); bands[bi].addLine(to: sp(pts[k])) }
                        else { break }
                    }
                    break
                } else { break }
            }
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 3))
                for bi in bands.indices where !bands[bi].isEmpty { l.stroke(bands[bi], with: .color(Color(hue: hue(bi), saturation: 0.95, brightness: 1).opacity(0.5)), lineWidth: 3) }
            }
            for bi in bands.indices where !bands[bi].isEmpty { ctx.stroke(bands[bi], with: .color(Color(hue: hue(bi), saturation: 0.95, brightness: 1)), lineWidth: 1.8) }
        }
    }
}

func render(_ p: CGFloat, _ path: String) {
    MainActor.assumeIsolated {
        let r = ImageRenderer(content: V(sweepP: p).frame(width: 500, height: 500)); r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)); print("wrote \(path)") }
    }
}
render(0.5, "/tmp/contour_rainbow_half.png")   // circle done, square mid-trace
render(1.0, "/tmp/contour_rainbow_full.png")   // both shapes, full rainbow
