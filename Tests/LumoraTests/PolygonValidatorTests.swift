import XCTest
import CoreGraphics
@testable import LumoraKit

final class PolygonValidatorTests: XCTestCase {
    private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [CGPoint] {
        [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
    }

    func testAcceptsAReasonableRectangle() {
        let poly = rect(20, 20, 60, 55) // ~26% of a 100x100 frame, well-filled
        XCTAssertTrue(PolygonValidator.isValid(poly, frameWidth: 100, frameHeight: 100))
    }

    func testRejectsTinyPolygon() {
        let poly = rect(10, 10, 13, 13) // ~0.09% of frame
        XCTAssertFalse(PolygonValidator.isValid(poly, frameWidth: 100, frameHeight: 100))
    }

    func testRejectsFrameFillingPolygon() {
        let poly = rect(1, 1, 99, 99) // ~96% of frame
        XCTAssertFalse(PolygonValidator.isValid(poly, frameWidth: 100, frameHeight: 100))
    }

    func testRejectsThinSliver() {
        let poly = rect(5, 48, 95, 50) // 90x2, aspect 45
        XCTAssertFalse(PolygonValidator.isValid(poly, frameWidth: 100, frameHeight: 100))
    }

    func testRejectsSelfIntersectingBowtie() {
        // Bowtie: crossing edges.
        let poly = [CGPoint(x: 20, y: 20), CGPoint(x: 60, y: 55),
                    CGPoint(x: 60, y: 20), CGPoint(x: 20, y: 55)]
        XCTAssertFalse(PolygonValidator.isValid(poly, frameWidth: 100, frameHeight: 100))
    }
}
