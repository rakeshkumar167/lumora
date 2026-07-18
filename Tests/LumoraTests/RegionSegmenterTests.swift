import XCTest
import CoreGraphics
@testable import LumoraKit

final class RegionSegmenterTests: XCTestCase {
    /// EdgeMap whose true pixels form a rectangle OUTLINE (its border only).
    private func rectangleOutline(w: Int, h: Int, x0: Int, y0: Int, x1: Int, y1: Int) -> EdgeMap {
        var e = [Bool](repeating: false, count: w * h)
        for x in x0...x1 { e[y0 * w + x] = true; e[y1 * w + x] = true }
        for y in y0...y1 { e[y * w + x0] = true; e[y * w + x1] = true }
        return EdgeMap(width: w, height: h, edges: e)
    }

    private func bbox(_ p: [CGPoint]) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var a = p[0], b = p[0]
        for q in p { a.x = min(a.x, q.x); a.y = min(a.y, q.y); b.x = max(b.x, q.x); b.y = max(b.y, q.y) }
        return (a.x, a.y, b.x, b.y)
    }

    func testInteriorRegionRecoveredFromRectangleOutline() {
        let edges = rectangleOutline(w: 60, h: 60, x0: 15, y0: 15, x1: 45, y1: 45)
        let regions = RegionSegmenter.regions(from: edges)
        // Expect at least the interior region and the exterior region.
        XCTAssertGreaterThanOrEqual(regions.count, 2)
        // One region's bbox should sit inside the outline (the interior).
        let interior = regions.first { r in
            let (minX, minY, maxX, maxY) = bbox(r.points)
            return minX >= 14 && minY >= 14 && maxX <= 46 && maxY <= 46
                && (maxX - minX) > 15 && (maxY - minY) > 15
        }
        XCTAssertNotNil(interior, "interior region should be recovered")
    }

    func testEmptyEdgesYieldOneRegion() {
        let edges = EdgeMap(width: 30, height: 30, edges: [Bool](repeating: false, count: 900))
        // No barriers → the whole frame is one region.
        XCTAssertEqual(RegionSegmenter.regions(from: edges).count, 1)
    }
}
