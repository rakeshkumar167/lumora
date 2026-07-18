import Foundation

/// Binary edge map, row-major, top-left origin.
public struct EdgeMap: Equatable {
    public let width: Int
    public let height: Int
    public var edges: [Bool]
}

/// Canny edge detection: Gaussian blur → Sobel → non-max suppression →
/// auto double-threshold → hysteresis. Pure Swift.
public enum CannyEdgeDetector {
    public struct Config {
        /// Pre-blur sigma.
        public var sigma: Float
        /// High threshold = `highFraction` × a robust max (95th-percentile) of
        /// the suppressed gradient magnitudes. A fraction-of-max (rather than a
        /// plain percentile of all magnitudes) is robust to plateaus: a pure
        /// step image has almost every edge at one magnitude, which a percentile
        /// would place the threshold exactly on — dropping edges on float ties.
        public var highFraction: Float
        /// Low threshold = high * lowRatio.
        public var lowRatio: Float
        public init(sigma: Float = 1.4, highFraction: Float = 0.3, lowRatio: Float = 0.4) {
            self.sigma = sigma
            self.highFraction = highFraction
            self.lowRatio = lowRatio
        }
    }

    public static func detect(_ img: GrayImage, config: Config = .init()) -> EdgeMap {
        let blurred = ImagePreprocessor.gaussianBlur(img, sigma: config.sigma)
        let g = Sobel.gradients(blurred)
        let w = g.width, h = g.height
        guard w >= 3, h >= 3 else {
            return EdgeMap(width: w, height: h, edges: [Bool](repeating: false, count: w * h))
        }

        // --- Non-maximum suppression (thin edges to 1px along the gradient). ---
        var nms = [Float](repeating: 0, count: w * h)
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let m = g.magnitude[y * w + x]
                if m == 0 { continue }
                let (a, b) = neighborsAlongGradient(g.magnitude, w, x, y, g.orientation[y * w + x])
                if m >= a && m >= b { nms[y * w + x] = m }
            }
        }

        // --- Auto thresholds: a fraction of a robust-max suppressed magnitude.
        // The 95th percentile estimates the strong-edge magnitude while ignoring
        // the top few outlier pixels; taking a fraction of it seeds every clear
        // edge (plateau-robust) without seeding flat-region noise. ---
        let robustMax = percentile(nms, 0.95)
        let high = robustMax * config.highFraction
        let low = high * config.lowRatio
        if high <= 0 {
            return EdgeMap(width: w, height: h, edges: [Bool](repeating: false, count: w * h))
        }

        // --- Hysteresis: seed on strong pixels, grow through weak-connected ones. ---
        var edges = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        for i in 0..<(w * h) where nms[i] >= high {
            edges[i] = true
            stack.append(i)
        }
        while let idx = stack.popLast() {
            let x = idx % w, y = idx / w
            for dy in -1...1 {
                for dx in -1...1 {
                    let xx = x + dx, yy = y + dy
                    if xx >= 0, xx < w, yy >= 0, yy < h {
                        let j = yy * w + xx
                        if !edges[j], nms[j] >= low {
                            edges[j] = true
                            stack.append(j)
                        }
                    }
                }
            }
        }
        return EdgeMap(width: w, height: h, edges: edges)
    }

    /// The two magnitudes adjacent to (x,y) along the quantized gradient
    /// direction (0°/45°/90°/135°). Callers guarantee 1 ≤ x < w-1, 1 ≤ y < h-1.
    static func neighborsAlongGradient(_ mag: [Float], _ w: Int, _ x: Int, _ y: Int,
                                       _ angle: Float) -> (Float, Float) {
        var a = angle
        if a < 0 { a += .pi }
        let deg = a * 180 / .pi
        @inline(__always) func m(_ xx: Int, _ yy: Int) -> Float { mag[yy * w + xx] }
        if deg < 22.5 || deg >= 157.5 {          // 0°  — compare left / right
            return (m(x - 1, y), m(x + 1, y))
        } else if deg < 67.5 {                   // 45° — compare the two diagonals
            return (m(x - 1, y + 1), m(x + 1, y - 1))
        } else if deg < 112.5 {                  // 90° — compare up / down
            return (m(x, y - 1), m(x, y + 1))
        } else {                                 // 135°
            return (m(x - 1, y - 1), m(x + 1, y + 1))
        }
    }

    /// The value at percentile `p` (0...1) among the strictly-positive entries.
    static func percentile(_ values: [Float], _ p: Float) -> Float {
        let nonzero = values.filter { $0 > 0 }.sorted()
        if nonzero.isEmpty { return 0 }
        let idx = min(nonzero.count - 1, max(0, Int(Float(nonzero.count - 1) * p)))
        return nonzero[idx]
    }
}
