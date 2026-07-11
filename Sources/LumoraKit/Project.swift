import Foundation

/// A saveable project: the ordered set of surfaces plus light line networks.
/// The room reference photo is managed by the app layer.
public struct Project: Codable, Equatable {
    public var surfaces: [Surface]
    public var lightLines: [LightLine]

    public init(surfaces: [Surface] = [], lightLines: [LightLine] = []) {
        self.surfaces = surfaces
        self.lightLines = lightLines
    }

    private enum CodingKeys: String, CodingKey {
        case surfaces, lightLines
    }

    // Custom decode so older `.lumora` files (saved before `lightLines`
    // existed) still load. Encoding stays synthesized.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        surfaces = try c.decode([Surface].self, forKey: .surfaces)
        lightLines = try c.decodeIfPresent([LightLine].self, forKey: .lightLines) ?? []
    }
}
