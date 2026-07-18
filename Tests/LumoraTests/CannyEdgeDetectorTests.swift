import XCTest
@testable import LumoraKit

final class CannyEdgeDetectorTests: XCTestCase {
    /// White rectangle (10,10)-(30,30) on a black 40×40 field.
    private func rectangleImage() -> GrayImage {
        let w = 40, h = 40
        var px = [Float](repeating: 0, count: w * h)
        for y in 10..<30 { for x in 10..<30 { px[y * w + x] = 1 } }
        return GrayImage(width: w, height: h, pixels: px)
    }

    private func hasEdgeNear(_ e: EdgeMap, _ cx: Int, _ cy: Int, radius: Int = 2) -> Bool {
        for dy in -radius...radius { for dx in -radius...radius {
            let x = cx + dx, y = cy + dy
            if x >= 0, x < e.width, y >= 0, y < e.height, e.edges[y * e.width + x] { return true }
        } }
        return false
    }

    func testDetectsRectangleBorderNotInterior() {
        let e = CannyEdgeDetector.detect(rectangleImage())
        XCTAssertTrue(e.edges.contains(true), "should find some edges")
        // Border midpoints (top, bottom, left, right of the rectangle).
        XCTAssertTrue(hasEdgeNear(e, 20, 10), "top border")
        XCTAssertTrue(hasEdgeNear(e, 20, 30), "bottom border")
        XCTAssertTrue(hasEdgeNear(e, 10, 20), "left border")
        XCTAssertTrue(hasEdgeNear(e, 30, 20), "right border")
        // No edges deep inside the flat rectangle or the flat background.
        XCTAssertFalse(hasEdgeNear(e, 20, 20, radius: 3), "interior is flat")
        XCTAssertFalse(hasEdgeNear(e, 2, 2, radius: 1), "far background is flat")
    }

    func testFlatImageHasNoEdges() {
        let flat = GrayImage(width: 20, height: 20, pixels: [Float](repeating: 0.5, count: 400))
        let e = CannyEdgeDetector.detect(flat)
        XCTAssertFalse(e.edges.contains(true), "a flat image has no edges")
    }
}
