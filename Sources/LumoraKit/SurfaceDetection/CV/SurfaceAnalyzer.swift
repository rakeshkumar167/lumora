import CoreGraphics
import Foundation

public struct SurfaceProperties: Equatable {
    public var area: Double
    public var perimeter: Double
    public var aspectRatio: Double
    public var orientation: Double  // longest-edge orientation in [0, π)
    public var centroid: CGPoint
    public var boundingBox: CGRect
    public var averageColor: RGBAColor
}

public enum SurfaceAnalyzer {
    public static func properties(of polygon: [CGPoint], in rgb: RGBImage) -> SurfaceProperties {
        let area = polygonArea(polygon)
        let perim = perimeter(polygon)
        let bb = bounds(polygon)
        let bw = Double(bb.width), bh = Double(bb.height)
        let aspect = (bw > 0 && bh > 0) ? max(bw, bh) / min(bw, bh) : 1
        return SurfaceProperties(area: area, perimeter: perim, aspectRatio: aspect,
                                 orientation: longestEdgeOrientation(polygon),
                                 centroid: centroid(polygon), boundingBox: bb,
                                 averageColor: averageColor(of: polygon, in: rgb))
    }

    public static func averageColor(of polygon: [CGPoint], in rgb: RGBImage) -> RGBAColor {
        let bb = bounds(polygon)
        let x0 = max(0, Int(bb.minX)), x1 = min(rgb.width - 1, Int(bb.maxX))
        let y0 = max(0, Int(bb.minY)), y1 = min(rgb.height - 1, Int(bb.maxY))
        if x1 < x0 || y1 < y0 { return .white }
        // Cap sampling to ~4000 points for speed on large surfaces.
        let stride = max(1, Int((Double((x1 - x0 + 1) * (y1 - y0 + 1)) / 4000).squareRoot()))
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        var y = y0
        while y <= y1 {
            var x = x0
            while x <= x1 {
                if pointInPolygon(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5), polygon) {
                    let c = rgb.color(at: x, y); r += c.r; g += c.g; b += c.b; n += 1
                }
                x += stride
            }
            y += stride
        }
        if n == 0 { return .white }
        return RGBAColor(r: r / n, g: g / n, b: b / n)
    }

    static func polygonArea(_ poly: [CGPoint]) -> Double {
        if poly.count < 3 { return 0 }
        var s = 0.0, j = poly.count - 1
        for i in poly.indices { s += Double(poly[j].x + poly[i].x) * Double(poly[j].y - poly[i].y); j = i }
        return abs(s) / 2
    }

    static func perimeter(_ poly: [CGPoint]) -> Double {
        if poly.count < 2 { return 0 }
        var p = 0.0, j = poly.count - 1
        for i in poly.indices {
            let dx = Double(poly[i].x - poly[j].x), dy = Double(poly[i].y - poly[j].y)
            p += (dx * dx + dy * dy).squareRoot(); j = i
        }
        return p
    }

    static func centroid(_ poly: [CGPoint]) -> CGPoint {
        if poly.count < 3 { // degenerate → average of points
            var sx = 0.0, sy = 0.0
            for p in poly { sx += Double(p.x); sy += Double(p.y) }
            let n = Double(max(poly.count, 1))
            return CGPoint(x: sx / n, y: sy / n)
        }
        var a = 0.0, cx = 0.0, cy = 0.0, j = poly.count - 1
        for i in poly.indices {
            let cross = Double(poly[j].x) * Double(poly[i].y) - Double(poly[i].x) * Double(poly[j].y)
            a += cross
            cx += (Double(poly[j].x) + Double(poly[i].x)) * cross
            cy += (Double(poly[j].y) + Double(poly[i].y)) * cross
            j = i
        }
        if abs(a) < 1e-9 { return bounds(poly).center }
        a *= 0.5
        return CGPoint(x: cx / (6 * a), y: cy / (6 * a))
    }

    static func longestEdgeOrientation(_ poly: [CGPoint]) -> Double {
        var best = -1.0, angle = 0.0, j = poly.count - 1
        for i in poly.indices {
            let dx = Double(poly[i].x - poly[j].x), dy = Double(poly[i].y - poly[j].y)
            let len = dx * dx + dy * dy
            if len > best { best = len; angle = atan2(dy, dx) }
            j = i
        }
        var a = angle.truncatingRemainder(dividingBy: .pi)
        if a < 0 { a += .pi }
        return a
    }

    static func bounds(_ poly: [CGPoint]) -> CGRect {
        var a = poly[0], b = poly[0]
        for p in poly { a.x = min(a.x, p.x); a.y = min(a.y, p.y); b.x = max(b.x, p.x); b.y = max(b.y, p.y) }
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    public static func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        if poly.count < 3 { return false }
        var inside = false, j = poly.count - 1
        for i in poly.indices {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) {
                let t = (p.y - a.y) / (b.y - a.y)
                if p.x < a.x + t * (b.x - a.x) { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}

extension CGRect { var center: CGPoint { CGPoint(x: midX, y: midY) } }
