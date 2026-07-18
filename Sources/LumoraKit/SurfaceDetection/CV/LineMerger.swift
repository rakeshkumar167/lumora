import CoreGraphics
import Foundation

/// Merge near-parallel, close, overlapping line segments into single lines.
public enum LineMerger {
    public struct Config {
        public var angleTol: Double  // max acute angle difference (radians)
        public var distTol: Double   // max perpendicular distance (px)
        public var gapTol: Double    // max along-direction gap to still merge (px)
        public init(angleTol: Double = 0.17, distTol: Double = 6, gapTol: Double = 12) {
            self.angleTol = angleTol; self.distTol = distTol; self.gapTol = gapTol
        }
    }

    public static func merge(_ lines: [DetectedLine], config: Config = .init()) -> [DetectedLine] {
        let n = lines.count
        if n <= 1 { return lines }
        var parent = Array(0..<n)
        func find(_ i: Int) -> Int { var r = i; while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }; return r }
        func union(_ i: Int, _ j: Int) { parent[find(i)] = find(j) }

        for i in 0..<n { for j in (i + 1)..<n where mergeable(lines[i], lines[j], config) { union(i, j) } }

        var groups: [Int: [DetectedLine]] = [:]
        for i in 0..<n { groups[find(i), default: []].append(lines[i]) }
        return groups.values.map { refit($0) }
    }

    static func mergeable(_ a: DetectedLine, _ b: DetectedLine, _ c: Config) -> Bool {
        if LineGeometry.angleDifference(a.angle, b.angle) > c.angleTol { return false }
        // Perpendicular distance from b's midpoint to a's infinite line.
        let mid = CGPoint(x: (b.p1.x + b.p2.x) / 2, y: (b.p1.y + b.p2.y) / 2)
        if perpendicularDistance(mid, a) > c.distTol { return false }
        // Along-direction overlap/gap using a's direction.
        let dir = direction(a)
        let (a0, a1) = project(a, onto: dir)
        let (b0, b1) = project(b, onto: dir)
        let gap = max(max(a0, b0) - min(a1, b1), 0) // 0 if intervals overlap
        return gap <= c.gapTol
    }

    static func direction(_ l: DetectedLine) -> (Double, Double) {
        let dx = Double(l.p2.x - l.p1.x), dy = Double(l.p2.y - l.p1.y)
        let n = (dx * dx + dy * dy).squareRoot()
        return n > 0 ? (dx / n, dy / n) : (1, 0)
    }

    static func project(_ l: DetectedLine, onto dir: (Double, Double)) -> (Double, Double) {
        let t1 = Double(l.p1.x) * dir.0 + Double(l.p1.y) * dir.1
        let t2 = Double(l.p2.x) * dir.0 + Double(l.p2.y) * dir.1
        return (min(t1, t2), max(t1, t2))
    }

    static func perpendicularDistance(_ p: CGPoint, _ l: DetectedLine) -> Double {
        let dir = direction(l)
        let vx = Double(p.x - l.p1.x), vy = Double(p.y - l.p1.y)
        let along = vx * dir.0 + vy * dir.1
        let cx = vx - along * dir.0, cy = vy - along * dir.1
        return (cx * cx + cy * cy).squareRoot()
    }

    /// Refit a group to one segment: the extent of all endpoints along the
    /// longest member's direction, anchored at that member's p1.
    static func refit(_ group: [DetectedLine]) -> DetectedLine {
        if group.count == 1 { return group[0] }
        let base = group.max { $0.length < $1.length }!
        let dir = direction(base)
        let anchor = base.p1
        var lo = Double.greatestFiniteMagnitude, hi = -Double.greatestFiniteMagnitude
        for l in group {
            for p in [l.p1, l.p2] {
                let t = Double(p.x - anchor.x) * dir.0 + Double(p.y - anchor.y) * dir.1
                lo = min(lo, t); hi = max(hi, t)
            }
        }
        let p1 = CGPoint(x: anchor.x + CGFloat(dir.0 * lo), y: anchor.y + CGFloat(dir.1 * lo))
        let p2 = CGPoint(x: anchor.x + CGFloat(dir.0 * hi), y: anchor.y + CGFloat(dir.1 * hi))
        return DetectedLine(p1: p1, p2: p2)
    }
}
