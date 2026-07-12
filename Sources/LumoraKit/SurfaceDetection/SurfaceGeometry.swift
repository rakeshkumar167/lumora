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

    /// Area of the axis-aligned bounding box enclosing the points.
    public static func boundingBoxArea(_ pts: [CGPoint]) -> Double {
        guard let first = pts.first else { return 0 }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in pts {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return Double((maxX - minX) * (maxY - minY))
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
    /// The result lies inside the hull; prefer `enclosingQuad` for surface
    /// fitting, which keeps corners at true edge intersections.
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

    /// Fit an *enclosing* quad to a convex hull: repeatedly remove the edge
    /// whose neighbouring edge-lines intersect with the least added area,
    /// replacing the edge's two endpoints with that intersection. Corners land
    /// where the region's dominant edges actually meet (a vertex-removal
    /// reduction instead shrinks inward and cuts corners off).
    public static func enclosingQuad(_ hull: [CGPoint]) -> [CGPoint] {
        var v = hull
        while v.count > 4 {
            let n = v.count
            var bestEdge = -1
            var bestPoint = CGPoint.zero
            var bestAdded = Double.greatestFiniteMagnitude
            for i in 0..<n {
                let a = v[(i - 1 + n) % n], b = v[i]
                let c = v[(i + 1) % n], d = v[(i + 2) % n]
                guard let (p, t, u) = lineIntersection(a, b, d, c), t > 1, u > 1 else { continue }
                let added = abs(cross(b, p, c)) / 2
                if added < bestAdded { bestAdded = added; bestEdge = i; bestPoint = p }
            }
            // No outward intersection (parallel edges): fall back to shrinking.
            guard bestEdge >= 0 else { return reduceToQuad(v) }
            v[bestEdge] = bestPoint
            v.remove(at: (bestEdge + 1) % n)
        }
        return v
    }

    /// Intersection of the infinite lines a->b and d->c, with the line
    /// parameters (p = a + t*(b-a) = d + u*(c-d)). Nil for parallel lines.
    private static func lineIntersection(_ a: CGPoint, _ b: CGPoint,
                                         _ d: CGPoint, _ c: CGPoint) -> (CGPoint, Double, Double)? {
        let rx = Double(b.x - a.x), ry = Double(b.y - a.y)
        let sx = Double(c.x - d.x), sy = Double(c.y - d.y)
        let denom = rx * sy - ry * sx
        guard abs(denom) > 1e-12 else { return nil }
        let qx = Double(d.x - a.x), qy = Double(d.y - a.y)
        let t = (qx * sy - qy * sx) / denom
        let u = (qx * ry - qy * rx) / denom
        return (CGPoint(x: Double(a.x) + t * rx, y: Double(a.y) + t * ry), t, u)
    }

    /// Order four points as TL, TR, BR, BL in a top-left origin (y grows down):
    /// sort by angle around the centroid (clockwise on screen), then rotate so
    /// the corner nearest the top-left starts the ring.
    public static func orderedCorners(_ quad: [CGPoint]) -> [CGPoint] {
        guard quad.count == 4 else { return quad }
        let c = centroid(quad)
        var pts = quad.sorted {
            atan2(Double($0.y - c.y), Double($0.x - c.x)) < atan2(Double($1.y - c.y), Double($1.x - c.x))
        }
        var tl = 0
        for i in 1..<4 where pts[i].x + pts[i].y < pts[tl].x + pts[tl].y { tl = i }
        pts = Array(pts[tl...] + pts[..<tl])
        return pts
    }

    /// Approximate overlap of two convex polygons as a fraction of the
    /// smaller one's area, estimated on a regular sample grid over the
    /// smaller polygon's bounding box.
    public static func overlapOverSmaller(_ a: [CGPoint], _ b: [CGPoint], samples: Int = 32) -> Double {
        guard a.count >= 3, b.count >= 3 else { return 0 }
        let (small, big) = polygonArea(a) <= polygonArea(b) ? (a, b) : (b, a)
        var minX = small[0].x, minY = small[0].y, maxX = small[0].x, maxY = small[0].y
        for p in small {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        guard maxX > minX, maxY > minY else { return 0 }
        var inSmall = 0, inBoth = 0
        for iy in 0..<samples {
            let y = minY + (maxY - minY) * (CGFloat(iy) + 0.5) / CGFloat(samples)
            for ix in 0..<samples {
                let x = minX + (maxX - minX) * (CGFloat(ix) + 0.5) / CGFloat(samples)
                let pt = CGPoint(x: x, y: y)
                if contains(pt, in: small) {
                    inSmall += 1
                    if contains(pt, in: big) { inBoth += 1 }
                }
            }
        }
        guard inSmall > 0 else { return 0 }
        return Double(inBoth) / Double(inSmall)
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
