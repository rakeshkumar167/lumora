import Foundation

/// The geometric kind of a projection surface.
///
/// - `quad`: exactly four corners, perspective-warped via `Homography`.
/// - `polygon`: three or more points; media is clipped to the outline (no warp).
/// - `ellipse`: media is clipped to an ellipse inscribed in the points' bounds.
public enum SurfaceShape: String, Codable, CaseIterable, Identifiable {
    case quad
    case polygon
    case ellipse

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .quad: return "Quad"
        case .polygon: return "Polygon"
        case .ellipse: return "Ellipse"
        }
    }

    /// Whether this shape is perspective-warped (only true quads can be).
    public var isWarped: Bool { self == .quad }
}
