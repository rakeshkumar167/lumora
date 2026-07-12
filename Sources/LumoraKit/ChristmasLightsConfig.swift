import Foundation

/// Customization for the Christmas string-light effects (chasing / multi-colour
/// / twinkling / warm bulbs — not the tree). Codable so it persists with a
/// project; stored on `Surface`.
public struct ChristmasLightsConfig: Equatable, Codable {
    /// Total number of bulbs across the string.
    public var bulbCount: Int
    /// Number of drooping swags (arcs) the wire makes across the width.
    public var sagCount: Int

    public init(bulbCount: Int = 16, sagCount: Int = 1) {
        self.bulbCount = bulbCount
        self.sagCount = sagCount
    }
}
