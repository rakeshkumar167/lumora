import CoreGraphics
import Foundation

/// A projection surface: a shape in normalized room space with assigned media.
///
/// `points` are normalized (0...1) room-space vertices. For a `.quad` they are
/// the four corners in order TL, TR, BR, BL (perspective-warped). For a
/// `.polygon` they are N vertices; for an `.ellipse` they bound the oval. Media
/// is warped (quad) or clipped to the outline (polygon/ellipse).
public struct Surface: Identifiable, Equatable, Codable {
    public var id: UUID
    public var name: String
    public var points: [CGPoint]
    public var shape: SurfaceShape
    /// Rotation about the shape's center, in radians.
    public var rotation: Double
    public var media: MediaAssignment
    public var isVisible: Bool
    public var opacity: Double
    /// Draw order: higher draws on top. Default 10; may be positive or negative.
    public var zIndex: Int
    /// Customization for the Marquee Text effect (nil = defaults).
    public var marquee: MarqueeConfig?
    /// Customization for the Christmas string-light effects (nil = defaults).
    public var christmasLights: ChristmasLightsConfig?
    /// Customization for the Game of Life effect (nil = defaults).
    public var gameOfLife: GameOfLifeConfig?
    /// Customization for the Falling Leaves effect (nil = defaults).
    public var fallingLeaves: FallingLeavesConfig?

    public init(
        id: UUID = UUID(),
        name: String,
        points: [CGPoint],
        shape: SurfaceShape = .quad,
        rotation: Double = 0,
        media: MediaAssignment = .color(.teal),
        isVisible: Bool = true,
        opacity: Double = 1,
        zIndex: Int = 10,
        marquee: MarqueeConfig? = nil,
        christmasLights: ChristmasLightsConfig? = nil,
        gameOfLife: GameOfLifeConfig? = nil,
        fallingLeaves: FallingLeavesConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.points = points
        self.shape = shape
        self.rotation = rotation
        self.media = media
        self.isVisible = isVisible
        self.opacity = opacity
        self.zIndex = zIndex
        self.marquee = marquee
        self.christmasLights = christmasLights
        self.gameOfLife = gameOfLife
        self.fallingLeaves = fallingLeaves
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, points, shape, rotation, media, isVisible, opacity, zIndex, marquee, christmasLights, gameOfLife, fallingLeaves
    }

    // Custom decode so older `.lumora` files (saved before `shape`/`rotation`
    // existed) still load, defaulting sensibly. Encoding stays synthesized.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        points = try c.decode([CGPoint].self, forKey: .points)
        shape = try c.decodeIfPresent(SurfaceShape.self, forKey: .shape) ?? .quad
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        media = try c.decode(MediaAssignment.self, forKey: .media)
        isVisible = try c.decode(Bool.self, forKey: .isVisible)
        opacity = try c.decode(Double.self, forKey: .opacity)
        zIndex = try c.decodeIfPresent(Int.self, forKey: .zIndex) ?? 10
        marquee = try c.decodeIfPresent(MarqueeConfig.self, forKey: .marquee)
        christmasLights = try c.decodeIfPresent(ChristmasLightsConfig.self, forKey: .christmasLights)
        gameOfLife = try c.decodeIfPresent(GameOfLifeConfig.self, forKey: .gameOfLife)
        fallingLeaves = try c.decodeIfPresent(FallingLeavesConfig.self, forKey: .fallingLeaves)
    }

    /// The shape's center (normalized), used as the rotation pivot.
    public var center: CGPoint {
        let b = Surface.bounds(of: points)
        return CGPoint(x: b.midX, y: b.midY)
    }

    /// `points` after applying `rotation` about `center` (normalized).
    public var displayPoints: [CGPoint] {
        guard rotation != 0 else { return points }
        let c = center
        let cs = CGFloat(CoreGraphics.cos(rotation))
        let sn = CGFloat(CoreGraphics.sin(rotation))
        return points.map { p in
            let dx = p.x - c.x, dy = p.y - c.y
            return CGPoint(x: c.x + dx * cs - dy * sn, y: c.y + dx * sn + dy * cs)
        }
    }

    /// Base corner points scaled into a canvas of the given pixel size.
    public func quadPoints(in size: CGSize) -> [CGPoint] {
        points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
    }

    /// Rotation-applied corner points scaled into a canvas of the given size.
    public func displayQuadPoints(in size: CGSize) -> [CGPoint] {
        displayPoints.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
    }

    // MARK: - Geometry helpers

    /// The default location/size for a new surface (normalized).
    public static let defaultBounds = CGRect(x: 0.35, y: 0.32, width: 0.30, height: 0.36)

    /// Axis-aligned bounding box of a set of points.
    public static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return defaultBounds }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points {
            minX = Swift.min(minX, p.x); minY = Swift.min(minY, p.y)
            maxX = Swift.max(maxX, p.x); maxY = Swift.max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The four corners of a rectangle, in TL, TR, BR, BL order.
    public static func rectCorners(_ b: CGRect) -> [CGPoint] {
        [
            CGPoint(x: b.minX, y: b.minY),
            CGPoint(x: b.maxX, y: b.minY),
            CGPoint(x: b.maxX, y: b.maxY),
            CGPoint(x: b.minX, y: b.maxY),
        ]
    }

    /// Vertices of a regular polygon inscribed in `b` (first vertex at top).
    public static func polygonCorners(_ b: CGRect, sides: Int) -> [CGPoint] {
        let n = Swift.max(3, sides)
        let cx = b.midX, cy = b.midY
        let rx = b.width / 2, ry = b.height / 2
        return (0..<n).map { i in
            let a = -Double.pi / 2 + Double(i) / Double(n) * 2 * .pi
            return CGPoint(x: cx + rx * CoreGraphics.cos(a), y: cy + ry * CoreGraphics.sin(a))
        }
    }

    // MARK: - Constructors

    /// A centered rectangle occupying the middle of the room.
    public static func defaultRect(name: String) -> Surface {
        Surface(name: name, points: rectCorners(defaultBounds), shape: .quad)
    }

    /// A centered regular polygon.
    public static func regularPolygon(name: String, sides: Int) -> Surface {
        Surface(name: name, points: polygonCorners(defaultBounds, sides: sides), shape: .polygon)
    }

    /// A centered ellipse (bounds defined by four points).
    public static func defaultEllipse(name: String) -> Surface {
        Surface(name: name, points: rectCorners(defaultBounds), shape: .ellipse)
    }
}
