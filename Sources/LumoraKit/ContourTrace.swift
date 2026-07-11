import CoreGraphics
import Foundation

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
