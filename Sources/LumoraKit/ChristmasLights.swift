import CoreGraphics
import Foundation

/// Pure geometry + palette for the Christmas string-light effects. Size-driven,
/// no UI. Bulb positions are returned in the given pixel space (top-left origin,
/// larger y is lower). Deterministic — any twinkle randomness lives in the
/// renderer as a per-bulb phase, so geometry is stable frame-to-frame.
public enum ChristmasLights {
    /// Classic festive palette: red, green, gold, blue, warm-white.
    public static let palette: [RGBAColor] = [
        RGBAColor(r: 0.85, g: 0.11, b: 0.14),
        RGBAColor(r: 0.11, g: 0.58, b: 0.24),
        RGBAColor(r: 0.95, g: 0.76, b: 0.22),
        RGBAColor(r: 0.16, g: 0.42, b: 0.90),
        RGBAColor(r: 1.00, g: 0.93, b: 0.80),
    ]

    /// One hung strand: bulb centers left→right along a downward-sagging arc.
    public struct Strand {
        public let bulbs: [CGPoint]
        public init(bulbs: [CGPoint]) { self.bulbs = bulbs }
    }

    private static let rowSpacing: CGFloat = 90
    private static let bulbSpacing: CGFloat = 55
    private static let insetFraction: CGFloat = 0.06

    /// Horizontal sagging strands stacked down the surface. Count scales with
    /// height (min 2); bulbs-per-strand scales with width (min 3).
    public static func strands(in size: CGSize) -> [Strand] {
        guard size.width > 0, size.height > 0 else { return [] }
        let strandCount = max(2, Int((size.height / rowSpacing).rounded()))
        let bulbCount = max(3, Int((size.width / bulbSpacing).rounded()))
        let sag = 0.35 * rowSpacing
        let inset = size.width * insetFraction
        let left = inset, right = size.width - inset

        var result: [Strand] = []
        for s in 0..<strandCount {
            // Base (pin) height for this strand, evenly distributed.
            let y0 = size.height * (CGFloat(s) + 0.5) / CGFloat(strandCount)
            var bulbs: [CGPoint] = []
            for i in 0..<bulbCount {
                let t = CGFloat(i) / CGFloat(bulbCount - 1)      // 0…1
                let x = left + (right - left) * t
                let y = y0 + sag * 4 * t * (1 - t)               // 0 at ends, max mid
                bulbs.append(CGPoint(x: x, y: y))
            }
            result.append(Strand(bulbs: bulbs))
        }
        return result
    }
}
