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
    case particleSwarm
    case audioParticles
    case butterflies
    case tvStatic
    case matrixRain
    case pixelDissolve
    case tunnel
    case dvdBounce
    case kaleidoscope
    case marqueeText
    case prismFalls
    case liquidSlosh
    case pendulumPaint
    case voronoi
    case metaballs
    case hexGrid
    case stainedGlass
    case vectorGrid
    case particleMesh
    case livingTexture
    case gameOfLife
    case flowingPlasma
    case reactionDiffusion
    case driftingNebula
    case perlinFlow
    case circuitTrace
    case caustics
    case infiniteKaleidoscope
    case mandalaExpansion
    case sacredGeometry
    case fractalZoom
    case tessellationMorph
    case torus3D
    case sphere3D
    case pointCloud3D
    case strangeAttractor
    case dnaHelix
    case outlineGlow
    case growingIvy
    case analogClock
    case digitalClock
    case weatherWidget
    case christmasTree
    case chasingLights
    case multiColorLights
    case twinklingLights
    case warmBulbs
    /// Chladni plate resonance patterns. Renderer/category/displayName land in
    /// Task 7; this task only adds the case so `supportsAudio` is exhaustive.
    case chladni
    case hilbertCurve
    case godRays
    case inkFlow
    case mazeSolve

    public var id: String { rawValue }

    /// Whether the effect uses the surface's primary color.
    public var usesColor: Bool {
        switch self {
        case .colorWash, .rainbowSweep, .colorBars, .starfieldWarp, .aurora, .tvStatic, .prismFalls,
             .voronoi, .vectorGrid, .livingTexture, .gameOfLife, .flowingPlasma, .fire, .bubbles, .fireworks,
             .christmasTree, .chasingLights, .multiColorLights, .twinklingLights, .warmBulbs,
             .weatherWidget,
             .infiniteKaleidoscope, .mandalaExpansion, .sacredGeometry, .fractalZoom, .tessellationMorph,
             .torus3D, .sphere3D, .pointCloud3D, .strangeAttractor, .dnaHelix, .pendulumPaint, .hilbertCurve, .stainedGlass:
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
             .reactionDiffusion, .driftingNebula, .perlinFlow, .circuitTrace, .caustics,
             .particleSwarm, .audioParticles, .butterflies,
             .outlineGlow, .growingIvy, .analogClock, .digitalClock, .inkFlow, .mazeSolve:
            return true
        default:
            return false
        }
    }

    /// Whether this effect can react to live microphone audio when the
    /// surface's Audio Reactive toggle is on. (`audioParticles` is inherently
    /// audio and is excluded — it has no toggle.)
    public var supportsAudio: Bool {
        switch self {
        case .equalizer, .strobe, .liquidSlosh, .aurora, .plasma, .chladni:
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
        case .particleSwarm: return "Particle Swarm"
        case .audioParticles: return "Audio Reactive Particles"
        case .butterflies: return "Butterflies"
        case .tvStatic: return "TV Static"
        case .matrixRain: return "Matrix Rain"
        case .pixelDissolve: return "Pixel Dissolve"
        case .tunnel: return "Tunnel"
        case .dvdBounce: return "DVD Bounce"
        case .kaleidoscope: return "Kaleidoscope"
        case .marqueeText: return "Marquee Text"
        case .prismFalls: return "Prism Falls"
        case .liquidSlosh: return "Liquid Slosh"
        case .pendulumPaint: return "Pendulum Paint"
        case .voronoi: return "Voronoi Cells"
        case .metaballs: return "Metaballs"
        case .hexGrid: return "Hex Grid"
        case .stainedGlass: return "Stained Glass"
        case .vectorGrid: return "Vector Grid"
        case .particleMesh: return "Particle Mesh"
        case .livingTexture: return "Living Texture"
        case .gameOfLife: return "Game of Life"
        case .flowingPlasma: return "Flowing Plasma"
        case .reactionDiffusion: return "Reaction Diffusion"
        case .driftingNebula: return "Drifting Nebula"
        case .perlinFlow: return "Perlin Flow Field"
        case .circuitTrace: return "Circuit Trace"
        case .caustics: return "Water Caustics"
        case .infiniteKaleidoscope: return "Infinite Kaleidoscope"
        case .mandalaExpansion: return "Mandala Expansion"
        case .sacredGeometry: return "Sacred Geometry"
        case .fractalZoom: return "Recursive Fractal Zoom"
        case .tessellationMorph: return "Tessellation Morph"
        case .torus3D: return "3D Torus"
        case .sphere3D: return "3D Sphere"
        case .pointCloud3D: return "3D Point Cloud"
        case .strangeAttractor: return "Strange Attractor"
        case .dnaHelix: return "DNA Helix"
        case .outlineGlow: return "Outline Glow"
        case .growingIvy: return "Growing Ivy"
        case .analogClock: return "Analog Clock"
        case .digitalClock: return "Digital Clock & Weather"
        case .weatherWidget: return "Weather Widget"
        case .christmasTree: return "Christmas Tree"
        case .chasingLights: return "Chasing Lights"
        case .multiColorLights: return "Multi-Colored Lights"
        case .twinklingLights: return "Twinkling Lights"
        case .warmBulbs: return "Warm Round Bulbs"
        case .chladni: return "Chladni"
        case .hilbertCurve: return "Hilbert Curve"
        case .godRays: return "God Rays"
        case .inkFlow: return "Ink in Water"
        case .mazeSolve: return "Maze Solve"
        }
    }

    /// The category this effect belongs to, used to group the picker.
    public var category: EffectCategory {
        switch self {
        case .grid, .colorWash, .gradientSweep, .breathingGlow, .rainbowSweep,
             .radialPulse, .aurora, .plasma, .strobe:
            return .gradients
        case .checkerboard, .barberStripes, .colorBars, .halftoneDots,
             .truchet, .concentricPolygons,
             .infiniteKaleidoscope, .mandalaExpansion, .sacredGeometry, .fractalZoom, .tessellationMorph,
             .chladni, .hilbertCurve, .mazeSolve:
            return .patterns
        case .sparkle, .starfieldWarp, .fireflies, .snow, .lava, .fire, .rain,
             .lightning, .bubbles, .fallingLeaves, .fireworks,
             .particleSwarm, .audioParticles, .butterflies:
            return .nature
        case .waves, .equalizer, .tunnel, .kaleidoscope,
             .prismFalls, .liquidSlosh, .pendulumPaint:
            return .motion
        case .tvStatic, .matrixRain, .pixelDissolve,
             .dvdBounce, .marqueeText:
            return .retro
        case .voronoi, .metaballs, .hexGrid, .stainedGlass:
            return .fields
        case .vectorGrid, .particleMesh:
            return .curvesGrids
        case .livingTexture, .gameOfLife, .flowingPlasma, .reactionDiffusion, .driftingNebula, .perlinFlow, .circuitTrace, .caustics, .godRays, .inkFlow:
            return .ambient
        case .torus3D, .sphere3D, .pointCloud3D, .strangeAttractor, .dnaHelix:
            return .threeD
        case .outlineGlow, .growingIvy:
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
    case threeD
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
        case .threeD: return "3D"
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
