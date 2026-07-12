import Foundation

/// Customization for the Game of Life effect. Codable; stored on `Surface`.
public struct GameOfLifeConfig: Equatable, Codable {
    /// Generations advanced per second (speed).
    public var genPerSecond: Double
    /// Cell size in points.
    public var cellSize: Double

    public init(genPerSecond: Double = 4, cellSize: Double = 18) {
        self.genPerSecond = genPerSecond
        self.cellSize = cellSize
    }

    private enum CodingKeys: String, CodingKey { case genPerSecond, cellSize }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        genPerSecond = try c.decodeIfPresent(Double.self, forKey: .genPerSecond) ?? 4
        cellSize = try c.decodeIfPresent(Double.self, forKey: .cellSize) ?? 18
    }
}
