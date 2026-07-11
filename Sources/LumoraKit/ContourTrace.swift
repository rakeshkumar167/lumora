import CoreGraphics
import Foundation

/// All settings for a Contour Trace surface. Kept as a struct (rather than a
/// long tuple of associated values) so options can grow without churn.
public struct ContourTraceConfig: Equatable, Codable {
    /// Source images, traced in order (each overlays the previous).
    public var images: [URL]
    /// Pen color (used only when `rainbow == false`).
    public var penColor: RGBAColor
    /// Trace speed multiplier.
    public var speed: Double
    /// Color the trace as a moving rainbow instead of the fixed pen color.
    public var rainbow: Bool
    /// How long the completed trace holds before it fades and repeats (seconds).
    /// Ignored when `alwaysOn` is true.
    public var holdSeconds: Double
    /// Keep the completed trace on permanently — trace once, then stay (no fade,
    /// no repeat).
    public var alwaysOn: Bool

    public init(images: [URL], penColor: RGBAColor = .green, speed: Double = 1.0,
                rainbow: Bool = false, holdSeconds: Double = 30, alwaysOn: Bool = false) {
        self.images = images
        self.penColor = penColor
        self.speed = speed
        self.rainbow = rainbow
        self.holdSeconds = holdSeconds
        self.alwaysOn = alwaysOn
    }
}

/// Pure helpers for the Contour Trace effect's rainbow coloring.
public enum ContourTrace {
    /// Number of discrete hue bands across one spectrum pass.
    public static let rainbowBandCount = 24

    /// The hue band (0..<rainbowBandCount) for a point at `length` along a trace
    /// of total arc length `total`, with a wrapping `phase` offset (0…1). One
    /// spectrum pass spans the whole trace; phase drifts it over time.
    public static func rainbowBand(length: CGFloat, total: CGFloat, phase: Double) -> Int {
        guard total > 0 else { return 0 }
        let frac = Double(length / total) + phase
        let wrapped = frac - floor(frac)                     // 0…1
        let band = Int(wrapped * Double(rainbowBandCount))
        return min(max(band, 0), rainbowBandCount - 1)
    }

    /// Hue (0…1) at the center of a band, for `Color(hue:…)`.
    public static func hue(forBand band: Int) -> Double {
        (Double(band) + 0.5) / Double(rainbowBandCount)
    }
}
