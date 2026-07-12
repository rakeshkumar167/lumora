import CoreGraphics

/// Which detector proposed a quad.
public enum QuadSource: String, Codable, Equatable {
    case plane   // region segmentation (walls, floors)
    case object  // Vision rectangle (screens, doors, panels)
}

/// A candidate surface: a quad in normalized 0–1 top-left coordinates,
/// ordered TL, TR, BR, BL.
public struct DetectedQuad: Equatable {
    public var corners: [CGPoint]
    public var areaFraction: Double
    public var source: QuadSource

    public init(corners: [CGPoint], areaFraction: Double, source: QuadSource) {
        self.corners = corners
        self.areaFraction = areaFraction
        self.source = source
    }
}
