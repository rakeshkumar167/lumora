import CoreGraphics
import Foundation

/// Pure math for the **Pendulum Paint** effect: a rotary-harmonograph path that
/// a rotating, swaying paint bucket would trace onto a canvas. No SwiftUI
/// dependency, fully deterministic from an integer cycle index so the editor and
/// projector render identical paintings (the effect stays a pure function of the
/// global clock).
///
/// The emitter position at path parameter `s` (radians) is the sum of two
/// sinusoids per axis — a low-frequency **sway** term and a higher-frequency
/// **rotation** term — under a shared exponential **decay** so the figure spirals
/// inward as a real swinging bucket loses energy. Output is normalized into the
/// unit box (0...1) centered at 0.5 with a small margin.
public enum PendulumPaint {
    /// Coefficients defining one painting. Re-seeded per cycle for variety.
    public struct Coefficients: Equatable {
        public var fx1, fy1: Double      // sway frequencies (near 1)
        public var fx2, fy2: Double      // rotation frequencies (near-integer)
        public var px1, py1, px2, py2: Double   // phases
        public var ax1, ay1, ax2, ay2: Double   // amplitudes
        public var decay: Double         // envelope decay per radian
        public var sMax: Double          // total parameter span
        public var norm: Double          // amplitude used to normalize into unit box
    }

    /// A tiny splitmix64 PRNG so seeding is deterministic and portable.
    private struct SplitMix64 {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        /// Uniform double in `[lo, hi)`.
        mutating func double(_ lo: Double, _ hi: Double) -> Double {
            let u = Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
            return lo + u * (hi - lo)
        }
        mutating func int(_ lo: Int, _ hi: Int) -> Int {
            lo + Int(next() % UInt64(hi - lo + 1))
        }
    }

    /// Deterministic coefficients for a given painting index.
    public static func coefficients(cycle: Int) -> Coefficients {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(cycle)) &* 0x2545_F491_4F6C_DD1D &+ 0x9E37_79B9)

        // Sway near freq 1, gently detuned per axis so the base ellipse precesses.
        let fx1 = 1.0
        let fy1 = 1.0 + rng.double(-0.04, 0.04)
        // Rotation at a near-integer multiple (2...6), slightly detuned so the
        // rosette loops slowly rotate rather than closing exactly.
        let k = Double(rng.int(2, 6))
        let fx2 = k
        let fy2 = k + rng.double(-0.05, 0.05)

        let px1 = rng.double(0, 2 * .pi)
        let py1 = rng.double(0, 2 * .pi)
        let px2 = rng.double(0, 2 * .pi)
        let py2 = rng.double(0, 2 * .pi)

        let ax1 = 1.0, ay1 = 1.0
        let ax2 = rng.double(0.30, 0.70)
        let ay2 = rng.double(0.30, 0.70)

        // More turns = denser painting. Decay derived from turns so the envelope
        // always lands around e^-2.6 (~7%) at the end, giving a clean spiral-in.
        let turns = rng.double(22, 40)
        let sMax = 2 * .pi * turns
        let decay = 2.6 / sMax

        let norm = max(ax1 + ax2, ay1 + ay2)

        return Coefficients(fx1: fx1, fy1: fy1, fx2: fx2, fy2: fy2,
                            px1: px1, py1: py1, px2: px2, py2: py2,
                            ax1: ax1, ay1: ay1, ax2: ax2, ay2: ay2,
                            decay: decay, sMax: sMax, norm: norm)
    }

    /// Emitter position at parameter `s`, normalized into the unit box.
    public static func point(_ s: Double, _ c: Coefficients) -> CGPoint {
        let env = exp(-c.decay * s)
        let x = c.ax1 * sin(c.fx1 * s + c.px1) * env + c.ax2 * sin(c.fx2 * s + c.px2) * env
        let y = c.ay1 * sin(c.fy1 * s + c.py1) * env + c.ay2 * sin(c.fy2 * s + c.py2) * env
        return CGPoint(x: 0.5 + (x / c.norm) * 0.46,
                       y: 0.5 + (y / c.norm) * 0.46)
    }

    /// Recommended number of samples for a painting (denser for faster rotation).
    public static func sampleCount(_ c: Coefficients) -> Int {
        min(4200, max(600, Int(c.sMax * 16)))
    }

    /// The full painting polyline (normalized points), evenly sampled in `s`.
    public static func samples(cycle: Int, count: Int? = nil) -> [CGPoint] {
        let c = coefficients(cycle: cycle)
        let n = count ?? sampleCount(c)
        guard n >= 2 else { return [] }
        var pts = [CGPoint]()
        pts.reserveCapacity(n)
        for i in 0..<n {
            let s = c.sMax * Double(i) / Double(n - 1)
            pts.append(point(s, c))
        }
        return pts
    }
}
