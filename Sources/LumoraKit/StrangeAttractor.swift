import Foundation

/// A single integrated point on a strange-attractor polyline.
public struct AttractorPoint: Equatable {
    public var x, y, z: Double
    public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
}

public enum StrangeAttractor {
    /// Classic Lorenz system via forward Euler (fine at small dt). Fixed seed →
    /// deterministic. Returns the integrated polyline.
    public static func lorenz(steps: Int, dt: Double,
                              sigma: Double = 10, rho: Double = 28, beta: Double = 8.0/3.0) -> [AttractorPoint] {
        var x = 0.1, y = 0.0, z = 0.0
        var out: [AttractorPoint] = []; out.reserveCapacity(steps)
        for _ in 0..<steps {
            let dx = sigma * (y - x), dy = x * (rho - z) - y, dz = x * y - beta * z
            x += dx * dt; y += dy * dt; z += dz * dt
            out.append(AttractorPoint(x: x, y: y, z: z))
        }
        return out
    }
}
