import CoreGraphics
import Foundation

/// A projection surface: a quad in normalized room space with assigned media.
public struct Surface: Identifiable, Equatable, Codable {
    public var id: UUID
    public var name: String
    /// Four normalized corners (0...1) in room space, order: TL, TR, BR, BL.
    public var points: [CGPoint]
    public var media: MediaAssignment
    public var isVisible: Bool
    public var opacity: Double

    public init(
        id: UUID = UUID(),
        name: String,
        points: [CGPoint],
        media: MediaAssignment = .color(.teal),
        isVisible: Bool = true,
        opacity: Double = 1
    ) {
        self.id = id
        self.name = name
        self.points = points
        self.media = media
        self.isVisible = isVisible
        self.opacity = opacity
    }

    /// Corner points scaled into a canvas of the given pixel size.
    public func quadPoints(in size: CGSize) -> [CGPoint] {
        points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
    }

    /// A centered rectangle occupying the middle of the room.
    public static func defaultRect(name: String) -> Surface {
        Surface(name: name, points: [
            CGPoint(x: 0.35, y: 0.32),
            CGPoint(x: 0.65, y: 0.32),
            CGPoint(x: 0.65, y: 0.68),
            CGPoint(x: 0.35, y: 0.68),
        ])
    }
}
