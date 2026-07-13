import XCTest
import CoreGraphics
@testable import LumoraKit

final class ParticleSwarmTests: XCTestCase {

    // MARK: CurlNoiseField

    func testCurlFieldIsDeterministic() {
        let f = CurlNoiseField()
        let a = f.flow(x: 0.37, y: 0.62, t: 1.5)
        let b = f.flow(x: 0.37, y: 0.62, t: 1.5)
        XCTAssertEqual(a.dx, b.dx, accuracy: 1e-12)
        XCTAssertEqual(a.dy, b.dy, accuracy: 1e-12)
    }

    func testCurlFieldIsApproximatelyDivergenceFree() {
        // Divergence = ∂vx/∂x + ∂vy/∂y should be ~0 everywhere for a curl field.
        let f = CurlNoiseField()
        let h = 1e-3
        var maxDiv = 0.0
        for (x, y, t) in [(0.2, 0.3, 0.0), (0.55, 0.8, 2.1), (0.9, 0.15, 5.0)] {
            let dvx_dx = (f.flow(x: x + h, y: y, t: t).dx - f.flow(x: x - h, y: y, t: t).dx) / (2 * h)
            let dvy_dy = (f.flow(x: x, y: y + h, t: t).dy - f.flow(x: x, y: y - h, t: t).dy) / (2 * h)
            maxDiv = max(maxDiv, abs(Double(dvx_dx) + Double(dvy_dy)))
        }
        XCTAssertLessThan(maxDiv, 0.05, "curl field should be near divergence-free")
    }

    func testValueNoiseInRange() {
        let f = CurlNoiseField()
        for i in 0..<200 {
            let v = f.valueNoise(Double(i) * 0.37, Double(i) * 0.11, Double(i) * 0.05)
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
    }

    // MARK: ParticleSwarmSystem

    func testStepKeepsParticlesInUnitSquareAndConservesCount() {
        let sys = ParticleSwarmSystem(count: 500)
        let field = CurlNoiseField()
        var t = 0.0
        for _ in 0..<120 {
            sys.step(rawDt: 1.0 / 60, drivers: .idle(time: t), field: field, time: t)
            t += 1.0 / 60
        }
        XCTAssertEqual(sys.count, 500)
        for p in sys.positions {
            XCTAssertTrue((0...1).contains(Double(p.x)), "x wrapped in range")
            XCTAssertTrue((0...1).contains(Double(p.y)), "y wrapped in range")
        }
    }

    func testHigherSpeedProducesLargerDisplacement() {
        let field = CurlNoiseField()
        func meanDisplacement(speed: Double) -> Double {
            let sys = ParticleSwarmSystem(count: 300, seed: 42)
            let start = sys.positions
            var d = SwarmDrivers.idle(time: 0)
            d.speed = speed
            d.turbulence = 0; d.cohesion = 0   // isolate flow advection
            var t = 0.0
            for _ in 0..<60 {
                sys.step(rawDt: 1.0 / 60, drivers: d, field: field, time: t)
                t += 1.0 / 60
            }
            // Toroidal-aware shortest displacement per axis.
            var total = 0.0
            for (a, b) in zip(start, sys.positions) {
                let dx = wrapDelta(Double(b.x - a.x)), dy = wrapDelta(Double(b.y - a.y))
                total += (dx * dx + dy * dy).squareRoot()
            }
            return total / Double(start.count)
        }
        XCTAssertGreaterThan(meanDisplacement(speed: 2.5), meanDisplacement(speed: 0.5) * 1.5)
    }

    private func wrapDelta(_ d: Double) -> Double {
        var r = d.truncatingRemainder(dividingBy: 1)
        if r > 0.5 { r -= 1 }; if r < -0.5 { r += 1 }
        return r
    }

    // MARK: AudioBandAnalyzer

    /// Build a magnitude spectrum with all energy in one frequency region.
    private func spectrum(bins: Int, hot: Range<Int>, level: Float) -> [Float] {
        var m = [Float](repeating: 0, count: bins)
        for i in hot where i < bins { m[i] = level }
        return m
    }

    func testBassHeavySpectrumReadsAsBass() {
        let a = AudioBandAnalyzer()
        let sr = 44_100.0, bins = 512
        // hzPerBin = sr / (2*bins) ≈ 43 Hz. Bass < 250 Hz → bins 1..5.
        let m = spectrum(bins: bins, hot: 1..<5, level: 1.0)
        var levels = AudioLevels.silent
        for _ in 0..<50 { levels = a.process(magnitudes: m, sampleRate: sr) }
        XCTAssertGreaterThan(levels.bass, 0.8)
        XCTAssertLessThan(levels.treble, 0.2)
    }

    func testTrebleHeavySpectrumReadsAsTreble() {
        let a = AudioBandAnalyzer()
        let sr = 44_100.0, bins = 512
        // Treble 2000..8000 Hz → bins ~46..186.
        let m = spectrum(bins: bins, hot: 60..<120, level: 1.0)
        var levels = AudioLevels.silent
        for _ in 0..<50 { levels = a.process(magnitudes: m, sampleRate: sr) }
        XCTAssertGreaterThan(levels.treble, 0.8)
        XCTAssertLessThan(levels.bass, 0.2)
    }

    func testSilenceDecaysToZero() {
        let a = AudioBandAnalyzer()
        let sr = 44_100.0, bins = 512
        let loud = spectrum(bins: bins, hot: 1..<5, level: 1.0)
        for _ in 0..<20 { _ = a.process(magnitudes: loud, sampleRate: sr) }
        var levels = AudioLevels.silent
        let quiet = [Float](repeating: 0, count: bins)
        for _ in 0..<400 { levels = a.process(magnitudes: quiet, sampleRate: sr) }
        XCTAssertLessThan(levels.overall, 0.05)
    }

    // MARK: SwarmDrivers

    func testAudioDriversAreMonotonicInBass() {
        let quiet = SwarmDrivers(from: AudioLevels(bass: 0.1, mid: 0, treble: 0, overall: 0.1))
        let loud = SwarmDrivers(from: AudioLevels(bass: 0.9, mid: 0, treble: 0, overall: 0.9))
        XCTAssertGreaterThan(loud.speed, quiet.speed)
        XCTAssertGreaterThan(loud.energy, quiet.energy)
        XCTAssertGreaterThan(loud.brightness, quiet.brightness)
    }
}
