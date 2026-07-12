import Foundation

/// One scene in a project: its own surfaces, light lines, and how long it plays
/// before the projection advances to the next scene. Named `ProjectScene` (not
/// `Scene`) to avoid clashing with SwiftUI's `Scene` in the app target.
public struct ProjectScene: Identifiable, Equatable, Codable {
    public var id: UUID
    public var name: String
    public var surfaces: [Surface]
    public var lightLines: [LightLine]
    /// Seconds this scene plays during projection.
    public var duration: TimeInterval

    public init(id: UUID = UUID(), name: String,
                surfaces: [Surface] = [], lightLines: [LightLine] = [],
                duration: TimeInterval = 15) {
        self.id = id
        self.name = name
        self.surfaces = surfaces
        self.lightLines = lightLines
        self.duration = duration
    }

    /// Surfaces ordered for compositing: lower `zIndex` first (drawn behind),
    /// ties keep array order (stable).
    public var surfacesInDrawOrder: [Surface] {
        let indexed = Array(surfaces.enumerated())
        let sorted = indexed.sorted { lhs, rhs in
            if lhs.element.zIndex != rhs.element.zIndex {
                return lhs.element.zIndex < rhs.element.zIndex
            }
            return lhs.offset < rhs.offset
        }
        return sorted.map { $0.element }
    }

    private enum CodingKeys: String, CodingKey { case id, name, surfaces, lightLines, duration }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Scene"
        surfaces = try c.decodeIfPresent([Surface].self, forKey: .surfaces) ?? []
        lightLines = try c.decodeIfPresent([LightLine].self, forKey: .lightLines) ?? []
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 15
    }
}
