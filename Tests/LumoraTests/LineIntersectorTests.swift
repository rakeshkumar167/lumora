import XCTest
import CoreGraphics
@testable import LumoraKit

final class LineIntersectorTests: XCTestCase {
    func testHorizontalAndVerticalCrossAtExpectedPoint() {
        let hor = DetectedLine(p1: CGPoint(x: 0, y: 20), p2: CGPoint(x: 40, y: 20))
        let ver = DetectedLine(p1: CGPoint(x: 25, y: 0), p2: CGPoint(x: 25, y: 40))
        let pts = LineIntersector.intersections([hor, ver], width: 40, height: 40)
        XCTAssertEqual(pts.count, 1)
        XCTAssertEqual(Double(pts[0].x), 25, accuracy: 1e-6)
        XCTAssertEqual(Double(pts[0].y), 20, accuracy: 1e-6)
    }

    func testParallelLinesProduceNoIntersection() {
        let a = DetectedLine(p1: CGPoint(x: 0, y: 10), p2: CGPoint(x: 40, y: 10))
        let b = DetectedLine(p1: CGPoint(x: 0, y: 30), p2: CGPoint(x: 40, y: 30))
        XCTAssertTrue(LineIntersector.intersections([a, b], width: 40, height: 40).isEmpty)
    }

    func testOutOfFrameIntersectionDiscarded() {
        // Two nearly-horizontal lines meeting far to the right, outside the frame.
        let a = DetectedLine(p1: CGPoint(x: 0, y: 10), p2: CGPoint(x: 40, y: 12))
        let b = DetectedLine(p1: CGPoint(x: 0, y: 30), p2: CGPoint(x: 40, y: 28))
        XCTAssertTrue(LineIntersector.intersections([a, b], width: 40, height: 40).isEmpty)
    }
}
