import XCTest
import CoreGraphics
@testable import LumoraKit

final class SurfaceDetectorTests: XCTestCase {
    /// A synthetic "room": a light wall with a dark rectangular screen. Keeps
    /// the detector test self-contained — no external sample photos required.
    private func syntheticRoom(width w: Int = 800, height h: Int = 600) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.86, green: 0.84, blue: 0.80, alpha: 1))   // wall
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1))   // dark "screen"
        ctx.fill(CGRect(x: Double(w) * 0.30, y: Double(h) * 0.35,
                        width: Double(w) * 0.40, height: Double(h) * 0.30))
        return ctx.makeImage()!
    }

    func testDetectsPlausibleSurfacesOnSyntheticRoom() {
        let opts = SurfaceDetector.Options()
        let quads = SurfaceDetector.detect(in: syntheticRoom(), options: opts)

        XCTAssertFalse(quads.isEmpty, "expected at least one surface on the synthetic scene")
        XCTAssertLessThanOrEqual(quads.count, opts.ranker.maxResults)
        for q in quads {
            XCTAssertEqual(q.corners.count, 4, "quad must have 4 corners")
            XCTAssertGreaterThanOrEqual(q.areaFraction, opts.ranker.minAreaFraction - 1e-6)
            for p in q.corners {
                XCTAssertTrue((-0.02...1.02).contains(Double(p.x)), "x in range")
                XCTAssertTrue((-0.02...1.02).contains(Double(p.y)), "y in range")
            }
        }
    }
}
