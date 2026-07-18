import XCTest
import CoreGraphics
@testable import LumoraKit

final class PerspectiveRectifierTests: XCTestCase {
    /// Top-left quadrant red, rest black — asymmetric, catches flips.
    private func asymmetric(_ w: Int = 120, _ h: Int = 100) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Top-left quadrant (top-left origin) → CGContext y-up bottom is y=0, so top half is y in [h/2, h].
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: h / 2, width: w / 2, height: h / 2))
        return ctx.makeImage()!
    }

    func testFullFrameCornersPreserveOrientation() {
        let img = asymmetric()
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        let out = PerspectiveRectifier.rectify(img, corners: corners)
        XCTAssertNotNil(out)
        guard let out = out else { return }
        XCTAssertGreaterThan(out.width, 0); XCTAssertGreaterThan(out.height, 0)
        // Sample the rectified image: top-left stays red, bottom-right stays black.
        let rgb = ImagePreprocessor.rgb(from: out, maxDimension: 200)
        let tl = rgb.color(at: rgb.width / 8, rgb.height / 8)
        let br = rgb.color(at: rgb.width * 7 / 8, rgb.height * 7 / 8)
        XCTAssertGreaterThan(tl.r, 0.6); XCTAssertLessThan(tl.g, 0.3)   // red, not flipped
        XCTAssertLessThan(br.r, 0.3)                                    // black corner
    }

    func testWrongCornerCountReturnsNil() {
        XCTAssertNil(PerspectiveRectifier.rectify(asymmetric(), corners: [CGPoint(x: 0, y: 0)]))
    }

    func testRectifiesInnerQuadToFullFrame() {
        // Corners of an inner sub-rectangle → output is roughly that crop, upright.
        let img = asymmetric(200, 200)
        let corners = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.6, y: 0.1),
                       CGPoint(x: 0.6, y: 0.6), CGPoint(x: 0.1, y: 0.6)]
        let out = PerspectiveRectifier.rectify(img, corners: corners)
        XCTAssertNotNil(out)
        // The inner region spans the red/black boundary → output has both.
        if let out = out {
            let rgb = ImagePreprocessor.rgb(from: out, maxDimension: 200)
            let tl = rgb.color(at: rgb.width / 8, rgb.height / 8)
            XCTAssertGreaterThan(tl.r, 0.5, "inner top-left is inside the red quadrant")
        }
    }
}
