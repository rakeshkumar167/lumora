import CoreGraphics

/// Pure 2-D polygon helpers used by surface detection. No AppKit/Vision.
public enum SurfaceGeometry {
    /// Absolute polygon area via the shoelace formula (order-independent).
    public static func polygonArea(_ pts: [CGPoint]) -> Double {
        guard pts.count >= 3 else { return 0 }
        var a = 0.0
        for i in 0..<pts.count {
            let j = (i + 1) % pts.count
            a += Double(pts[i].x * pts[j].y - pts[j].x * pts[i].y)
        }
        return abs(a) / 2
    }

    public static func centroid(_ pts: [CGPoint]) -> CGPoint {
        guard !pts.isEmpty else { return .zero }
        var x = 0.0, y = 0.0
        for p in pts { x += Double(p.x); y += Double(p.y) }
        return CGPoint(x: x / Double(pts.count), y: y / Double(pts.count))
    }

    private static func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        Double((a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x))
    }

    /// Convex hull (Andrew's monotone chain). Collinear/interior points dropped.
    public static func convexHull(_ pts: [CGPoint]) -> [CGPoint] {
        let s = pts.sorted { $0.x < $1.x || ($0.x == $1.x && $0.y < $1.y) }
        guard s.count >= 3 else { return s }
        var lower: [CGPoint] = []
        for p in s {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [CGPoint] = []
        for p in s.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        lower.removeLast(); upper.removeLast()
        return lower + upper
    }

    /// Reduce a polygon to 4 vertices by greedily removing the vertex whose
    /// removal loses the least triangle area (keeps the strongest corners).
    public static func reduceToQuad(_ poly: [CGPoint]) -> [CGPoint] {
        var v = poly
        while v.count > 4 {
            var worst = 0
            var worstLoss = Double.greatestFiniteMagnitude
            for i in 0..<v.count {
                let a = v[(i - 1 + v.count) % v.count]
                let c = v[(i + 1) % v.count]
                let loss = abs(cross(a, v[i], c)) / 2
                if loss < worstLoss { worstLoss = loss; worst = i }
            }
            v.remove(at: worst)
        }
        return v
    }

    /// Order four points as TL, TR, BR, BL in a top-left origin (y grows down).
    public static func orderedCorners(_ quad: [CGPoint]) -> [CGPoint] {
        guard quad.count == 4 else { return quad }
        let tl = quad.min { $0.x + $0.y < $1.x + $1.y }!
        let br = quad.max { $0.x + $0.y < $1.x + $1.y }!
        let tr = quad.max { $0.x - $0.y < $1.x - $1.y }!
        let bl = quad.min { $0.x - $0.y < $1.x - $1.y }!
        return [tl, tr, br, bl]
    }

    /// Ray-casting point-in-polygon test.
    public static func contains(_ pt: CGPoint, in poly: [CGPoint]) -> Bool {
        guard poly.count >= 3 else { return false }
        var c = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            if ((poly[i].y > pt.y) != (poly[j].y > pt.y)) &&
                (pt.x < (poly[j].x - poly[i].x) * (pt.y - poly[i].y) / (poly[j].y - poly[i].y) + poly[i].x) {
                c.toggle()
            }
            j = i
        }
        return c
    }
}
