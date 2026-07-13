import Foundation

/// The single modulation interface between a driver (time or audio) and the
/// particle simulation. Both effects produce one of these per frame; the
/// simulation and renderer never know which driver made it. Pure value type.
public struct SwarmDrivers: Equatable {
    /// Advection speed multiplier along the flow field.
    public var speed: Double
    /// Random per-particle jitter added to the flow.
    public var turbulence: Double
    /// Pull toward the drifting global attractors (the "school turns together"
    /// feel).
    public var cohesion: Double
    /// Burst energy — scales particle size / streak length; spikes on the beat.
    public var energy: Double
    /// Palette blend between the surface's primary and accent color (`0…1`).
    public var colorMix: Double
    /// Overall brightness (`0…1`).
    public var brightness: Double

    public init(speed: Double, turbulence: Double, cohesion: Double,
                energy: Double, colorMix: Double, brightness: Double) {
        self.speed = speed
        self.turbulence = turbulence
        self.cohesion = cohesion
        self.energy = energy
        self.colorMix = colorMix
        self.brightness = brightness
    }

    /// Gentle time-based defaults — Particle Swarm mode, and the fallback when
    /// the microphone is denied or silent.
    public static func idle(time: Double) -> SwarmDrivers {
        SwarmDrivers(
            speed: 1.0 + 0.25 * sin(time * 0.11),
            turbulence: 0.12,
            cohesion: 0.35 + 0.15 * sin(time * 0.07 + 1.3),
            energy: 0.35,
            colorMix: 0.5 + 0.5 * sin(time * 0.05),
            brightness: 0.85)
    }

    /// Audio Reactive Particles mode: bass drives speed + burst energy, mids
    /// drive turbulence, treble shifts the palette / adds sparkle, overall sets
    /// brightness. Monotonic in each band.
    public init(from levels: AudioLevels) {
        self.speed = 0.6 + 2.2 * levels.bass
        self.turbulence = 0.08 + 0.9 * levels.mid
        self.cohesion = 0.45 - 0.3 * levels.mid          // loud mids loosen the school
        self.energy = 0.25 + 1.6 * levels.bass
        self.colorMix = levels.treble
        self.brightness = 0.45 + 0.55 * levels.overall
    }
}
