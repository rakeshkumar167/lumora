import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LumoraKit

final class CannyEdgeDetectorTests: XCTestCase {
    /// White rectangle (10,10)-(30,30) on a black 40×40 field.
    private func rectangleImage() -> GrayImage {
        let w = 40, h = 40
        var px = [Float](repeating: 0, count: w * h)
        for y in 10..<30 { for x in 10..<30 { px[y * w + x] = 1 } }
        return GrayImage(width: w, height: h, pixels: px)
    }

    private func hasEdgeNear(_ e: EdgeMap, _ cx: Int, _ cy: Int, radius: Int = 2) -> Bool {
        for dy in -radius...radius { for dx in -radius...radius {
            let x = cx + dx, y = cy + dy
            if x >= 0, x < e.width, y >= 0, y < e.height, e.edges[y * e.width + x] { return true }
        } }
        return false
    }

    func testDetectsRectangleBorderNotInterior() {
        let e = CannyEdgeDetector.detect(rectangleImage())
        XCTAssertTrue(e.edges.contains(true), "should find some edges")
        // Border midpoints (top, bottom, left, right of the rectangle).
        XCTAssertTrue(hasEdgeNear(e, 20, 10), "top border")
        XCTAssertTrue(hasEdgeNear(e, 20, 30), "bottom border")
        XCTAssertTrue(hasEdgeNear(e, 10, 20), "left border")
        XCTAssertTrue(hasEdgeNear(e, 30, 20), "right border")
        // No edges deep inside the flat rectangle or the flat background.
        XCTAssertFalse(hasEdgeNear(e, 20, 20, radius: 3), "interior is flat")
        XCTAssertFalse(hasEdgeNear(e, 2, 2, radius: 1), "far background is flat")
    }

    func testFlatImageHasNoEdges() {
        let flat = GrayImage(width: 20, height: 20, pixels: [Float](repeating: 0.5, count: 400))
        let e = CannyEdgeDetector.detect(flat)
        XCTAssertFalse(e.edges.contains(true), "a flat image has no edges")
    }

    func testWritesCannyOverlayArtifactWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["CANNY_OVERLAY"] == "1" else {
            throw XCTSkip("set CANNY_OVERLAY=1 to write the overlay artifact")
        }
        // Synthetic room: a wall over a floor band, plus a dark rectangular screen.
        let w = 320, h = 240
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.82, green: 0.80, blue: 0.76, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.55, green: 0.52, blue: 0.48, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h / 3)) // floor band
        ctx.setFillColor(CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)); ctx.fill(CGRect(x: 110, y: 120, width: 110, height: 70)) // screen
        let room = ctx.makeImage()!

        let gray = ImagePreprocessor.grayscale(from: room, maxDimension: 320)
        let e = CannyEdgeDetector.detect(gray)

        // Render edges as white-on-black into a PNG.
        var bytes = [UInt8](repeating: 0, count: e.width * e.height * 4)
        for i in 0..<(e.width * e.height) {
            let v: UInt8 = e.edges[i] ? 255 : 0
            bytes[i * 4] = v; bytes[i * 4 + 1] = v; bytes[i * 4 + 2] = v; bytes[i * 4 + 3] = 255
        }
        let outCtx = CGContext(data: &bytes, width: e.width, height: e.height, bitsPerComponent: 8,
                               bytesPerRow: e.width * 4, space: cs,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let outImg = outCtx.makeImage()!
        let dir = ProcessInfo.processInfo.environment["CANNY_OVERLAY_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent("canny_overlay.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, outImg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        print("CANNY_OVERLAY written to: \(url.path)")
        XCTAssertTrue(e.edges.contains(true))
    }
}
