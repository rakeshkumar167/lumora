import Foundation

/// Ring motif family for the Rangoli Bloom effect.
public enum RangoliStyle: String, Codable, CaseIterable, Equatable {
    case grand, lotus, peacock, star, kolam, paisley, chakra, spiral, yantra

    public var displayName: String {
        switch self {
        case .grand: return "Grand Mandala (mixed)"
        case .lotus: return "Lotus"
        case .peacock: return "Peacock Feathers"
        case .star: return "Star & Diamond"
        case .kolam: return "Kolam Line Work"
        case .paisley: return "Paisley Garden"
        case .chakra: return "Sun Chakra"
        case .spiral: return "Swirling Vortex"
        case .yantra: return "Sacred Yantra"
        }
    }
}

/// Colour set for the Rangoli Bloom effect.
public enum RangoliPalette: String, Codable, CaseIterable, Equatable {
    case marigold, jewel, pastel, sunset, neon

    public var displayName: String {
        switch self {
        case .marigold: return "Marigold & Magenta"
        case .jewel: return "Royal Jewel"
        case .pastel: return "Pastel Bloom"
        case .sunset: return "Sunset Fire"
        case .neon: return "Neon Festival"
        }
    }
}

/// Customization for the Rangoli Bloom effect. Codable; stored on `Surface`.
public struct RangoliConfig: Equatable, Codable {
    public var style: RangoliStyle
    public var palette: RangoliPalette
    /// Number of concentric rings (3…12).
    public var rings: Int
    /// Rotational symmetry of the innermost ring (6…24); outer rings scale up from it.
    public var symmetry: Int
    /// Animation speed multiplier (0.2…3).
    public var speed: Double
    /// Build ring-by-ring then fade and repeat (true) or stay fully formed (false).
    public var buildCycle: Bool
    /// A ring of lit diyas around the outer edge.
    public var diyaRing: Bool
    /// Glittering coloured-powder sparkle.
    public var sparkle: Bool
    /// Marigold petals drifting down over the pattern.
    public var fallingPetals: Bool
    /// Strength of the soft glow (0…1).
    public var glow: Double
    /// Living motion — petals unfurling, ripples and shimmer waves (0…1).
    public var motion: Double
    /// Small rotating rosettes filling the surface corners.
    public var cornerRosettes: Bool

    public init(style: RangoliStyle = .grand,
                palette: RangoliPalette = .marigold,
                rings: Int = 9,
                symmetry: Int = 12,
                speed: Double = 1,
                buildCycle: Bool = true,
                diyaRing: Bool = true,
                sparkle: Bool = true,
                fallingPetals: Bool = true,
                glow: Double = 0.6,
                motion: Double = 0.7,
                cornerRosettes: Bool = true) {
        self.style = style
        self.palette = palette
        self.rings = rings
        self.symmetry = symmetry
        self.speed = speed
        self.buildCycle = buildCycle
        self.diyaRing = diyaRing
        self.sparkle = sparkle
        self.fallingPetals = fallingPetals
        self.glow = glow
        self.motion = motion
        self.cornerRosettes = cornerRosettes
    }

    private enum CodingKeys: String, CodingKey {
        case style, palette, rings, symmetry, speed, buildCycle, diyaRing, sparkle, fallingPetals, glow, motion, cornerRosettes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RangoliConfig()
        style = try c.decodeIfPresent(RangoliStyle.self, forKey: .style) ?? d.style
        palette = try c.decodeIfPresent(RangoliPalette.self, forKey: .palette) ?? d.palette
        rings = min(12, max(3, try c.decodeIfPresent(Int.self, forKey: .rings) ?? d.rings))
        symmetry = min(24, max(6, try c.decodeIfPresent(Int.self, forKey: .symmetry) ?? d.symmetry))
        speed = min(3, max(0.2, try c.decodeIfPresent(Double.self, forKey: .speed) ?? d.speed))
        buildCycle = try c.decodeIfPresent(Bool.self, forKey: .buildCycle) ?? d.buildCycle
        diyaRing = try c.decodeIfPresent(Bool.self, forKey: .diyaRing) ?? d.diyaRing
        sparkle = try c.decodeIfPresent(Bool.self, forKey: .sparkle) ?? d.sparkle
        fallingPetals = try c.decodeIfPresent(Bool.self, forKey: .fallingPetals) ?? d.fallingPetals
        glow = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .glow) ?? d.glow))
        motion = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .motion) ?? d.motion))
        cornerRosettes = try c.decodeIfPresent(Bool.self, forKey: .cornerRosettes) ?? d.cornerRosettes
    }
}
