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

    func testBulbCountFollowsConfig() {
        let s = ChristmasLights.strands(in: CGSize(width: 800, height: 300),
                                        config: .init(bulbCount: 24, sagCount: 2))
        XCTAssertEqual(s[0].bulbs.count, 24)
    }

    func testStrandSagsDownwardEndsPinned() {
        let size = CGSize(width: 600, height: 400)
        let strand = ChristmasLights.strands(in: size)[0]   // default config: 1 sag
        let first = strand.bulbs.first!, last = strand.bulbs.last!, mid = strand.bulbs[strand.bulbs.count / 2]
        // Ends share the pin height; the middle dips below (larger y = lower).
        XCTAssertEqual(first.y, last.y, accuracy: 1.0)
        XCTAssertGreaterThan(mid.y, first.y + 1)
    }

    func testSagCountReturnsToPinAtSwagBoundaries() {
        // 61 bulbs over 3 sags puts swag boundaries exactly on bulbs 20 and 40.
        let bulbs = ChristmasLights.strands(in: CGSize(width: 900, height: 300),
                                            config: .init(bulbCount: 61, sagCount: 3))[0].bulbs
        let pinY = bulbs.first!.y
        XCTAssertEqual(bulbs[20].y, pinY, accuracy: 1.0)   // between swag 1 and 2
        XCTAssertEqual(bulbs[40].y, pinY, accuracy: 1.0)   // between swag 2 and 3
        XCTAssertGreaterThan(bulbs[10].y, pinY + 1)        // dip inside swag 1
    }

    func testGeometryIsHeightIndependent() {
        let cfg = ChristmasLightsConfig(bulbCount: 12, sagCount: 2)
        let short = ChristmasLights.strands(in: CGSize(width: 600, height: 150), config: cfg)[0].bulbs
        let tall = ChristmasLights.strands(in: CGSize(width: 600, height: 600), config: cfg)[0].bulbs
        XCTAssertEqual(short.count, tall.count)
        for (a, b) in zip(short, tall) {
            XCTAssertEqual(a.x, b.x, accuracy: 0.001)
            XCTAssertEqual(a.y, b.y, accuracy: 0.001)   // pinned to top, unaffected by height
        }
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
