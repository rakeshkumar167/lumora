import XCTest
import CoreGraphics
@testable import LumoraKit

final class DetectSurfacesTests: XCTestCase {
    /// A synthetic room: gradient wall, a floor band, and a dark rectangular screen.
    private func syntheticRoom(_ w: Int = 800, _ h: Int = 600) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.80, green: 0.78, blue: 0.74, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.55, green: 0.53, blue: 0.50, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h / 4)) // floor band
        ctx.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1))
        ctx.fill(CGRect(x: Double(w) * 0.35, y: Double(h) * 0.40, width: Double(w) * 0.35, height: Double(h) * 0.32)) // screen
        return ctx.makeImage()!
    }

    func testReturnsNormalizedSortedSurfaces() {
        let surfaces = SurfaceDetector.detectSurfaces(in: syntheticRoom())
        XCTAssertFalse(surfaces.isEmpty, "should detect at least one surface")
        // Largest first.
        for i in 1..<surfaces.count { XCTAssertGreaterThanOrEqual(surfaces[i - 1].area, surfaces[i].area) }
        // Normalized coordinates.
        for s in surfaces { for p in s.polygon {
            XCTAssertTrue((-0.01...1.01).contains(Double(p.x)))
            XCTAssertTrue((-0.01...1.01).contains(Double(p.y)))
        } }
    }

    func testRespectsMaxResults() {
        var opts = SurfaceDetector.Options()
        opts.ranker.maxResults = 3
        XCTAssertLessThanOrEqual(SurfaceDetector.detectSurfaces(in: syntheticRoom(), options: opts).count, 3)
    }
}
