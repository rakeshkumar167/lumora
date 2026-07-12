import Foundation

/// Customization for the Falling Leaves effect. Codable; stored on `Surface`.
public struct FallingLeavesConfig: Equatable, Codable {
    /// Leaf-size multiplier applied to the base leaf size.
    public var leafScale: Double

    public init(leafScale: Double = 1.0) {
        self.leafScale = leafScale
    }

    private enum CodingKeys: String, CodingKey { case leafScale }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        leafScale = try c.decodeIfPresent(Double.self, forKey: .leafScale) ?? 1.0
    }
}
