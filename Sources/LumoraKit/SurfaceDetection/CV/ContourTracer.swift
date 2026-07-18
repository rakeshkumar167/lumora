import CoreGraphics
import Foundation

/// Region-boundary contours with containment hierarchy.
///
/// Each foreground component's outer boundary is traced (Moore-neighbor
/// tracing, clockwise). Nesting is derived by point-in-polygon containment:
/// a contour's parent is the smallest other contour that encloses it.
public enum ContourTracer {
    public static func traceContours(binary: [Bool], width w: Int, height h: Int) -> [Contour] {
        let field = ConnectedComponents.label(binary, width: w, height: h)
        if field.count == 0 { return [] }

        // First boundary-start pixel (raster order) for each label.
        var starts = [(Int, Int)?](repeating: nil, count: field.count + 1)
        for y in 0..<h {
            for x in 0..<w {
                let l = field.labels[y * w + x]
                if l > 0, starts[l] == nil { starts[l] = (x, y) }
            }
        }

        var polys: [[CGPoint]] = []
        for label in 1...field.count {
            guard let s = starts[label] else { continue }
            polys.append(mooreTrace(field, label: label, start: s))
        }

        // Containment hierarchy: parent = smallest OTHER polygon enclosing this
        // polygon's first point.
        var contours: [Contour] = []
        for i in polys.indices {
            let p0 = polys[i][0]
            var bestParent: Int? = nil
            var bestArea = Double.greatestFiniteMagnitude
            for j in polys.indices where j != i {
                if pointInPolygon(p0, polys[j]) {
                    let a = polygonArea(polys[j])
                    if a < bestArea { bestArea = a; bestParent = j }
                }
            }
            contours.append(Contour(points: polys[i], parentIndex: bestParent))
        }
        return contours
    }

    // 8 directions clockwise: W, NW, N, NE, E, SE, S, SW.
    private static let dx = [-1, -1, 0, 1, 1, 1, 0, -1]
    private static let dy = [0, -1, -1, -1, 0, 1, 1, 1]

    private static func dirIndex(_ ddx: Int, _ ddy: Int) -> Int {
        for d in 0..<8 where dx[d] == ddx && dy[d] == ddy { return d }
        return 0
    }

    /// Moore-neighbor boundary trace (clockwise) of one component.
    static func mooreTrace(_ field: LabelField, label: Int, start: (Int, Int)) -> [CGPoint] {
        let w = field.width, h = field.height
        func isFg(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < w && y >= 0 && y < h && field.labels[y * w + x] == label }

        var boundary: [CGPoint] = []
        var px = start.0, py = start.1
        // Came from the west (the pixel to the left is background since `start`
        // is the first pixel of its component in raster order).
        var bx = start.0 - 1, by = start.1
        let maxSteps = 8 * w * h + 8
        var steps = 0
        while steps < maxSteps {
            boundary.append(CGPoint(x: px, y: py))
            let startDir = dirIndex(bx - px, by - py)
            var foundNext = false
            var nx = px, ny = py, nbx = bx, nby = by
            for k in 1...8 {
                let d = (startDir + k) % 8
                let cx = px + dx[d], cy = py + dy[d]
                if isFg(cx, cy) {
                    nx = cx; ny = cy
                    let pd = (d + 7) % 8            // the neighbor examined just before (background)
                    nbx = px + dx[pd]; nby = py + dy[pd]
                    foundNext = true
                    break
                }
            }
            if !foundNext { break }                 // isolated pixel
            if nx == start.0 && ny == start.1 { break } // closed the loop
            px = nx; py = ny; bx = nbx; by = nby
            steps += 1
        }
        return boundary
    }

    /// Ray-cast point-in-polygon (even-odd rule).
    static func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        if poly.count < 3 { return false }
        var inside = false
        var j = poly.count - 1
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

    /// Absolute polygon area (shoelace).
    static func polygonArea(_ poly: [CGPoint]) -> Double {
        if poly.count < 3 { return 0 }
        var s = 0.0
        var j = poly.count - 1
        for i in poly.indices {
            s += Double(poly[j].x + poly[i].x) * Double(poly[j].y - poly[i].y)
            j = i
        }
        return abs(s) / 2
    }
}
