import Foundation

/// Customization for the Pendulum Paint effect. Codable; stored on `Surface`.
public struct PaintDripConfig: Equatable, Codable {
    /// When true, paint hue advances along the trail (spectrum ribbons). When
    /// false, the surface's primary color is used with per-layer lightness
    /// variation.
    public var rainbow: Bool

    public init(rainbow: Bool = true) {
        self.rainbow = rainbow
    }

    private enum CodingKeys: String, CodingKey { case rainbow }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rainbow = try c.decodeIfPresent(Bool.self, forKey: .rainbow) ?? true
    }
}
