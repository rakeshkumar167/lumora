import CoreGraphics

/// A traced region boundary with optional nesting parent.
public struct Contour: Equatable {
    public var points: [CGPoint]
    public var parentIndex: Int?
    public init(points: [CGPoint], parentIndex: Int? = nil) {
        self.points = points; self.parentIndex = parentIndex
    }
}
