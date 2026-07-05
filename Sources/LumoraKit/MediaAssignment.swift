import Foundation

/// What a surface displays. Codable so projects can be saved/reopened.
public enum MediaAssignment: Equatable, Codable {
    case none
    case color(RGBAColor)
    case effect(EffectKind, RGBAColor, RGBAColor)   // primary, accent
    case image(URL)
    case video(URL)

    public var label: String {
        switch self {
        case .none: return "None"
        case .color: return "Solid Color"
        case .effect(let kind, _, _): return kind.displayName
        case .image(let url): return url.lastPathComponent
        case .video(let url): return url.lastPathComponent
        }
    }
}
