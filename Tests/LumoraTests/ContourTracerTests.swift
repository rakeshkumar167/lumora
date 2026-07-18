import XCTest
import CoreGraphics
@testable import LumoraKit

final class ContourTracerTests: XCTestCase {
    private func grid(_ w: Int, _ h: Int, _ paint: (Int, Int) -> Bool) -> [Bool] {
        var b = [Bool](repeating: false, count: w * h)
        for y in 0..<h { for x in 0..<w { b[y * w + x] = paint(x, y) } }
        return b
    }

    private func bbox(_ pts: [CGPoint]) -> (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
        var a = pts[0], b = pts[0]
        for p in pts { a.x = min(a.x, p.x); a.y = min(a.y, p.y); b.x = max(b.x, p.x); b.y = max(b.y, p.y) }
        return (a.x, a.y, b.x, b.y)
    }

    func testTracesFilledRectangleBoundary() {
        let b = grid(24, 24) { x, y in (5...18).contains(x) && (5...18).contains(y) }
        let cs = ContourTracer.traceContours(binary: b, width: 24, height: 24)
        XCTAssertEqual(cs.count, 1)
        let bb = bbox(cs[0].points)
        XCTAssertEqual(bb.minX, 5, accuracy: 1); XCTAssertEqual(bb.minY, 5, accuracy: 1)
        XCTAssertEqual(bb.maxX, 18, accuracy: 1); XCTAssertEqual(bb.maxY, 18, accuracy: 1)
        XCTAssertNil(cs[0].parentIndex)
    }

    func testTwoSeparateRectanglesAreBothTopLevel() {
        let b = grid(40, 20) { x, y in ((2...10).contains(x) || (28...36).contains(x)) && (4...14).contains(y) }
        let cs = ContourTracer.traceContours(binary: b, width: 40, height: 20)
        XCTAssertEqual(cs.count, 2)
        XCTAssertTrue(cs.allSatisfy { $0.parentIndex == nil })
    }

    func testInnerComponentIsChildOfSurroundingFrame() {
        // A square ring (frame) with a separate filled square inside its hole.
        let b = grid(40, 40) { x, y in
            let onFrame = (5...34).contains(x) && (5...34).contains(y)
                && !((9...30).contains(x) && (9...30).contains(y))
            let inner = (15...24).contains(x) && (15...24).contains(y)
            return onFrame || inner
        }
        let cs = ContourTracer.traceContours(binary: b, width: 40, height: 40)
        XCTAssertEqual(cs.count, 2)
        // Exactly one contour has the other as parent.
        let children = cs.filter { $0.parentIndex != nil }
        XCTAssertEqual(children.count, 1)
        // The child is the smaller (inner) contour.
        let childIdx = cs.firstIndex { $0.parentIndex != nil }!
        let parentIdx = cs[childIdx].parentIndex!
        XCTAssertLessThan(ContourTracer.polygonArea(cs[childIdx].points),
                          ContourTracer.polygonArea(cs[parentIdx].points))
    }
}
