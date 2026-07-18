import XCTest
@testable import LumoraKit

final class MorphologyTests: XCTestCase {
    func testDilateGrowsSinglePixelToBox() {
        var b = [Bool](repeating: false, count: 25) // 5x5
        b[2 * 5 + 2] = true
        let d = Morphology.dilate(b, width: 5, height: 5, radius: 1)
        // 3x3 box around (2,2) is now true.
        for y in 1...3 { for x in 1...3 { XCTAssertTrue(d[y * 5 + x]) } }
        XCTAssertFalse(d[0])            // corner untouched
        XCTAssertFalse(d[4 * 5 + 4])
    }

    func testDilateSealsAOnePixelGap() {
        // Two true pixels with a one-pixel gap → radius-1 dilation connects them.
        var b = [Bool](repeating: false, count: 15) // 5x3
        b[1 * 5 + 1] = true; b[1 * 5 + 3] = true
        let d = Morphology.dilate(b, width: 5, height: 3, radius: 1)
        XCTAssertTrue(d[1 * 5 + 2], "the gap pixel is filled")
    }

    func testDilateRadiusZeroIsIdentity() {
        var b = [Bool](repeating: false, count: 9)
        b[4] = true
        XCTAssertEqual(Morphology.dilate(b, width: 3, height: 3, radius: 0), b)
    }
}
