import XCTest
@testable import LumoraKit

final class ConnectedComponentsTests: XCTestCase {
    /// Paint filled rectangles (true) into a binary grid.
    private func grid(_ w: Int, _ h: Int, _ rects: [(Int, Int, Int, Int)]) -> [Bool] {
        var b = [Bool](repeating: false, count: w * h)
        for (x0, y0, x1, y1) in rects { for y in y0...y1 { for x in x0...x1 { b[y * w + x] = true } } }
        return b
    }

    func testSingleComponent() {
        let f = ConnectedComponents.label(grid(20, 20, [(5, 5, 12, 12)]), width: 20, height: 20)
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f.labels[8 * 20 + 8], 1)
        XCTAssertEqual(f.labels[0], 0)
    }

    func testTwoSeparateComponents() {
        let f = ConnectedComponents.label(grid(30, 20, [(2, 2, 8, 8), (18, 2, 26, 8)]), width: 30, height: 20)
        XCTAssertEqual(f.count, 2)
        XCTAssertNotEqual(f.labels[5 * 30 + 5], f.labels[5 * 30 + 22])
        XCTAssertGreaterThan(f.labels[5 * 30 + 5], 0)
        XCTAssertGreaterThan(f.labels[5 * 30 + 22], 0)
    }

    func testDiagonalPixelsAre8Connected() {
        var b = [Bool](repeating: false, count: 9)
        b[0] = true; b[4] = true // (0,0) and (1,1) touch diagonally
        let f = ConnectedComponents.label(b, width: 3, height: 3)
        XCTAssertEqual(f.count, 1)
    }
}
