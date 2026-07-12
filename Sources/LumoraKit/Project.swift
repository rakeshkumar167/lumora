import Foundation

/// A saveable project: an ordered list of scenes. Each scene carries its own
/// surfaces and light lines. The room reference photo is managed by the app.
public struct Project: Codable, Equatable {
    public var scenes: [ProjectScene]

    public init(scenes: [ProjectScene]) {
        self.scenes = scenes.isEmpty ? [ProjectScene(name: "Scene 1")] : scenes
    }

    /// Convenience for a single-scene project (used by the sample + tests).
    public init(surfaces: [Surface] = [], lightLines: [LightLine] = []) {
        self.scenes = [ProjectScene(name: "Scene 1", surfaces: surfaces, lightLines: lightLines)]
    }

    private enum CodingKeys: String, CodingKey { case scenes, surfaces, lightLines }

    // Backward-compatible decode: older `.lumora` files stored flat
    // `surfaces` / `lightLines` with no `scenes` — load them as one scene.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let scenes = try c.decodeIfPresent([ProjectScene].self, forKey: .scenes), !scenes.isEmpty {
            self.scenes = scenes
        } else {
            let surfaces = try c.decodeIfPresent([Surface].self, forKey: .surfaces) ?? []
            let lightLines = try c.decodeIfPresent([LightLine].self, forKey: .lightLines) ?? []
            self.scenes = [ProjectScene(name: "Scene 1", surfaces: surfaces, lightLines: lightLines)]
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(scenes, forKey: .scenes)
    }
}
