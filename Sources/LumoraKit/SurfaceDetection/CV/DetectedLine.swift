import CoreGraphics
import Foundation

/// A straight line segment in working-image pixel coordinates.
public struct DetectedLine: Equatable {
    public var p1: CGPoint
    public var p2: CGPoint
    public var angle: Double   // orientation in [0, π)
    public var length: Double

    public init(p1: CGPoint, p2: CGPoint, angle: Double, length: Double) {
        self.p1 = p1; self.p2 = p2; self.angle = angle; self.length = length
    }

    /// Build from endpoints, deriving `angle` (in [0, π)) and `length`.
    public init(p1: CGPoint, p2: CGPoint) {
        self.p1 = p1
        self.p2 = p2
        let dx = Double(p2.x - p1.x), dy = Double(p2.y - p1.y)
        self.length = (dx * dx + dy * dy).squareRoot()
        self.angle = LineGeometry.normalizeAngle(atan2(dy, dx))
    }
}

public enum LineGeometry {
    /// Fold an angle into [0, π) (a line and its 180°-rotation are the same line).
    public static func normalizeAngle(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: .pi)
        if x < 0 { x += .pi }
        // Guard the boundary: values numerically equal to π fold to 0.
        if x >= .pi { x -= .pi }
        return x
    }

    /// Acute difference between two orientations, in [0, π/2].
    public static func angleDifference(_ a: Double, _ b: Double) -> Double {
        let d = abs(normalizeAngle(a) - normalizeAngle(b))
        return min(d, .pi - d)
    }
}
