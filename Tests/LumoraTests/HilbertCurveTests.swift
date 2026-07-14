import CoreGraphics
import XCTest
@testable import LumoraKit

final class HilbertCurveTests: XCTestCase {
    func testOrderNVisitsEveryCellExactlyOnce() {
        for order in 1...5 {
            let pts = HilbertCurve.points(order: order)
            XCTAssertEqual(pts.count, (1 << order) * (1 << order))
            XCTAssertEqual(Set(pts.map { "\(Int($0.x)),\(Int($0.y))" }).count, pts.count)
        }
    }
    func testConsecutiveStepsAreUnitLength() {
        let pts = HilbertCurve.points(order: 4)
        for i in 1..<pts.count {
            let d = abs(pts[i].x - pts[i-1].x) + abs(pts[i].y - pts[i-1].y)
            XCTAssertEqual(d, 1, accuracy: 1e-9)
        }
    }
}
