import XCTest
import CoreGraphics
@testable import LumoraKit

final class SurfaceDetectorTests: XCTestCase {
    /// A synthetic "room": a wall under a left-to-right lighting gradient with
    /// a dark rectangular screen. The gradient is the hard part — a segmenter
    /// keyed on exact colour splits the wall apart. Self-contained, no
    /// external sample photos required.
    private func syntheticRoom(width w: Int = 800, height h: Int = 600) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let gradient = CGGradient(colorsSpace: cs, colors: [
            CGColor(red: 0.72, green: 0.70, blue: 0.66, alpha: 1),
            CGColor(red: 0.93, green: 0.91, blue: 0.87, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: w, y: 0), options: [])
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
            XCTAssertLessThanOrEqual(q.areaFraction, opts.ranker.maxAreaFraction + 1e-6,
                                     "near-full-frame quads must be filtered out")
            for p in q.corners {
                XCTAssertTrue((-0.02...1.02).contains(Double(p.x)), "x in range")
                XCTAssertTrue((-0.02...1.02).contains(Double(p.y)), "y in range")
            }
        }

        // The screen (0.30...0.70 x 0.35...0.65, area 0.12) must be found with
        // reasonably accurate placement.
        let screen = quads.first { q in
            let c = SurfaceGeometry.centroid(q.corners)
            return abs(Double(c.x) - 0.5) < 0.05 && abs(Double(c.y) - 0.5) < 0.05
                && (0.08...0.18).contains(q.areaFraction)
        }
        XCTAssertNotNil(screen, "expected a quad matching the dark screen, got \(quads)")
    }

    func testWallWithGradientSurvivesAsOneRegion() {
        // Region pass only: the lit wall must not fragment under the lighting
        // gradient. Expect a plane candidate covering most of the frame (the
        // wall ring around the screen hulls to nearly the full image).
        let opts = SurfaceDetector.Options()
        let planes = SurfaceDetector.regionPlaneCandidates(syntheticRoom(), options: opts)
        XCTAssertTrue(planes.contains { $0.areaFraction > 0.7 },
                      "wall should stay one region despite the gradient, got \(planes.map(\.areaFraction))")
    }
}
