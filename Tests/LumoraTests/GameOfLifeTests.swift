import XCTest
@testable import LumoraKit

final class GameOfLifeTests: XCTestCase {
    func testBlinkerOscillatesWithPeriodTwo() {
        let cols = 5, rows = 5
        var g = [Bool](repeating: false, count: 25)
        g[1 * 5 + 2] = true; g[2 * 5 + 2] = true; g[3 * 5 + 2] = true   // vertical bar
        let s1 = GameOfLife.step(g, cols: cols, rows: rows)
        // Should become a horizontal bar.
        XCTAssertTrue(s1[2 * 5 + 1] && s1[2 * 5 + 2] && s1[2 * 5 + 3])
        XCTAssertFalse(s1[1 * 5 + 2] || s1[3 * 5 + 2])
        let s2 = GameOfLife.step(s1, cols: cols, rows: rows)
        XCTAssertEqual(s2, g)   // back to the original vertical bar
    }

    func testBlockIsStillLife() {
        let cols = 6, rows = 6
        var g = [Bool](repeating: false, count: 36)
        for (x, y) in [(2, 2), (2, 3), (3, 2), (3, 3)] { g[y * cols + x] = true }
        XCTAssertEqual(GameOfLife.step(g, cols: cols, rows: rows), g)
    }

    func testSeedIsDeterministicAndNonEmpty() {
        let a = GameOfLife.seed(cols: 40, rows: 30, seeds: 20, seedValue: 7)
        let b = GameOfLife.seed(cols: 40, rows: 30, seeds: 20, seedValue: 7)
        XCTAssertEqual(a, b)
        XCTAssertGreaterThan(GameOfLife.population(a), 0)
        // A different seed value gives a different board.
        XCTAssertNotEqual(a, GameOfLife.seed(cols: 40, rows: 30, seeds: 20, seedValue: 8))
    }
}
