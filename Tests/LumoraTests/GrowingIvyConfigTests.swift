import XCTest
@testable import LumoraKit

final class GrowingIvyConfigTests: XCTestCase {
    func testDefaultDirectionIsTopDown() {
        XCTAssertEqual(GrowingIvyConfig().direction, .topDown)
    }

    func testGrowthVectors() {
        XCTAssertEqual(IvyDirection.topDown.growth, CGVector(dx: 0, dy: 1))
        XCTAssertEqual(IvyDirection.bottomUp.growth, CGVector(dx: 0, dy: -1))
        XCTAssertEqual(IvyDirection.leftToRight.growth, CGVector(dx: 1, dy: 0))
        XCTAssertEqual(IvyDirection.rightToLeft.growth, CGVector(dx: -1, dy: 0))
    }

    func testAllCasesHaveDisplayName() {
        for d in IvyDirection.allCases { XCTAssertFalse(d.displayName.isEmpty) }
    }

    func testTolerantDecodeDefaultsToTopDown() throws {
        let data = "{}".data(using: .utf8)!
        let cfg = try JSONDecoder().decode(GrowingIvyConfig.self, from: data)
        XCTAssertEqual(cfg.direction, .topDown)
    }

    func testRoundTripEncodesDirection() throws {
        let cfg = GrowingIvyConfig(direction: .leftToRight)
        let data = try JSONEncoder().encode(cfg)
        XCTAssertEqual(try JSONDecoder().decode(GrowingIvyConfig.self, from: data), cfg)
    }
}
