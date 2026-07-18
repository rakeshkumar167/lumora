import CoreGraphics
import Foundation

/// Convert a detected polygon into a 4-corner quad, keeping the dominant real
/// edges as the base (a parallelogram from the 2–3 longest adjacent edges), with
/// a min-area enclosing-quad fallback for shapes that don't fit that heuristic.
public enum PolygonToQuad {
    public static func convert(_ polygon: [CGPoint]) -> [CGPoint] {
        let n = polygon.count
        if n < 3 { return polygon }
        if n == 4 { return SurfaceGeometry.orderedCorners(polygon) }
        if n == 3 { return SurfaceGeometry.orderedCorners(parallelogram(polygon[0], polygon[1], polygon[2])) }

        func edgeLen(_ i: Int) -> Double {
            let a = polygon[i], b = polygon[(i + 1) % n]
            let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            return (dx * dx + dy * dy).squareRoot()
        }

        // Best window of 3 consecutive edges → 4 vertices.
        var best3 = 0, best3Len = -1.0
        for i in 0..<n {
            let t = edgeLen(i) + edgeLen((i + 1) % n) + edgeLen((i + 2) % n)
            if t > best3Len { best3Len = t; best3 = i }
        }
        let q3 = [polygon[best3], polygon[(best3 + 1) % n], polygon[(best3 + 2) % n], polygon[(best3 + 3) % n]]

        // Best window of 2 consecutive edges → 3 vertices → parallelogram.
        var best2 = 0, best2Len = -1.0
        for i in 0..<n {
            let t = edgeLen(i) + edgeLen((i + 1) % n)
            if t > best2Len { best2Len = t; best2 = i }
        }
        let q2 = parallelogram(polygon[best2], polygon[(best2 + 1) % n], polygon[(best2 + 2) % n])

        let i3 = iou(q3, polygon), i2 = iou(q2, polygon)
        let (bestQuad, bestIoU) = i3 >= i2 ? (q3, i3) : (q2, i2)
        if bestIoU >= 0.70 { return SurfaceGeometry.orderedCorners(bestQuad) }

        let fb = SurfaceGeometry.enclosingQuad(SurfaceGeometry.convexHull(polygon))
        return SurfaceGeometry.orderedCorners(fb.count == 4 ? fb : bestQuad)
    }

    /// Fourth parallelogram corner D = A + C − B for the corner A-B-C.
    static func parallelogram(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> [CGPoint] {
        [a, b, c, CGPoint(x: a.x + c.x - b.x, y: a.y + c.y - b.y)]
    }

    /// Sampled intersection-over-union of two polygons.
    static func iou(_ a: [CGPoint], _ b: [CGPoint], samples: Int = 48) -> Double {
        let pts = a + b
        guard let first = pts.first else { return 0 }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in pts { minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y) }
        if maxX <= minX || maxY <= minY { return 0 }
        var inter = 0, uni = 0
        for i in 0..<samples {
            for j in 0..<samples {
                let x = minX + (maxX - minX) * (CGFloat(i) + 0.5) / CGFloat(samples)
                let y = minY + (maxY - minY) * (CGFloat(j) + 0.5) / CGFloat(samples)
                let p = CGPoint(x: x, y: y)
                let ina = SurfaceGeometry.contains(p, in: a), inb = SurfaceGeometry.contains(p, in: b)
                if ina && inb { inter += 1 }
                if ina || inb { uni += 1 }
            }
        }
        return uni > 0 ? Double(inter) / Double(uni) : 0
    }
}
