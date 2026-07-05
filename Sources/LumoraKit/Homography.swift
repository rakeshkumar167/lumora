import CoreGraphics
import QuartzCore

/// Projective-geometry core for perspective-correcting a surface's media.
///
/// A `Homography` is a 3×3 matrix (row-major, `m[row*3 + col]`) that maps a
/// 2D point given as the column vector `[x y 1]ᵀ`. This type has no UI
/// dependencies and is fully unit-testable.
public struct Homography: Equatable {
    /// Row-major 3×3 matrix. Always 9 elements.
    public var m: [Double]

    public init(_ m: [Double]) {
        precondition(m.count == 9, "Homography requires 9 elements")
        self.m = m
    }

    public static let identity = Homography([1, 0, 0, 0, 1, 0, 0, 0, 1])

    /// Matrix product `self * other` (both map column vectors on the left).
    public func multiplied(by o: Homography) -> Homography {
        var r = [Double](repeating: 0, count: 9)
        for i in 0..<3 {
            for j in 0..<3 {
                var s = 0.0
                for k in 0..<3 { s += m[i * 3 + k] * o.m[k * 3 + j] }
                r[i * 3 + j] = s
            }
        }
        return Homography(r)
    }

    /// Applies the projective map to a point (with perspective divide).
    public func apply(_ p: CGPoint) -> CGPoint {
        let x = Double(p.x), y = Double(p.y)
        let xp = m[0] * x + m[1] * y + m[2]
        let yp = m[3] * x + m[4] * y + m[5]
        let w = m[6] * x + m[7] * y + m[8]
        return CGPoint(x: xp / w, y: yp / w)
    }

    /// Maps the unit square corners (0,0),(1,0),(1,1),(0,1) → `quad[0...3]`.
    /// (Closed-form square-to-quad projective map, after Heckbert.)
    public static func squareToQuad(_ q: [CGPoint]) -> Homography {
        precondition(q.count == 4, "quad requires 4 points")
        let x0 = Double(q[0].x), y0 = Double(q[0].y)
        let x1 = Double(q[1].x), y1 = Double(q[1].y)
        let x2 = Double(q[2].x), y2 = Double(q[2].y)
        let x3 = Double(q[3].x), y3 = Double(q[3].y)

        let dx1 = x1 - x2, dx2 = x3 - x2, sumX = x0 - x1 + x2 - x3
        let dy1 = y1 - y2, dy2 = y3 - y2, sumY = y0 - y1 + y2 - y3

        var a, b, c, d, e, f, g, h: Double
        if abs(sumX) < 1e-12 && abs(sumY) < 1e-12 {
            // Parallelogram — affine map, no perspective terms.
            a = x1 - x0; b = x2 - x1; c = x0
            d = y1 - y0; e = y2 - y1; f = y0
            g = 0; h = 0
        } else {
            let denom = dx1 * dy2 - dx2 * dy1
            g = (sumX * dy2 - dx2 * sumY) / denom
            h = (dx1 * sumY - sumX * dy1) / denom
            a = x1 - x0 + g * x1
            b = x3 - x0 + h * x3
            c = x0
            d = y1 - y0 + g * y1
            e = y3 - y0 + h * y3
            f = y0
        }
        return Homography([a, b, c, d, e, f, g, h, 1])
    }

    /// Maps a rectangle's coordinate space onto the unit square.
    public static func rectToSquare(_ r: CGRect) -> Homography {
        let w = Double(r.width), h = Double(r.height)
        let ox = Double(r.origin.x), oy = Double(r.origin.y)
        return Homography([
            1 / w, 0, -ox / w,
            0, 1 / h, -oy / h,
            0, 0, 1,
        ])
    }

    /// Homography mapping `rect`'s four corners (TL, TR, BR, BL) → `quad`.
    public static func rectToQuad(_ rect: CGRect, _ quad: [CGPoint]) -> Homography {
        squareToQuad(quad).multiplied(by: rectToSquare(rect))
    }

    /// This homography expressed as a `CATransform3D` (row-vector convention,
    /// so it can drive SwiftUI's `ProjectionTransform` or a `CALayer`).
    public var caTransform3D: CATransform3D {
        var t = CATransform3DIdentity
        t.m11 = m[0]; t.m21 = m[1]; t.m41 = m[2]
        t.m12 = m[3]; t.m22 = m[4]; t.m42 = m[5]
        t.m14 = m[6]; t.m24 = m[7]; t.m44 = m[8]
        return t
    }

    /// Convenience: the `CATransform3D` mapping `rect` → `quad` directly.
    public static func transform(from rect: CGRect, to quad: [CGPoint]) -> CATransform3D {
        rectToQuad(rect, quad).caTransform3D
    }
}
