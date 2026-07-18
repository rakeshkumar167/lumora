import Foundation

/// Binary morphology on row-major `[Bool]` images.
public enum Morphology {
    /// Dilate with a square (Chebyshev) structuring element of the given radius.
    public static func dilate(_ binary: [Bool], width w: Int, height h: Int, radius: Int) -> [Bool] {
        if radius <= 0 { return binary }
        var out = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w where binary[y * w + x] {
                let x0 = max(0, x - radius), x1 = min(w - 1, x + radius)
                let y0 = max(0, y - radius), y1 = min(h - 1, y + radius)
                for ny in y0...y1 { for nx in x0...x1 { out[ny * w + nx] = true } }
            }
        }
        return out
    }
}
