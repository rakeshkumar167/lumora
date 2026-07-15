import XCTest
@testable import LumoraKit
final class StrangeAttractorTests: XCTestCase {
    func testLorenzStaysBoundedAndFinite() {
        let pts = StrangeAttractor.lorenz(steps: 5000, dt: 0.005)
        XCTAssertEqual(pts.count, 5000)
        for p in pts {
            XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.z.isFinite)
            XCTAssertLessThan(abs(p.x), 100); XCTAssertLessThan(abs(p.y), 100); XCTAssertLessThan(abs(p.z), 100)
        }
    }
    func testDeterministic() {
        XCTAssertEqual(StrangeAttractor.lorenz(steps: 100, dt: 0.01).last!.x,
                       StrangeAttractor.lorenz(steps: 100, dt: 0.01).last!.x, accuracy: 1e-12)
    }
}
