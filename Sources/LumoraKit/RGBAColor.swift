import Foundation

/// UI-free color value stored in the model so the geometry core stays free of
/// any SwiftUI/AppKit dependency. Views bridge this to `Color`.
public struct RGBAColor: Equatable, Codable, Hashable {
    public var r, g, b, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public static let teal = RGBAColor(r: 0.10, g: 0.80, b: 0.76)
    public static let cyan = RGBAColor(r: 0.10, g: 0.80, b: 0.92)
    public static let blue = RGBAColor(r: 0.22, g: 0.48, b: 0.96)
    public static let violet = RGBAColor(r: 0.55, g: 0.35, b: 0.95)
    public static let magenta = RGBAColor(r: 0.92, g: 0.20, b: 0.62)
    public static let pink = RGBAColor(r: 0.98, g: 0.45, b: 0.72)
    public static let red = RGBAColor(r: 0.95, g: 0.22, b: 0.22)
    public static let orange = RGBAColor(r: 0.98, g: 0.48, b: 0.12)
    public static let amber = RGBAColor(r: 0.98, g: 0.72, b: 0.12)
    public static let lime = RGBAColor(r: 0.60, g: 0.85, b: 0.20)
    public static let green = RGBAColor(r: 0.18, g: 0.76, b: 0.36)
    public static let white = RGBAColor(r: 1, g: 1, b: 1)

    /// Quick-pick presets shown as swatches (any color is still choosable via
    /// the color picker in the UI).
    public static let palette: [RGBAColor] = [
        .teal, .cyan, .blue, .violet, .magenta, .pink,
        .red, .orange, .amber, .lime, .green, .white,
    ]
}
