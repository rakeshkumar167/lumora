import CoreGraphics
import Foundation

/// Douglas–Peucker polyline simplification.
public enum PolygonApproximator {
    public static func simplify(_ points: [CGPoint], epsilon: Double) -> [CGPoint] {
        if points.count < 3 { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true; keep[points.count - 1] = true
        simplifyRange(points, 0, points.count - 1, epsilon, &keep)
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    private static func simplifyRange(_ pts: [CGPoint], _ lo: Int, _ hi: Int,
                                      _ eps: Double, _ keep: inout [Bool]) {
        if hi <= lo + 1 { return }
        var maxDist = 0.0, idx = lo
        for i in (lo + 1)..<hi {
            let d = perpDistance(pts[i], pts[lo], pts[hi])
            if d > maxDist { maxDist = d; idx = i }
        }
        if maxDist > eps {
            keep[idx] = true
            simplifyRange(pts, lo, idx, eps, &keep)
            simplifyRange(pts, idx, hi, eps, &keep)
        }
    }

    /// Perpendicular distance from `p` to the segment (a, b).
    static func perpDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let len = (dx * dx + dy * dy).squareRoot()
        if len < 1e-12 { return Double((p.x - a.x).magnitude + (p.y - a.y).magnitude) }
        let area2 = abs(dx * Double(p.y - a.y) - dy * Double(p.x - a.x))
        return area2 / len
    }
}
