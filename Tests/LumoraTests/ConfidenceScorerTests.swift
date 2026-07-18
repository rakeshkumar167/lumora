import XCTest
import CoreGraphics
@testable import LumoraKit

final class ConfidenceScorerTests: XCTestCase {
    private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [CGPoint] {
        [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
    }

    func testCleanRectangleScoresHigh() {
        let s = ConfidenceScorer.score(rect(20, 20, 70, 65), frameWidth: 100, frameHeight: 100)
        XCTAssertGreaterThan(s, 0.6)
    }

    func testThinSliverScoresLowerThanRectangle() {
        let sliver = ConfidenceScorer.score(rect(5, 49, 95, 51), frameWidth: 100, frameHeight: 100)
        let clean = ConfidenceScorer.score(rect(20, 20, 70, 65), frameWidth: 100, frameHeight: 100)
        XCTAssertLessThan(sliver, clean)
    }

    func testScoreInUnitRange() {
        let s = ConfidenceScorer.score(rect(0, 0, 100, 100), frameWidth: 100, frameHeight: 100)
        XCTAssertGreaterThanOrEqual(s, 0); XCTAssertLessThanOrEqual(s, 1)
    }
}
