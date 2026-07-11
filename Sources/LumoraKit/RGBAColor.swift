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

    /// Quick-pick presets shown as swatches, laid out 8 per row × 4 rows (any
    /// color is still choosable via the color picker in the UI).
    public static let palette: [RGBAColor] = [
        // Row 1 — vivid spectrum
        .red, .orange, .amber,
        RGBAColor(r: 0.98, g: 0.90, b: 0.20),   // yellow
        .lime, .green, .teal, .cyan,
        // Row 2 — cool tones → pinks
        RGBAColor(r: 0.25, g: 0.65, b: 0.98),   // sky
        .blue,
        RGBAColor(r: 0.35, g: 0.35, b: 0.90),   // indigo
        .violet,
        RGBAColor(r: 0.70, g: 0.30, b: 0.90),   // purple
        .magenta, .pink,
        RGBAColor(r: 0.98, g: 0.60, b: 0.66),   // rose
        // Row 3 — deep / muted
        RGBAColor(r: 0.55, g: 0.12, b: 0.16),   // maroon
        RGBAColor(r: 0.70, g: 0.30, b: 0.12),   // rust
        RGBAColor(r: 0.55, g: 0.55, b: 0.15),   // olive
        RGBAColor(r: 0.12, g: 0.45, b: 0.25),   // forest
        RGBAColor(r: 0.06, g: 0.45, b: 0.48),   // deep teal
        RGBAColor(r: 0.12, g: 0.20, b: 0.55),   // navy
        RGBAColor(r: 0.36, g: 0.16, b: 0.55),   // deep purple
        RGBAColor(r: 0.50, g: 0.15, b: 0.40),   // plum
        // Row 4 — pastels + neutrals
        RGBAColor(r: 0.99, g: 0.80, b: 0.68),   // peach
        RGBAColor(r: 0.70, g: 0.95, b: 0.82),   // mint
        RGBAColor(r: 0.80, g: 0.78, b: 0.98),   // lavender
        RGBAColor(r: 0.92, g: 0.86, b: 0.70),   // sand
        .white,
        RGBAColor(r: 0.76, g: 0.78, b: 0.81),   // light gray
        RGBAColor(r: 0.50, g: 0.52, b: 0.55),   // gray
        RGBAColor(r: 0.20, g: 0.22, b: 0.26),   // charcoal
    ]
}
