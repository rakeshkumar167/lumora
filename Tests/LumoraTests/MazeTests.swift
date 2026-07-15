import XCTest
@testable import LumoraKit

final class MazeTests: XCTestCase {
    func testPerfectMazeHasExactlyOnePathBetweenAnyTwoCells() {
        let m = Maze.generate(cols: 12, rows: 8, seed: 3)
        // A perfect maze on N cells is a spanning tree: exactly N-1 carved edges.
        XCTAssertEqual(m.passages.count, 12 * 8 - 1)
        XCTAssertTrue(m.isFullyConnected())
    }
    func testSolveFindsPathFromStartToEnd() {
        let m = Maze.generate(cols: 12, rows: 8, seed: 3)
        let path = m.solve()
        XCTAssertEqual(path.first, MazeCell(x: 0, y: 0))
        XCTAssertEqual(path.last, MazeCell(x: 11, y: 7))
        for i in 1..<path.count { XCTAssertTrue(m.connected(path[i-1], path[i])) }
    }
    func testDeterministicForSeed() {
        XCTAssertEqual(Maze.generate(cols: 10, rows: 10, seed: 9).passages,
                       Maze.generate(cols: 10, rows: 10, seed: 9).passages)
    }
}
