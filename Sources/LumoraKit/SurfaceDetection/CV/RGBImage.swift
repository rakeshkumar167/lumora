import CoreGraphics
import Foundation

/// An RGBA8 image buffer, row-major, top-left origin.
public struct RGBImage {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8] // RGBA, length width*height*4

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width; self.height = height; self.pixels = pixels
    }

    public func color(at x: Int, _ y: Int) -> RGBAColor {
        let i = (y * width + x) * 4
        return RGBAColor(r: Double(pixels[i]) / 255, g: Double(pixels[i + 1]) / 255,
                         b: Double(pixels[i + 2]) / 255, a: Double(pixels[i + 3]) / 255)
    }
}

extension ImagePreprocessor {
    /// Downscale (never up) so the longer side ≤ `maxDimension`; rasterize into
    /// a top-left-origin RGBA8 buffer.
    public static func rgb(from image: CGImage, maxDimension: Int) -> RGBImage {
        let longSide = max(image.width, image.height)
        let scale = longSide > maxDimension ? Double(maxDimension) / Double(longSide) : 1.0
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        let cs = CGColorSpaceCreateDeviceRGB()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return RGBImage(width: w, height: h, pixels: bytes)
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return RGBImage(width: w, height: h, pixels: bytes)
    }
}
