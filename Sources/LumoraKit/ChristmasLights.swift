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

    private static let insetFraction: CGFloat = 0.06

    /// A single horizontal strand hung across the surface in one or more
    /// drooping swags. The wire pins to the **top** and its droop depth is
    /// driven by width, so stretching the surface taller neither moves nor
    /// scales the lights. Bulb and swag counts come from `config`.
    public static func strands(in size: CGSize, config: ChristmasLightsConfig = .init()) -> [Strand] {
        guard size.width > 0, size.height > 0 else { return [] }
        let bulbCount = max(2, config.bulbCount)
        let sagCount = max(1, config.sagCount)
        let inset = size.width * insetFraction
        let left = inset, right = size.width - inset
        let span = max(1, right - left)

        // Everything vertical is derived from width → height-independent.
        let sagSpan = span / CGFloat(sagCount)   // horizontal width of one swag
        let sagDepth = sagSpan * 0.28            // how far each swag droops
        let pinY = sagDepth * 0.45 + size.width * 0.012   // wire pins just below the top

        var bulbs: [CGPoint] = []
        for i in 0..<bulbCount {
            let t = bulbCount == 1 ? 0.5 : CGFloat(i) / CGFloat(bulbCount - 1)   // 0…1 across width
            let x = left + span * t
            // Position within the current swag (0 at a top pin, 0.5 at the dip).
            let localT = (t * CGFloat(sagCount)).truncatingRemainder(dividingBy: 1)
            let y = pinY + sagDepth * 4 * localT * (1 - localT)   // 0 at swag ends, max mid
            bulbs.append(CGPoint(x: x, y: y))
        }
        return [Strand(bulbs: bulbs)]
    }
}
