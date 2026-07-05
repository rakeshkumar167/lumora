import Foundation

/// Built-in generative animations that can be assigned to a surface.
public enum EffectKind: String, Codable, CaseIterable, Identifiable {
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

    public var id: String { rawValue }

    /// Whether the effect uses the surface's primary color.
    public var usesColor: Bool {
        switch self {
        case .colorWash, .rainbowSweep, .colorBars, .starfieldWarp, .aurora:
            return false
        default:
            return true
        }
    }

    /// Whether the effect uses a second (accent) color.
    public var usesAccent: Bool {
        switch self {
        case .gradientSweep, .breathingGlow, .radialPulse, .checkerboard, .waves,
             .plasma, .strobe, .barberStripes, .equalizer, .neonGrid, .vortex:
            return true
        default:
            return false
        }
    }

    public var displayName: String {
        switch self {
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
        }
    }
}
