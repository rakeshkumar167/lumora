import XCTest
import CoreGraphics
@testable import LumoraKit

final class PolygonApproximatorTests: XCTestCase {
    func testStraightLineReducesToEndpoints() {
        let pts = (0...10).map { CGPoint(x: Double($0), y: 0.0) }
        let s = PolygonApproximator.simplify(pts, epsilon: 0.5)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s.first, CGPoint(x: 0, y: 0))
        XCTAssertEqual(s.last, CGPoint(x: 10, y: 0))
    }

    func testRightAngleKeepsTheCorner() {
        var pts = (0...10).map { CGPoint(x: Double($0), y: 0.0) }
        pts += (1...10).map { CGPoint(x: 10.0, y: Double($0)) }
        let s = PolygonApproximator.simplify(pts, epsilon: 0.5)
        XCTAssertEqual(s.count, 3, "start, corner, end")
        XCTAssertEqual(s[1], CGPoint(x: 10, y: 0))
    }

    func testJitterWithinEpsilonIsRemoved() {
        let pts = (0...10).map { CGPoint(x: Double($0), y: ($0 % 2 == 0) ? 0.2 : -0.2) }
        let s = PolygonApproximator.simplify(pts, epsilon: 0.5)
        XCTAssertEqual(s.count, 2)
    }
}
