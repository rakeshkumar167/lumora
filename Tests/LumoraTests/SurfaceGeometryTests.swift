import XCTest
import CoreGraphics
@testable import LumoraKit

final class SurfaceGeometryTests: XCTestCase {
    func testPolygonAreaOfUnitSquare() {
        let sq = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        XCTAssertEqual(SurfaceGeometry.polygonArea(sq), 1.0, accuracy: 1e-9)
    }

    func testPolygonAreaIsOrderIndependent() {
        let tri = [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 0, y: 3)]
        XCTAssertEqual(SurfaceGeometry.polygonArea(tri), 6.0, accuracy: 1e-9)
    }

    func testCentroid() {
        let sq = [CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 0), CGPoint(x: 2, y: 2), CGPoint(x: 0, y: 2)]
        XCTAssertEqual(SurfaceGeometry.centroid(sq), CGPoint(x: 1, y: 1))
    }

    func testConvexHullDropsInteriorAndCollinearPoints() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 0), CGPoint(x: 2, y: 2),
                   CGPoint(x: 0, y: 2), CGPoint(x: 1, y: 1) /*interior*/, CGPoint(x: 1, y: 0) /*collinear*/]
        let hull = SurfaceGeometry.convexHull(pts)
        XCTAssertEqual(hull.count, 4)
        XCTAssertEqual(SurfaceGeometry.polygonArea(hull), 4.0, accuracy: 1e-9)
    }

    func testReduceToQuadKeepsFourStrongestCorners() {
        // A square with two tiny bumps -> should reduce back to the square.
        let poly = [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 10, y: 0),
                    CGPoint(x: 10, y: 10), CGPoint(x: 5, y: 10.1), CGPoint(x: 0, y: 10)]
        let quad = SurfaceGeometry.reduceToQuad(poly)
        XCTAssertEqual(quad.count, 4)
        XCTAssertEqual(SurfaceGeometry.polygonArea(quad), 100.0, accuracy: 2.0)
    }

    func testReduceToQuadPassesThroughFourPoints() {
        let quad = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        XCTAssertEqual(SurfaceGeometry.reduceToQuad(quad).count, 4)
    }

    func testEnclosingQuadRecoversChamferedSquare() {
        // A square with all four corners chamfered off: the enclosing quad
        // should restore the original square by intersecting the edge lines.
        let hull = [CGPoint(x: 2, y: 0), CGPoint(x: 8, y: 0), CGPoint(x: 10, y: 2), CGPoint(x: 10, y: 8),
                    CGPoint(x: 8, y: 10), CGPoint(x: 2, y: 10), CGPoint(x: 0, y: 8), CGPoint(x: 0, y: 2)]
        let quad = SurfaceGeometry.enclosingQuad(hull)
        XCTAssertEqual(quad.count, 4)
        XCTAssertEqual(SurfaceGeometry.polygonArea(quad), 100.0, accuracy: 1.0)
        // Encloses the hull: never smaller than the hull area.
        XCTAssertGreaterThanOrEqual(SurfaceGeometry.polygonArea(quad),
                                    SurfaceGeometry.polygonArea(hull) - 1e-9)
    }

    func testEnclosingQuadPassesThroughFourPoints() {
        let quad = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        XCTAssertEqual(SurfaceGeometry.enclosingQuad(quad), quad)
    }

    func testOverlapOverSmaller() {
        let big = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        let nested = [CGPoint(x: 2, y: 2), CGPoint(x: 5, y: 2), CGPoint(x: 5, y: 5), CGPoint(x: 2, y: 5)]
        let half = [CGPoint(x: 5, y: 0), CGPoint(x: 15, y: 0), CGPoint(x: 15, y: 10), CGPoint(x: 5, y: 10)]
        let apart = [CGPoint(x: 20, y: 0), CGPoint(x: 25, y: 0), CGPoint(x: 25, y: 5), CGPoint(x: 20, y: 5)]
        XCTAssertEqual(SurfaceGeometry.overlapOverSmaller(nested, big), 1.0, accuracy: 0.05)
        XCTAssertEqual(SurfaceGeometry.overlapOverSmaller(big, half), 0.5, accuracy: 0.05)
        XCTAssertEqual(SurfaceGeometry.overlapOverSmaller(apart, big), 0.0, accuracy: 0.01)
    }

    func testOrderedCornersRotatedQuad() {
        // A visibly rotated square; sum/diff heuristics break on these.
        let rotated = [CGPoint(x: 3, y: 4), CGPoint(x: 0, y: 3), CGPoint(x: 4, y: 1), CGPoint(x: 1, y: 0)]
        let o = SurfaceGeometry.orderedCorners(rotated)
        XCTAssertEqual(o, [CGPoint(x: 1, y: 0), CGPoint(x: 4, y: 1), CGPoint(x: 3, y: 4), CGPoint(x: 0, y: 3)])
    }

    func testOrderedCornersTopLeftOrigin() {
        // scrambled; TL=(0,0) TR=(4,0) BR=(4,3) BL=(0,3)
        let scrambled = [CGPoint(x: 4, y: 3), CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 3), CGPoint(x: 4, y: 0)]
        let o = SurfaceGeometry.orderedCorners(scrambled)
        XCTAssertEqual(o, [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 4, y: 3), CGPoint(x: 0, y: 3)])
    }

    func testBoundingBoxArea() {
        let tri = [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 2, y: 3)]
        XCTAssertEqual(SurfaceGeometry.boundingBoxArea(tri), 12.0, accuracy: 1e-9) // 4 x 3 bbox
    }

    func testContains() {
        let sq = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        XCTAssertTrue(SurfaceGeometry.contains(CGPoint(x: 5, y: 5), in: sq))
        XCTAssertFalse(SurfaceGeometry.contains(CGPoint(x: 15, y: 5), in: sq))
    }
}
