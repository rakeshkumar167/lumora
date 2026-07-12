import Foundation

/// Customization for the Christmas string-light effects (chasing / multi-colour
/// / twinkling / warm bulbs — not the tree). Codable so it persists with a
/// project; stored on `Surface`.
public struct ChristmasLightsConfig: Equatable, Codable {
    /// Total number of bulbs across the string.
    public var bulbCount: Int
    /// Number of drooping swags (arcs) the wire makes across the width.
    public var sagCount: Int
    /// Bulb-size multiplier applied to the width-driven default radius.
    public var bulbScale: Double

    public init(bulbCount: Int = 16, sagCount: Int = 1, bulbScale: Double = 1.0) {
        self.bulbCount = bulbCount
        self.sagCount = sagCount
        self.bulbScale = bulbScale
    }

    private enum CodingKeys: String, CodingKey { case bulbCount, sagCount, bulbScale }

    // Tolerant decode so a config saved before a field existed still loads.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bulbCount = try c.decodeIfPresent(Int.self, forKey: .bulbCount) ?? 16
        sagCount = try c.decodeIfPresent(Int.self, forKey: .sagCount) ?? 1
        bulbScale = try c.decodeIfPresent(Double.self, forKey: .bulbScale) ?? 1.0
    }
}
