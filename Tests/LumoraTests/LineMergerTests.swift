import XCTest
import CoreGraphics
@testable import LumoraKit

final class LineMergerTests: XCTestCase {
    func testMergesTwoNearlyCollinearSegments() {
        // Same row, slight vertical jitter, small gap → one line.
        let a = DetectedLine(p1: CGPoint(x: 0, y: 20), p2: CGPoint(x: 25, y: 20))
        let b = DetectedLine(p1: CGPoint(x: 27, y: 21), p2: CGPoint(x: 50, y: 21))
        let merged = LineMerger.merge([a, b])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].length, 50, accuracy: 3)
    }

    func testKeepsSeparateParallelLinesApart() {
        // Two horizontals far apart vertically → stay two.
        let a = DetectedLine(p1: CGPoint(x: 0, y: 5), p2: CGPoint(x: 40, y: 5))
        let b = DetectedLine(p1: CGPoint(x: 0, y: 35), p2: CGPoint(x: 40, y: 35))
        XCTAssertEqual(LineMerger.merge([a, b]).count, 2)
    }

    func testKeepsPerpendicularLinesApart() {
        let a = DetectedLine(p1: CGPoint(x: 0, y: 20), p2: CGPoint(x: 40, y: 20))
        let b = DetectedLine(p1: CGPoint(x: 20, y: 0), p2: CGPoint(x: 20, y: 40))
        XCTAssertEqual(LineMerger.merge([a, b]).count, 2)
    }
}
