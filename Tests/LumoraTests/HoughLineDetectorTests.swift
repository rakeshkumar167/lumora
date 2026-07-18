import XCTest
import CoreGraphics
@testable import LumoraKit

final class HoughLineDetectorTests: XCTestCase {
    func testDetectedLineComputesAngleAndLength() {
        let l = DetectedLine(p1: CGPoint(x: 0, y: 0), p2: CGPoint(x: 3, y: 4))
        XCTAssertEqual(l.length, 5, accuracy: 1e-9)
        XCTAssertEqual(l.angle, atan2(4.0, 3.0), accuracy: 1e-9)
    }

    func testNormalizeAngleFoldsIntoZeroPi() {
        XCTAssertEqual(LineGeometry.normalizeAngle(-0.1), Double.pi - 0.1, accuracy: 1e-9)
        XCTAssertEqual(LineGeometry.normalizeAngle(Double.pi + 0.1), 0.1, accuracy: 1e-9)
    }

    func testAngleDifferenceIsAcute() {
        XCTAssertEqual(LineGeometry.angleDifference(0.1, Double.pi - 0.1), 0.2, accuracy: 1e-9)
        XCTAssertEqual(LineGeometry.angleDifference(0, Double.pi / 2), Double.pi / 2, accuracy: 1e-9)
    }
}
