import CoreGraphics
import Foundation

/// Merge over-segmented adjacent same-color polygons (e.g. wall panels split by
/// interior seams) via convex hull of each merged group.
public enum PolygonMerger {
    public struct Item {
        public var polygon: [CGPoint]
        public var color: RGBAColor
        public init(polygon: [CGPoint], color: RGBAColor) { self.polygon = polygon; self.color = color }
    }
    public struct Config {
        public var colorTolerance: Double   // Euclidean RGB distance
        public var adjacencyDistance: Double // px between nearest boundary points
        public init(colorTolerance: Double = 0.14, adjacencyDistance: Double = 6) {
            self.colorTolerance = colorTolerance; self.adjacencyDistance = adjacencyDistance
        }
    }

    public static func merge(_ items: [Item], config: Config = .init()) -> [[CGPoint]] {
        let n = items.count
        if n <= 1 { return items.map { $0.polygon } }
        var parent = Array(0..<n)
        func find(_ i: Int) -> Int { var r = i; while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }; return r }
        func union(_ i: Int, _ j: Int) { parent[find(i)] = find(j) }

        for i in 0..<n {
            for j in (i + 1)..<n where colorClose(items[i].color, items[j].color, config.colorTolerance)
                && adjacent(items[i].polygon, items[j].polygon, config.adjacencyDistance) {
                union(i, j)
            }
        }
        var groups: [Int: [CGPoint]] = [:]
        for i in 0..<n { groups[find(i), default: []].append(contentsOf: items[i].polygon) }
        return groups.values.map { convexHull($0) }
    }

    static func colorClose(_ a: RGBAColor, _ b: RGBAColor, _ tol: Double) -> Bool {
        let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
        return (dr * dr + dg * dg + db * db).squareRoot() <= tol
    }

    static func adjacent(_ a: [CGPoint], _ b: [CGPoint], _ maxDist: Double) -> Bool {
        let d2 = maxDist * maxDist
        for p in a { for q in b {
            let dx = Double(p.x - q.x), dy = Double(p.y - q.y)
            if dx * dx + dy * dy <= d2 { return true }
        } }
        return false
    }

    /// Andrew's monotone chain convex hull.
    static func convexHull(_ pts: [CGPoint]) -> [CGPoint] {
        let p = Array(Set(pts.map { HPoint($0) })).map { $0.cg }.sorted {
            $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y
        }
        if p.count < 3 { return p }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
            Double(a.x - o.x) * Double(b.y - o.y) - Double(a.y - o.y) * Double(b.x - o.x)
        }
        var lower: [CGPoint] = []
        for pt in p { while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], pt) <= 0 { lower.removeLast() }; lower.append(pt) }
        var upper: [CGPoint] = []
        for pt in p.reversed() { while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], pt) <= 0 { upper.removeLast() }; upper.append(pt) }
        lower.removeLast(); upper.removeLast()
        return lower + upper
    }

    // Hashable wrapper so we can dedup CGPoints before hulling.
    private struct HPoint: Hashable {
        let x: CGFloat, y: CGFloat
        init(_ p: CGPoint) { x = p.x; y = p.y }
        var cg: CGPoint { CGPoint(x: x, y: y) }
    }
}
