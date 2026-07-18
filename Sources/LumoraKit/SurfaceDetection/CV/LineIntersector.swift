import CoreGraphics
import Foundation

/// Candidate corners from pairwise line intersections.
public enum LineIntersector {
    public struct Config {
        public var minAngle: Double // discard near-parallel pairs (radians)
        public var margin: Double   // allow intersections slightly outside the frame
        public init(minAngle: Double = 0.35, margin: Double = 0.05) {
            self.minAngle = minAngle; self.margin = margin
        }
    }

    public static func intersections(_ lines: [DetectedLine], width: Int, height: Int,
                                     config: Config = .init()) -> [CGPoint] {
        let w = Double(width), h = Double(height)
        let minX = -config.margin * w, maxX = (1 + config.margin) * w
        let minY = -config.margin * h, maxY = (1 + config.margin) * h
        var out: [CGPoint] = []
        for i in 0..<lines.count {
            for j in (i + 1)..<lines.count {
                if LineGeometry.angleDifference(lines[i].angle, lines[j].angle) < config.minAngle { continue }
                guard let p = intersect(lines[i], lines[j]) else { continue }
                let px = Double(p.x), py = Double(p.y)
                if px < minX || px > maxX || py < minY || py > maxY { continue }
                out.append(p)
            }
        }
        return out
    }

    /// Infinite-line intersection from two segments' endpoints (nil if parallel).
    static func intersect(_ a: DetectedLine, _ b: DetectedLine) -> CGPoint? {
        let x1 = Double(a.p1.x), y1 = Double(a.p1.y), x2 = Double(a.p2.x), y2 = Double(a.p2.y)
        let x3 = Double(b.p1.x), y3 = Double(b.p1.y), x4 = Double(b.p2.x), y4 = Double(b.p2.y)
        let denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        if abs(denom) < 1e-9 { return nil }
        let pre = x1 * y2 - y1 * x2, post = x3 * y4 - y3 * x4
        let px = (pre * (x3 - x4) - (x1 - x2) * post) / denom
        let py = (pre * (y3 - y4) - (y1 - y2) * post) / denom
        return CGPoint(x: px, y: py)
    }
}
