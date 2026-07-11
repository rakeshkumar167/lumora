import CoreGraphics
import XCTest
@testable import LumoraKit

final class ChristmasLightsTests: XCTestCase {
    func testPaletteHasFiveDistinctColors() {
        let p = ChristmasLights.palette
        XCTAssertEqual(p.count, 5)
        XCTAssertEqual(Set(p).count, 5)
    }

    func testAlwaysASingleStrand() {
        XCTAssertEqual(ChristmasLights.strands(in: CGSize(width: 400, height: 120)).count, 1)
        XCTAssertEqual(ChristmasLights.strands(in: CGSize(width: 400, height: 900)).count, 1)
    }

    func testBulbCountScalesWithWidthMinThree() {
        let narrow = ChristmasLights.strands(in: CGSize(width: 120, height: 400))
        let wide = ChristmasLights.strands(in: CGSize(width: 1200, height: 400))
        XCTAssertGreaterThanOrEqual(narrow[0].bulbs.count, 3)
        XCTAssertGreaterThan(wide[0].bulbs.count, narrow[0].bulbs.count)
    }

    func testStrandSagsDownwardEndsPinned() {
        let size = CGSize(width: 600, height: 400)
        let strand = ChristmasLights.strands(in: size)[0]
        let first = strand.bulbs.first!, last = strand.bulbs.last!, mid = strand.bulbs[strand.bulbs.count / 2]
        // Ends share the pin height; the middle dips below (larger y = lower).
        XCTAssertEqual(first.y, last.y, accuracy: 1.0)
        XCTAssertGreaterThan(mid.y, first.y + 1)
    }

    func testAllBulbsInsideBounds() {
        let size = CGSize(width: 600, height: 400)
        for strand in ChristmasLights.strands(in: size) {
            for b in strand.bulbs {
                XCTAssertGreaterThanOrEqual(b.x, 0); XCTAssertLessThanOrEqual(b.x, size.width)
                XCTAssertGreaterThanOrEqual(b.y, 0); XCTAssertLessThanOrEqual(b.y, size.height)
            }
        }
    }
}
