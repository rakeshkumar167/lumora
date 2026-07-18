import CoreGraphics
import Foundation

/// Direction an ivy vine creeps across the surface (top-left origin, y grows down).
public enum IvyDirection: String, Codable, CaseIterable, Equatable {
    case topDown, bottomUp, leftToRight, rightToLeft

    public var displayName: String {
        switch self {
        case .topDown: return "Top → Down"
        case .bottomUp: return "Bottom → Up"
        case .leftToRight: return "Left → Right"
        case .rightToLeft: return "Right → Left"
        }
    }

    /// Unit growth vector.
    public var growth: CGVector {
        switch self {
        case .topDown: return CGVector(dx: 0, dy: 1)
        case .bottomUp: return CGVector(dx: 0, dy: -1)
        case .leftToRight: return CGVector(dx: 1, dy: 0)
        case .rightToLeft: return CGVector(dx: -1, dy: 0)
        }
    }
}

/// Customization for the Growing Ivy effect. Codable; stored on `Surface`.
public struct GrowingIvyConfig: Equatable, Codable {
    public var direction: IvyDirection

    public init(direction: IvyDirection = .topDown) {
        self.direction = direction
    }

    private enum CodingKeys: String, CodingKey { case direction }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        direction = try c.decodeIfPresent(IvyDirection.self, forKey: .direction) ?? .topDown
    }
}
