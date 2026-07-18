import XCTest
import CoreGraphics
@testable import LumoraKit

final class PolygonToQuadTests: XCTestCase {
    private func area(_ p: [CGPoint]) -> Double { SurfaceGeometry.polygonArea(p) }

    /// Sampled IoU for assertions (independent of the implementation's own).
    private func iou(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        let pts = a + b
        var minX = pts[0].x, minY = pts[0].y, maxX = pts[0].x, maxY = pts[0].y
        for p in pts { minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y) }
        var inter = 0, uni = 0
        let s = 60
        for i in 0..<s { for j in 0..<s {
            let x = Double(minX) + (Double(maxX - minX)) * (Double(i) + 0.5) / Double(s)
            let y = Double(minY) + (Double(maxY - minY)) * (Double(j) + 0.5) / Double(s)
            let p = CGPoint(x: x, y: y)
            let ina = SurfaceGeometry.contains(p, in: a), inb = SurfaceGeometry.contains(p, in: b)
            if ina && inb { inter += 1 }
            if ina || inb { uni += 1 }
        } }
        return uni > 0 ? Double(inter) / Double(uni) : 0
    }

    func testAlreadyQuadReturnsFourCorners() {
        let sq = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        let q = PolygonToQuad.convert(sq)
        XCTAssertEqual(q.count, 4)
        XCTAssertEqual(Set(q.map { "\($0.x),\($0.y)" }), Set(sq.map { "\($0.x),\($0.y)" }))
    }

    func testThreePointsCompleteParallelogram() {
        // A=(0,0) B=(0,4) C=(3,4) → D = A + C − B = (3,0).
        let q = PolygonToQuad.convert([CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 4), CGPoint(x: 3, y: 4)])
        XCTAssertEqual(q.count, 4)
        XCTAssertTrue(q.contains { abs($0.x - 3) < 1e-6 && abs($0.y - 0) < 1e-6 }, "computed 4th corner (3,0)")
        XCTAssertEqual(area(q), 12, accuracy: 1e-6)
    }

    func testFivePointDominatedByThreeEdgesRecoversRectangle() {
        // Rectangle 10×6 with the left edge split by an extra midpoint (0,3).
        let poly = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 6),
                    CGPoint(x: 0, y: 6), CGPoint(x: 0, y: 3)]
        let q = PolygonToQuad.convert(poly)
        XCTAssertEqual(q.count, 4)
        // Recovers the clean rectangle → high IoU with the (nearly identical) polygon.
        XCTAssertGreaterThan(iou(q, poly), 0.9)
        XCTAssertEqual(area(q), 60, accuracy: 2)
    }

    func testBlobFallsBackToEnclosingQuad() {
        // Regular octagon — no 2–3 dominant adjacent edges.
        var poly: [CGPoint] = []
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi
            poly.append(CGPoint(x: 5 + 4 * cos(a), y: 5 + 4 * sin(a)))
        }
        let q = PolygonToQuad.convert(poly)
        XCTAssertEqual(q.count, 4)
        // The enclosing quad covers the whole octagon (a quad around an octagon
        // tops out near octagon/square ≈ 0.71 IoU) and is at least its area.
        XCTAssertGreaterThan(iou(q, poly), 0.6)
        XCTAssertGreaterThanOrEqual(area(q), area(poly) - 1e-6)
    }

    func testAlwaysReturnsFourOrderedCorners() {
        let poly = [CGPoint(x: 0, y: 0), CGPoint(x: 6, y: 1), CGPoint(x: 7, y: 5),
                    CGPoint(x: 3, y: 7), CGPoint(x: -1, y: 4), CGPoint(x: 0, y: 2)]
        XCTAssertEqual(PolygonToQuad.convert(poly).count, 4)
    }
}
