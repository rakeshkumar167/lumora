import Foundation

/// Customization for the 3D effects (torus / sphere / point cloud). Codable;
/// stored on `Surface`.
public struct ThreeDConfig: Equatable, Codable {
    /// Movement/rotation speed multiplier.
    public var speed: Double
    /// Point Cloud: rainbow hue vs. the surface's primary colour.
    public var rainbow: Bool

    public init(speed: Double = 1.0, rainbow: Bool = true) {
        self.speed = speed
        self.rainbow = rainbow
    }

    private enum CodingKeys: String, CodingKey { case speed, rainbow }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1.0
        rainbow = try c.decodeIfPresent(Bool.self, forKey: .rainbow) ?? true
    }
}
