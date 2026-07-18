import CoreGraphics
import Foundation

/// Classical-CV preprocessing: rasterize + smooth a room photo into a
/// noise-reduced grayscale buffer for edge detection. Pure Swift + CoreGraphics.
public enum ImagePreprocessor {
    /// Downscale (never upscale) so the longer side ≤ `maxDimension`, then
    /// rasterize into a device-gray, top-left-origin buffer normalized to 0...1.
    public static func grayscale(from image: CGImage, maxDimension: Int) -> GrayImage {
        let longSide = max(image.width, image.height)
        let scale = longSide > maxDimension ? Double(maxDimension) / Double(longSide) : 1.0
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))

        let cs = CGColorSpaceCreateDeviceGray()
        var bytes = [UInt8](repeating: 0, count: w * h)
        // No flip: CGContext bitmap row 0 is already the TOP scanline.
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return GrayImage(width: w, height: h, pixels: [Float](repeating: 0, count: w * h))
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var pixels = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) { pixels[i] = Float(bytes[i]) / 255.0 }
        return GrayImage(width: w, height: h, pixels: pixels)
    }

    /// Separable Gaussian blur with clamp-to-edge borders.
    public static func gaussianBlur(_ img: GrayImage, sigma: Float) -> GrayImage {
        let radius = max(1, Int((sigma * 3).rounded()))
        var kernel = [Float](repeating: 0, count: 2 * radius + 1)
        var sum: Float = 0
        for i in -radius...radius {
            let v = expf(-Float(i * i) / (2 * sigma * sigma))
            kernel[i + radius] = v
            sum += v
        }
        for i in kernel.indices { kernel[i] /= sum }

        let w = img.width, h = img.height
        var tmp = [Float](repeating: 0, count: w * h)
        // Horizontal pass.
        for y in 0..<h {
            for x in 0..<w {
                var acc: Float = 0
                for k in -radius...radius {
                    let xx = min(max(x + k, 0), w - 1)
                    acc += img.pixels[y * w + xx] * kernel[k + radius]
                }
                tmp[y * w + x] = acc
            }
        }
        // Vertical pass.
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var acc: Float = 0
                for k in -radius...radius {
                    let yy = min(max(y + k, 0), h - 1)
                    acc += tmp[yy * w + x] * kernel[k + radius]
                }
                out[y * w + x] = acc
            }
        }
        return GrayImage(width: w, height: h, pixels: out)
    }
}
