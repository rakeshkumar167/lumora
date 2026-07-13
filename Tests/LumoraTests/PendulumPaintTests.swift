import XCTest
@testable import LumoraKit

final class PendulumPaintTests: XCTestCase {
    func testDeterministicForSameCycle() {
        let a = PendulumPaint.samples(cycle: 7)
        let b = PendulumPaint.samples(cycle: 7)
        XCTAssertEqual(a.count, b.count)
        XCTAssertFalse(a.isEmpty)
        for (p, q) in zip(a, b) {
            XCTAssertEqual(p.x, q.x, accuracy: 1e-12)
            XCTAssertEqual(p.y, q.y, accuracy: 1e-12)
        }
    }

    func testDifferentCyclesDiffer() {
        let a = PendulumPaint.samples(cycle: 1, count: 500)
        let b = PendulumPaint.samples(cycle: 2, count: 500)
        // At least some points must differ between two distinct paintings.
        let differ = zip(a, b).contains { abs($0.x - $1.x) > 1e-6 || abs($0.y - $1.y) > 1e-6 }
        XCTAssertTrue(differ)
    }

    func testPointsStayInUnitBox() {
        for cycle in 0..<12 {
            for p in PendulumPaint.samples(cycle: cycle) {
                XCTAssertGreaterThanOrEqual(p.x, 0.0)
                XCTAssertLessThanOrEqual(p.x, 1.0)
                XCTAssertGreaterThanOrEqual(p.y, 0.0)
                XCTAssertLessThanOrEqual(p.y, 1.0)
            }
        }
    }

    func testSampleCountRespected() {
        let pts = PendulumPaint.samples(cycle: 3, count: 400)
        XCTAssertEqual(pts.count, 400)
    }

    func testStartsNearCenter() {
        // s = 0 has full envelope; but the figure is centered on 0.5,0.5, so the
        // very first point is a finite offset from center, well inside the box.
        let c = PendulumPaint.coefficients(cycle: 5)
        let p0 = PendulumPaint.point(0, c)
        XCTAssertGreaterThan(p0.x, 0.02)
        XCTAssertLessThan(p0.x, 0.98)
        XCTAssertGreaterThan(p0.y, 0.02)
        XCTAssertLessThan(p0.y, 0.98)
    }
}
