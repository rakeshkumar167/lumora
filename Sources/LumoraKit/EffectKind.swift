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
    case aurora
    case fireflies
    case snow
    case lava
    case halftoneDots
    case truchet
    case concentricPolygons
    case fire
    case rain
    case lightning
    case bubbles
    case fallingLeaves
    case fireworks
    case tvStatic
    case matrixRain
    case pixelDissolve
    case tunnel
    case dvdBounce
    case kaleidoscope
    case marqueeText
    case prismFalls
    case liquidSlosh
    case voronoi
    case metaballs
    case hexGrid
    case vectorGrid
    case particleMesh
    case livingTexture
    case outlineGlow
    case analogClock
    case digitalClock
    case weatherWidget
    case christmasTree
    case chasingLights
    case multiColorLights
    case twinklingLights
    case warmBulbs

    public var id: String { rawValue }

    /// Whether the effect uses the surface's primary color.
    public var usesColor: Bool {
        switch self {
        case .colorWash, .rainbowSweep, .colorBars, .starfieldWarp, .aurora, .tvStatic, .prismFalls,
             .voronoi, .vectorGrid, .livingTexture, .fire, .bubbles, .fireworks,
             .christmasTree, .chasingLights, .multiColorLights, .twinklingLights, .warmBulbs,
             .weatherWidget:
            return false
        default:
            return true
        }
    }

    /// Whether the effect uses a second (accent) color.
    public var usesAccent: Bool {
        switch self {
        case .grid, .gradientSweep, .breathingGlow, .radialPulse, .checkerboard, .waves,
             .plasma, .strobe, .barberStripes, .equalizer,
             .halftoneDots, .truchet, .concentricPolygons, .lightning,
             .fallingLeaves, .matrixRain, .pixelDissolve, .tunnel, .dvdBounce,
             .kaleidoscope, .marqueeText, .liquidSlosh, .metaballs, .hexGrid, .particleMesh,
             .outlineGlow, .analogClock, .digitalClock:
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
        case .aurora: return "Aurora"
        case .fireflies: return "Fireflies"
        case .snow: return "Snow"
        case .lava: return "Lava Lamp"
        case .halftoneDots: return "Halftone Dots"
        case .truchet: return "Truchet Tiles"
        case .concentricPolygons: return "Concentric Polygons"
        case .fire: return "Fire"
        case .rain: return "Rain"
        case .lightning: return "Lightning"
        case .bubbles: return "Bubbles"
        case .fallingLeaves: return "Falling Leaves"
        case .fireworks: return "Fireworks"
        case .tvStatic: return "TV Static"
        case .matrixRain: return "Matrix Rain"
        case .pixelDissolve: return "Pixel Dissolve"
        case .tunnel: return "Tunnel"
        case .dvdBounce: return "DVD Bounce"
        case .kaleidoscope: return "Kaleidoscope"
        case .marqueeText: return "Marquee Text"
        case .prismFalls: return "Prism Falls"
        case .liquidSlosh: return "Liquid Slosh"
        case .voronoi: return "Voronoi Cells"
        case .metaballs: return "Metaballs"
        case .hexGrid: return "Hex Grid"
        case .vectorGrid: return "Vector Grid"
        case .particleMesh: return "Particle Mesh"
        case .livingTexture: return "Living Texture"
        case .outlineGlow: return "Outline Glow"
        case .analogClock: return "Analog Clock"
        case .digitalClock: return "Digital Clock & Weather"
        case .weatherWidget: return "Weather Widget"
        case .christmasTree: return "Christmas Tree"
        case .chasingLights: return "Chasing Lights"
        case .multiColorLights: return "Multi-Colored Lights"
        case .twinklingLights: return "Twinkling Lights"
        case .warmBulbs: return "Warm Round Bulbs"
        }
    }

    /// The category this effect belongs to, used to group the picker.
    public var category: EffectCategory {
        switch self {
        case .grid, .colorWash, .gradientSweep, .breathingGlow, .rainbowSweep,
             .radialPulse, .aurora, .plasma, .strobe:
            return .gradients
        case .checkerboard, .barberStripes, .colorBars, .halftoneDots,
             .truchet, .concentricPolygons:
            return .patterns
        case .sparkle, .starfieldWarp, .fireflies, .snow, .lava, .fire, .rain,
             .lightning, .bubbles, .fallingLeaves, .fireworks:
            return .nature
        case .waves, .equalizer, .tunnel, .kaleidoscope,
             .prismFalls, .liquidSlosh:
            return .motion
        case .tvStatic, .matrixRain, .pixelDissolve,
             .dvdBounce, .marqueeText:
            return .retro
        case .voronoi, .metaballs, .hexGrid:
            return .fields
        case .vectorGrid, .particleMesh:
            return .curvesGrids
        case .livingTexture:
            return .ambient
        case .outlineGlow:
            return .edge
        case .analogClock, .digitalClock, .weatherWidget:
            return .clocks
        case .christmasTree, .chasingLights, .multiColorLights, .twinklingLights, .warmBulbs:
            return .christmas
        }
    }
}

/// A grouping of related effects, used to make the effect picker a two-step
/// Category → Effect selection. Cases mirror the per-category renderer groups.
public enum EffectCategory: String, Codable, CaseIterable, Identifiable {
    case gradients
    case patterns
    case nature
    case motion
    case retro
    case fields
    case curvesGrids
    case ambient
    case edge
    case clocks
    case christmas

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gradients: return "Gradients & Washes"
        case .patterns: return "Patterns & Geometry"
        case .nature: return "Particles & Nature"
        case .motion: return "Waves & Motion"
        case .retro: return "Retro & Digital"
        case .fields: return "Fields"
        case .curvesGrids: return "Curves & Grids"
        case .ambient: return "Ambient & Illusion"
        case .edge: return "Edge"
        case .clocks: return "Clocks & Info"
        case .christmas: return "Christmas Lights"
        }
    }

    /// Effects in this category, in canonical `EffectKind` order.
    public var effects: [EffectKind] {
        EffectKind.allCases.filter { $0.category == self }
    }
}
