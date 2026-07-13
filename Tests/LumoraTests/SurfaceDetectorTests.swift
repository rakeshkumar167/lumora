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

    /// Build a Segmentation with a single hand-drawn region (no image needed).
    private func segmentation(width: Int, height: Int, region: (Int, Int) -> Bool) -> SurfaceDetector.Segmentation {
        var labels = [Int](repeating: -1, count: width * height)
        for y in 0..<height {
            for x in 0..<width where region(x, y) { labels[y * width + x] = 0 }
        }
        return SurfaceDetector.Segmentation(labels: labels,
                                            barrier: [Bool](repeating: false, count: width * height),
                                            gradient: [Double](repeating: 0, count: width * height),
                                            width: width, height: height)
    }

    func testLargeConcaveRegionRejectedSmallOneKept() {
        // An L-shaped region fills ~0.64 of its enclosing quad. When the quad
        // spans the whole frame that's a background wrapping around objects ->
        // reject; the same shape at a small scale is a plausible surface -> keep.
        let opts = SurfaceDetector.Options()
        // Square with a notch cut out of its bottom middle (fill ~0.63): its
        // hull spans the full square, like a background wrapping around objects.
        func notched(_ x: Int, _ y: Int, _ s: Int) -> Bool {
            !((s * 20 / 100...s * 80 / 100).contains(x) && y >= s * 40 / 100)
        }

        let large = segmentation(width: 100, height: 100) { notched($0, $1, 100) }
        XCTAssertTrue(SurfaceDetector.regionPlaneCandidates(large, options: opts).isEmpty,
                      "near-full-frame concave region must be rejected")

        let small = segmentation(width: 100, height: 100) { (20...49).contains($0) && (20...49).contains($1) && notched($0 - 20, $1 - 20, 30) }
        XCTAssertFalse(SurfaceDetector.regionPlaneCandidates(small, options: opts).isEmpty,
                       "small region with the same fill ratio must be kept")
    }

    func testEdgeSupportSeparatesEdgeBackedFromFloatingQuads() {
        // Gradient ridge forming a rectangle outline at x,y in [20,80].
        var grad = [Double](repeating: 0, count: 100 * 100)
        for i in 20...80 {
            for j in [20, 80] {
                grad[j * 100 + i] = 20  // horizontal edges
                grad[i * 100 + j] = 20  // vertical edges
            }
        }
        let seg = SurfaceDetector.Segmentation(labels: [], barrier: [],
                                               gradient: grad, width: 100, height: 100)
        let onEdges = [CGPoint(x: 0.2, y: 0.2), CGPoint(x: 0.8, y: 0.2),
                       CGPoint(x: 0.8, y: 0.8), CGPoint(x: 0.2, y: 0.8)]
        XCTAssertGreaterThan(SurfaceDetector.edgeSupport(onEdges, seg: seg, minGrad: 7), 0.9)

        let floating = [CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.7, y: 0.35),
                        CGPoint(x: 0.7, y: 0.7), CGPoint(x: 0.3, y: 0.65)]
        XCTAssertLessThan(SurfaceDetector.edgeSupport(floating, seg: seg, minGrad: 7), 0.4,
                          "a quad crossing featureless area must score low")
    }

    func testWallWithGradientSurvivesAsOneRegion() {
        // Region pass only: the lit wall must not fragment under the lighting
        // gradient. Expect a plane candidate covering most of the frame (the
        // wall ring around the screen hulls to nearly the full image).
        let opts = SurfaceDetector.Options()
        let seg = SurfaceDetector.segment(syntheticRoom(), options: opts)!
        let planes = SurfaceDetector.regionPlaneCandidates(seg, options: opts)
        XCTAssertTrue(planes.contains { $0.areaFraction > 0.7 },
                      "wall should stay one region despite the gradient, got \(planes.map(\.areaFraction))")
    }
}
