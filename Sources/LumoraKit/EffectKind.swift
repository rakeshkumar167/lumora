import Foundation

/// Built-in generative animations that can be assigned to a surface.
public enum EffectKind: String, Codable, CaseIterable, Identifiable {
    case grid
    case colorWash
    case gradientSweep
    case breathingGlow
    case rainbowSweep
    case radialPulse
    case checkerboard
    case waves
    case plasma
    case strobe
    case sparkle
    case barberStripes
    case colorBars
    case equalizer
    case starfieldWarp
    case neonGrid
    case vortex
    case aurora
    case fireflies
    case snow
    case lava
    case halftoneDots
    case moire
    case truchet
    case concentricPolygons
    case spirograph
    case fire
    case rain
    case lightning
    case bubbles
    case fallingLeaves
    case tvStatic
    case crtScanlines
    case matrixRain
    case glitch
    case pixelDissolve
    case tunnel
    case pendulumWave
    case dvdBounce
    case kaleidoscope
    case marqueeText

    public var id: String { rawValue }

    /// Whether the effect uses the surface's primary color.
    public var usesColor: Bool {
        switch self {
        case .colorWash, .rainbowSweep, .colorBars, .starfieldWarp, .aurora, .tvStatic:
            return false
        default:
            return true
        }
    }

    /// Whether the effect uses a second (accent) color.
    public var usesAccent: Bool {
        switch self {
        case .grid, .gradientSweep, .breathingGlow, .radialPulse, .checkerboard, .waves,
             .plasma, .strobe, .barberStripes, .equalizer, .neonGrid, .vortex,
             .halftoneDots, .truchet, .concentricPolygons, .fire, .lightning,
             .bubbles, .fallingLeaves, .matrixRain, .pixelDissolve, .tunnel, .dvdBounce,
             .kaleidoscope, .marqueeText:
            return true
        default:
            return false
        }
    }

    public var displayName: String {
        switch self {
        case .grid: return "Grid"
        case .colorWash: return "Color Wash"
        case .gradientSweep: return "Gradient Sweep"
        case .breathingGlow: return "Breathing Glow"
        case .rainbowSweep: return "Rainbow Sweep"
        case .radialPulse: return "Radial Pulse"
        case .checkerboard: return "Checkerboard"
        case .waves: return "Waves"
        case .plasma: return "Plasma"
        case .strobe: return "Strobe"
        case .sparkle: return "Sparkle"
        case .barberStripes: return "Barber Stripes"
        case .colorBars: return "Color Bars"
        case .equalizer: return "Equalizer Bars"
        case .starfieldWarp: return "Starfield Warp"
        case .neonGrid: return "Neon Grid"
        case .vortex: return "Vortex"
        case .aurora: return "Aurora"
        case .fireflies: return "Fireflies"
        case .snow: return "Snow"
        case .lava: return "Lava Lamp"
        case .halftoneDots: return "Halftone Dots"
        case .moire: return "Moiré"
        case .truchet: return "Truchet Tiles"
        case .concentricPolygons: return "Concentric Polygons"
        case .spirograph: return "Spirograph"
        case .fire: return "Fire"
        case .rain: return "Rain"
        case .lightning: return "Lightning"
        case .bubbles: return "Bubbles"
        case .fallingLeaves: return "Falling Leaves"
        case .tvStatic: return "TV Static"
        case .crtScanlines: return "CRT Scanlines"
        case .matrixRain: return "Matrix Rain"
        case .glitch: return "Glitch"
        case .pixelDissolve: return "Pixel Dissolve"
        case .tunnel: return "Tunnel"
        case .pendulumWave: return "Pendulum Wave"
        case .dvdBounce: return "DVD Bounce"
        case .kaleidoscope: return "Kaleidoscope"
        case .marqueeText: return "Marquee Text"
        }
    }
}
