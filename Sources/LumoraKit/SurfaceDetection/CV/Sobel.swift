import Foundation

/// Gradient magnitude + orientation from a 3×3 Sobel operator.
public struct GradientField: Equatable {
    public let width: Int
    public let height: Int
    public var magnitude: [Float]
    public var orientation: [Float] // radians, atan2(gy, gx)
}

public enum Sobel {
    public static func gradients(_ img: GrayImage) -> GradientField {
        let w = img.width, h = img.height
        var mag = [Float](repeating: 0, count: w * h)
        var ori = [Float](repeating: 0, count: w * h)

        @inline(__always) func p(_ x: Int, _ y: Int) -> Float {
            img.pixels[min(max(y, 0), h - 1) * w + min(max(x, 0), w - 1)]
        }
        for y in 0..<h {
            for x in 0..<w {
                let gx = (p(x + 1, y - 1) + 2 * p(x + 1, y) + p(x + 1, y + 1))
                       - (p(x - 1, y - 1) + 2 * p(x - 1, y) + p(x - 1, y + 1))
                let gy = (p(x - 1, y + 1) + 2 * p(x, y + 1) + p(x + 1, y + 1))
                       - (p(x - 1, y - 1) + 2 * p(x, y - 1) + p(x + 1, y - 1))
                mag[y * w + x] = (gx * gx + gy * gy).squareRoot()
                ori[y * w + x] = atan2f(gy, gx)
            }
        }
        return GradientField(width: w, height: h, magnitude: mag, orientation: ori)
    }
}
