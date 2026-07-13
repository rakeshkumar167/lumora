import CoreGraphics

/// A divergence-free 2-D flow field for advecting particles into swirling,
/// school-like motion. Built as the curl of a smooth scalar potential
/// `ψ(x, y, t)`, so `flow = (∂ψ/∂y, -∂ψ/∂x)` is analytically divergence-free
/// (no sources or sinks — particle density stays visually even). Pure, no
/// AppKit. Deterministic: the same `(x, y, t)` always yields the same vector.
public struct CurlNoiseField {
    /// Spatial frequency of the noise lattice (higher = tighter swirls).
    public var frequency: Double
    /// How fast the field evolves over time.
    public var timeScale: Double

    public init(frequency: Double = 3.0, timeScale: Double = 0.15) {
        self.frequency = frequency
        self.timeScale = timeScale
    }

    /// Divergence-free flow vector at a normalized point `(x, y)` and time `t`.
    public func flow(x: Double, y: Double, t: Double) -> CGVector {
        let eps = 1e-3
        // Curl of a scalar potential: (dψ/dy, -dψ/dx).
        let dpsi_dx = (potential(x + eps, y, t) - potential(x - eps, y, t)) / (2 * eps)
        let dpsi_dy = (potential(x, y + eps, t) - potential(x, y - eps, t)) / (2 * eps)
        return CGVector(dx: dpsi_dy, dy: -dpsi_dx)
    }

    /// Smooth scalar potential in roughly `[-1, 1]`. Two octaves: a low
    /// frequency for school-scale swirls plus a finer one for fish-scale wiggle.
    /// The sum is still a scalar, so its curl stays divergence-free.
    func potential(_ x: Double, _ y: Double, _ t: Double) -> Double {
        let lo = valueNoise(x * frequency, y * frequency, t * timeScale)
        let hi = valueNoise(x * frequency * 2.3 + 11.5, y * frequency * 2.3 + 4.2, t * timeScale * 1.6)
        return ((lo * 0.65 + hi * 0.35) * 2 - 1)
    }

    // MARK: - 3-D value noise

    /// Trilinearly-interpolated lattice value noise in `[0, 1]`.
    func valueNoise(_ x: Double, _ y: Double, _ z: Double) -> Double {
        let xi = fastFloor(x), yi = fastFloor(y), zi = fastFloor(z)
        let xf = x - Double(xi), yf = y - Double(yi), zf = z - Double(zi)
        let u = fade(xf), v = fade(yf), w = fade(zf)

        func corner(_ dx: Int, _ dy: Int, _ dz: Int) -> Double {
            hash(xi + dx, yi + dy, zi + dz)
        }
        let x00 = lerp(corner(0, 0, 0), corner(1, 0, 0), u)
        let x10 = lerp(corner(0, 1, 0), corner(1, 1, 0), u)
        let x01 = lerp(corner(0, 0, 1), corner(1, 0, 1), u)
        let x11 = lerp(corner(0, 1, 1), corner(1, 1, 1), u)
        let y0 = lerp(x00, x10, v)
        let y1 = lerp(x01, x11, v)
        return lerp(y0, y1, w)
    }

    private func fade(_ t: Double) -> Double { t * t * t * (t * (t * 6 - 15) + 10) }
    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private func fastFloor(_ v: Double) -> Int { v >= 0 ? Int(v) : Int(v) - 1 }

    /// Deterministic integer hash → `[0, 1]`. Integer mixing (no `sin`) so it is
    /// stable across platforms and optimizers.
    private func hash(_ x: Int, _ y: Int, _ z: Int) -> Double {
        var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263 &+ z &* 2_147_483_647))
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h = h ^ (h >> 16)
        return Double(h & 0xFFFFFF) / Double(0xFFFFFF)
    }
}
