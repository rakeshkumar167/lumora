import CoreGraphics
import Foundation

/// A 0…1 confidence that a polygon is a clean planar surface.
public enum ConfidenceScorer {
    public static func score(_ polygon: [CGPoint], frameWidth: Int, frameHeight: Int) -> Double {
        if polygon.count < 3 { return 0 }
        let area = polygonArea(polygon)
        let bb = bounds(polygon)
        let bw = Double(bb.width), bh = Double(bb.height)
        if bw <= 0 || bh <= 0 { return 0 }

        // Rectangularity: how fully the polygon fills its bounding box.
        let fill = min(1, area / (bw * bh))
        // Aspect: penalize slivers (aspect 1 → 1.0, aspect ≥ 8 → ~0).
        let aspect = max(bw, bh) / min(bw, bh)
        let aspectScore = max(0, 1 - (aspect - 1) / 7)
        // Size: prefer a meaningful chunk of the frame, saturating.
        let frac = area / Double(frameWidth * frameHeight)
        let sizeScore = min(1, frac / 0.05)

        let s = 0.5 * fill + 0.3 * aspectScore + 0.2 * sizeScore
        return max(0, min(1, s))
    }

    static func polygonArea(_ poly: [CGPoint]) -> Double {
        var s = 0.0, j = poly.count - 1
        for i in poly.indices { s += Double(poly[j].x + poly[i].x) * Double(poly[j].y - poly[i].y); j = i }
        return abs(s) / 2
    }
    static func bounds(_ poly: [CGPoint]) -> CGRect {
        var a = poly[0], b = poly[0]
        for p in poly { a.x = min(a.x, p.x); a.y = min(a.y, p.y); b.x = max(b.x, p.x); b.y = max(b.y, p.y) }
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }
}
