import CoreGraphics
import Foundation

/// Geometric validity checks for candidate surface polygons.
public enum PolygonValidator {
    public struct Config {
        public var minAreaFraction: Double
        public var maxAreaFraction: Double
        public var minFillRatio: Double   // polygon area / bbox area
        public var maxAspectRatio: Double // longer bbox side / shorter
        public var minPoints: Int
        public init(minAreaFraction: Double = 0.008, maxAreaFraction: Double = 0.9,
                    minFillRatio: Double = 0.35, maxAspectRatio: Double = 12, minPoints: Int = 3) {
            self.minAreaFraction = minAreaFraction
            self.maxAreaFraction = maxAreaFraction
            self.minFillRatio = minFillRatio
            self.maxAspectRatio = maxAspectRatio
            self.minPoints = minPoints
        }
    }

    public static func isValid(_ poly: [CGPoint], frameWidth: Int, frameHeight: Int,
                               config: Config = .init()) -> Bool {
        if poly.count < config.minPoints { return false }
        let frameArea = Double(frameWidth * frameHeight)
        if frameArea <= 0 { return false }

        let area = polygonArea(poly)
        let frac = area / frameArea
        if frac < config.minAreaFraction || frac > config.maxAreaFraction { return false }

        let (minX, minY, maxX, maxY) = bounds(poly)
        let bw = Double(maxX - minX), bh = Double(maxY - minY)
        if bw <= 0 || bh <= 0 { return false }
        if area / (bw * bh) < config.minFillRatio { return false }
        if max(bw, bh) / min(bw, bh) > config.maxAspectRatio { return false }
        if isSelfIntersecting(poly) { return false }
        return true
    }

    static func polygonArea(_ poly: [CGPoint]) -> Double {
        if poly.count < 3 { return 0 }
        var s = 0.0, j = poly.count - 1
        for i in poly.indices {
            s += Double(poly[j].x + poly[i].x) * Double(poly[j].y - poly[i].y)
            j = i
        }
        return abs(s) / 2
    }

    static func bounds(_ poly: [CGPoint]) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var a = poly[0], b = poly[0]
        for p in poly { a.x = min(a.x, p.x); a.y = min(a.y, p.y); b.x = max(b.x, p.x); b.y = max(b.y, p.y) }
        return (a.x, a.y, b.x, b.y)
    }

    /// True if any pair of non-adjacent polygon edges properly intersects.
    static func isSelfIntersecting(_ poly: [CGPoint]) -> Bool {
        let n = poly.count
        if n < 4 { return false }
        for i in 0..<n {
            let a1 = poly[i], a2 = poly[(i + 1) % n]
            for j in (i + 1)..<n {
                // Skip adjacent edges (sharing a vertex).
                if j == i { continue }
                if (j + 1) % n == i || j == (i + 1) % n { continue }
                let b1 = poly[j], b2 = poly[(j + 1) % n]
                if segmentsProperlyIntersect(a1, a2, b1, b2) { return true }
            }
        }
        return false
    }

    private static func segmentsProperlyIntersect(_ p1: CGPoint, _ p2: CGPoint,
                                                  _ p3: CGPoint, _ p4: CGPoint) -> Bool {
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
            Double(a.x - o.x) * Double(b.y - o.y) - Double(a.y - o.y) * Double(b.x - o.x)
        }
        let d1 = cross(p3, p4, p1), d2 = cross(p3, p4, p2)
        let d3 = cross(p1, p2, p3), d4 = cross(p1, p2, p4)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0))
            && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }
}
