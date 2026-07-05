import Foundation

/// A saveable project: the ordered set of surfaces (geometry + media + playback
/// settings). The room reference photo is managed by the app layer.
public struct Project: Codable, Equatable {
    public var surfaces: [Surface]

    public init(surfaces: [Surface] = []) {
        self.surfaces = surfaces
    }
}
