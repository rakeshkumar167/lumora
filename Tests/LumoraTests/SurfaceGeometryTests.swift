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

    func testOrderedCornersTopLeftOrigin() {
        // scrambled; TL=(0,0) TR=(4,0) BR=(4,3) BL=(0,3)
        let scrambled = [CGPoint(x: 4, y: 3), CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 3), CGPoint(x: 4, y: 0)]
        let o = SurfaceGeometry.orderedCorners(scrambled)
        XCTAssertEqual(o, [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 4, y: 3), CGPoint(x: 0, y: 3)])
    }

    func testContains() {
        let sq = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        XCTAssertTrue(SurfaceGeometry.contains(CGPoint(x: 5, y: 5), in: sq))
        XCTAssertFalse(SurfaceGeometry.contains(CGPoint(x: 15, y: 5), in: sq))
    }
}
