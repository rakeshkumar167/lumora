import XCTest
import CoreGraphics
@testable import LumoraKit

final class PolygonMergerTests: XCTestCase {
    private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [CGPoint] {
        [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
    }

    func testMergesAdjacentSameColorRectangles() {
        let a = PolygonMerger.Item(polygon: rect(0, 0, 20, 40), color: RGBAColor(r: 0.5, g: 0.5, b: 0.5))
        let b = PolygonMerger.Item(polygon: rect(21, 0, 40, 40), color: RGBAColor(r: 0.52, g: 0.5, b: 0.49))
        let merged = PolygonMerger.merge([a, b])
        XCTAssertEqual(merged.count, 1)
        // Hull spans both.
        let xs = merged[0].map { $0.x }
        XCTAssertEqual(xs.min()!, 0, accuracy: 1); XCTAssertEqual(xs.max()!, 40, accuracy: 1)
    }

    func testKeepsAdjacentDifferentColorRectanglesSeparate() {
        let a = PolygonMerger.Item(polygon: rect(0, 0, 20, 40), color: RGBAColor(r: 0.1, g: 0.1, b: 0.1))
        let b = PolygonMerger.Item(polygon: rect(21, 0, 40, 40), color: RGBAColor(r: 0.9, g: 0.9, b: 0.9))
        XCTAssertEqual(PolygonMerger.merge([a, b]).count, 2)
    }

    func testKeepsFarApartSameColorSeparate() {
        let a = PolygonMerger.Item(polygon: rect(0, 0, 20, 20), color: RGBAColor(r: 0.5, g: 0.5, b: 0.5))
        let b = PolygonMerger.Item(polygon: rect(60, 60, 80, 80), color: RGBAColor(r: 0.5, g: 0.5, b: 0.5))
        XCTAssertEqual(PolygonMerger.merge([a, b]).count, 2)
    }
}
