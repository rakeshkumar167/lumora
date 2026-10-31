import CoreGraphics
import Foundation

/// Layout of the virtual running-bond brick grid shared by the Brick Wall
/// effects. Tune it so the projected bricks land on a real wall's bricks.
/// Codable; stored on `Surface`.
public struct BrickWallConfig: Equatable, Codable {
    /// Courses (rows of bricks) top to bottom.
    public var rows: Int
    /// Whole bricks per course.
    public var columns: Int
    /// Mortar joint thickness as a fraction of a course's height.
    public var mortar: Double
    /// Horizontal shift of every other course, as a fraction of a brick
    /// (0.5 = classic running bond, 0 = stack bond).
    public var stagger: Double

    public init(rows: Int = 14, columns: Int = 6, mortar: Double = 0.14, stagger: Double = 0.5) {
        self.rows = rows
        self.columns = columns
        self.mortar = mortar
        self.stagger = stagger
    }

    private enum CodingKeys: String, CodingKey { case rows, columns, mortar, stagger }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? 14
        columns = try c.decodeIfPresent(Int.self, forKey: .columns) ?? 6
        mortar = try c.decodeIfPresent(Double.self, forKey: .mortar) ?? 0.14
        stagger = try c.decodeIfPresent(Double.self, forKey: .stagger) ?? 0.5
    }
}

/// One brick of a `BrickGrid`: its course (0 = top), index within the course,
/// and its face rectangle (mortar already removed). Edge bricks of a staggered
/// course are cut to the surface, like real half bricks.
public struct Brick: Equatable {
    public var row: Int
    public var index: Int
    public var rect: CGRect
    /// A stable per-brick id, handy for seeding hashes.
    public var id: Int

    public var center: CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
}

/// Pure geometry for a running-bond wall filling `size`.
public struct BrickGrid {
    public let size: CGSize
    public let rows: Int
    public let columns: Int
    public let courseHeight: CGFloat
    public let brickWidth: CGFloat
    /// Mortar thickness in points.
    public let joint: CGFloat
    public let bricks: [Brick]

    public init(size: CGSize, config: BrickWallConfig) {
        self.size = size
        rows = max(1, config.rows)
        columns = max(1, config.columns)
        courseHeight = size.height / CGFloat(rows)
        brickWidth = size.width / CGFloat(columns)
        joint = max(0.5, courseHeight * CGFloat(min(max(config.mortar, 0), 0.6)))
        let half = joint / 2
        let shift = brickWidth * CGFloat(config.stagger.truncatingRemainder(dividingBy: 1))

        var out: [Brick] = []
        out.reserveCapacity(rows * (columns + 1))
        for r in 0..<rows {
            let y0 = CGFloat(r) * courseHeight
            // Odd courses shift left by `shift`, so they start with a partial brick.
            let offset = r % 2 == 1 ? -shift : 0
            var i = 0
            var x = offset
            while x < size.width - 0.5 {
                let left = max(0, x), right = min(size.width, x + brickWidth)
                if right - left > joint * 2 {
                    let rect = CGRect(x: left + half, y: y0 + half,
                                      width: right - left - joint, height: courseHeight - joint)
                    out.append(Brick(row: r, index: i, rect: rect, id: r * 1000 + i))
                    i += 1
                }
                x += brickWidth
            }
        }
        bricks = out
    }
}
