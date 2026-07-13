import CoreGraphics

/// A stateful buffer of particles advected through a `CurlNoiseField`, producing
/// school-of-fish / murmuration motion. Positions are normalized to the unit
/// square and wrap toroidally so density stays even. Pure (CoreGraphics only),
/// so the whole simulation is unit-testable; rendering lives in the app.
public final class ParticleSwarmSystem {
    public private(set) var positions: [CGPoint]
    public private(set) var velocities: [CGVector]
    /// Per-particle random constant in `0…1` — drives size, color and phase
    /// variation so particles don't move in lockstep.
    public let seeds: [Double]
    public var count: Int { positions.count }

    // Motion gains (normalized units per second).
    private let baseSpeed = 0.18
    private let cohesionGain = 0.22
    private let turbulenceGain = 0.16
    private let steer = 0.22
    private let maxSpeed = 0.7

    public init(count: Int, seed: UInt64 = 0x9E37) {
        var rng = seed | 1
        func next() -> Double {
            rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(rng >> 11) / Double(1 << 53)
        }
        var pos: [CGPoint] = [], vel: [CGVector] = [], sd: [Double] = []
        pos.reserveCapacity(count); vel.reserveCapacity(count); sd.reserveCapacity(count)
        for _ in 0..<count {
            pos.append(CGPoint(x: next(), y: next()))
            vel.append(.zero)
            sd.append(next())
        }
        positions = pos; velocities = vel; seeds = sd
    }

    /// Advance the simulation by `rawDt` seconds under `drivers`, using `field`
    /// evaluated at `time`. `rawDt` is clamped so a stalled frame can't teleport
    /// particles.
    public func step(rawDt: Double, drivers: SwarmDrivers, field: CurlNoiseField, time: Double) {
        let dt = min(max(rawDt, 0), 0.05)
        guard dt > 0 else { return }
        // Two slowly drifting attractors the school leans toward.
        let ax = 0.5 + 0.33 * sin(time * 0.13)
        let ay = 0.5 + 0.33 * cos(time * 0.17)

        for i in 0..<positions.count {
            let x = Double(positions[i].x), y = Double(positions[i].y)
            let f = field.flow(x: x, y: y, t: time)

            // Desired velocity (units/sec): flow + cohesion pull + turbulence.
            var dvx = Double(f.dx) * baseSpeed * drivers.speed
            var dvy = Double(f.dy) * baseSpeed * drivers.speed
            dvx += (ax - x) * cohesionGain * drivers.cohesion
            dvy += (ay - y) * cohesionGain * drivers.cohesion
            let phase = time * (1.4 + seeds[i]) + seeds[i] * 100
            dvx += sin(phase) * turbulenceGain * drivers.turbulence
            dvy += cos(phase * 1.27) * turbulenceGain * drivers.turbulence

            // Steer current velocity toward desired, then clamp its magnitude.
            var vx = Double(velocities[i].dx), vy = Double(velocities[i].dy)
            vx += (dvx - vx) * steer
            vy += (dvy - vy) * steer
            let sp = (vx * vx + vy * vy).squareRoot()
            if sp > maxSpeed { vx *= maxSpeed / sp; vy *= maxSpeed / sp }
            velocities[i] = CGVector(dx: vx, dy: vy)

            positions[i] = CGPoint(x: wrap01(x + vx * dt), y: wrap01(y + vy * dt))
        }
    }

    private func wrap01(_ v: Double) -> Double {
        let r = v.truncatingRemainder(dividingBy: 1)
        return r < 0 ? r + 1 : r
    }
}
