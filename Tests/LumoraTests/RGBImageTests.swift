import XCTest
import CoreGraphics
@testable import LumoraKit

final class RGBImageTests: XCTestCase {
    private func rgbCGImage(_ w: Int, _ h: Int, _ fill: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let (r, g, b) = fill(x, y); let i = (y * w + x) * 4
            bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b; bytes[i + 3] = 255
        } }
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    func testExtractsColorsWithCorrectOrientation() {
        // Top-left red, else blue: catches H and V flips.
        let img = rgbCGImage(4, 4) { x, y in (x < 2 && y < 2) ? (255, 0, 0) : (0, 0, 255) }
        let rgb = ImagePreprocessor.rgb(from: img, maxDimension: 4)
        XCTAssertEqual(rgb.width, 4); XCTAssertEqual(rgb.height, 4)
        let tl = rgb.color(at: 0, 0), br = rgb.color(at: 3, 3)
        XCTAssertGreaterThan(tl.r, 0.8); XCTAssertLessThan(tl.b, 0.2)
        XCTAssertGreaterThan(br.b, 0.8); XCTAssertLessThan(br.r, 0.2)
    }

    func testDownscales() {
        let img = rgbCGImage(8, 4) { _, _ in (128, 128, 128) }
        let rgb = ImagePreprocessor.rgb(from: img, maxDimension: 4)
        XCTAssertEqual(rgb.width, 4); XCTAssertEqual(rgb.height, 2)
    }
}
