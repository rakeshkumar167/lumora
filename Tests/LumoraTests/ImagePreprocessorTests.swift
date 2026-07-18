import XCTest
import CoreGraphics
@testable import LumoraKit

final class ImagePreprocessorTests: XCTestCase {
    /// Build a device-gray CGImage from a per-pixel fill. Row 0 is the TOP row
    /// (matches the no-flip raster convention used throughout the pipeline).
    static func grayCGImage(width w: Int, height h: Int, fill: (Int, Int) -> UInt8) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { bytes[y * w + x] = fill(x, y) } }
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w, space: cs,
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        return ctx.makeImage()!
    }

    func testGrayscaleRecoversAsymmetricPattern() {
        // White only in the top-left quadrant: catches both H and V flips.
        let img = Self.grayCGImage(width: 4, height: 4) { x, y in (x < 2 && y < 2) ? 255 : 0 }
        let g = ImagePreprocessor.grayscale(from: img, maxDimension: 4)
        XCTAssertEqual(g.width, 4)
        XCTAssertEqual(g.height, 4)
        XCTAssertGreaterThan(g.at(0, 0), 0.9, "top-left should be white")
        XCTAssertLessThan(g.at(3, 3), 0.1, "bottom-right should be black")
        XCTAssertLessThan(g.at(3, 0), 0.1, "top-right should be black")
        XCTAssertLessThan(g.at(0, 3), 0.1, "bottom-left should be black")
    }

    func testGrayscaleDownscalesToMaxDimension() {
        let img = Self.grayCGImage(width: 8, height: 4) { _, _ in 128 }
        let g = ImagePreprocessor.grayscale(from: img, maxDimension: 4)
        XCTAssertEqual(g.width, 4)
        XCTAssertEqual(g.height, 2)
        XCTAssertEqual(g.pixels.count, 8)
    }

    func testGrayscaleNeverUpscales() {
        let img = Self.grayCGImage(width: 4, height: 4) { _, _ in 200 }
        let g = ImagePreprocessor.grayscale(from: img, maxDimension: 100)
        XCTAssertEqual(g.width, 4)
        XCTAssertEqual(g.height, 4)
    }

    func testGaussianBlurPreservesUniformImage() {
        let g = GrayImage(width: 5, height: 5, pixels: [Float](repeating: 0.5, count: 25))
        let b = ImagePreprocessor.gaussianBlur(g, sigma: 1.0)
        XCTAssertEqual(b.width, 5)
        XCTAssertEqual(b.height, 5)
        for v in b.pixels { XCTAssertEqual(v, 0.5, accuracy: 1e-4) }
    }

    func testGaussianBlurSpreadsAnImpulse() {
        var px = [Float](repeating: 0, count: 25)
        px[2 * 5 + 2] = 1.0 // center impulse
        let g = GrayImage(width: 5, height: 5, pixels: px)
        let b = ImagePreprocessor.gaussianBlur(g, sigma: 1.0)
        XCTAssertLessThan(b.at(2, 2), 1.0, "center energy should spread out")
        XCTAssertGreaterThan(b.at(2, 1), 0.0, "neighbor should receive energy")
        XCTAssertGreaterThan(b.at(1, 2), 0.0, "neighbor should receive energy")
    }
}
