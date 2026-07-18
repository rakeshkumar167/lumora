import XCTest
import CoreGraphics
@testable import LumoraKit

final class SurfaceAnalyzerTests: XCTestCase {
    private func solidRGB(_ w: Int, _ h: Int, _ c: (UInt8, UInt8, UInt8)) -> RGBImage {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) { px[i * 4] = c.0; px[i * 4 + 1] = c.1; px[i * 4 + 2] = c.2; px[i * 4 + 3] = 255 }
        return RGBImage(width: w, height: h, pixels: px)
    }

    private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [CGPoint] {
        [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
    }

    func testRectangleGeometry() {
        let img = solidRGB(100, 100, (10, 20, 30))
        let p = SurfaceAnalyzer.properties(of: rect(10, 20, 50, 60), in: img)
        XCTAssertEqual(p.area, 40 * 40, accuracy: 1)
        XCTAssertEqual(p.perimeter, 2 * (40 + 40), accuracy: 1)
        XCTAssertEqual(Double(p.centroid.x), 30, accuracy: 1)
        XCTAssertEqual(Double(p.centroid.y), 40, accuracy: 1)
        XCTAssertEqual(p.aspectRatio, 1, accuracy: 0.01)
    }

    func testAverageColorOfRegion() {
        let img = solidRGB(50, 50, (200, 100, 50))
        let c = SurfaceAnalyzer.averageColor(of: rect(5, 5, 45, 45), in: img)
        XCTAssertEqual(c.r, 200.0 / 255, accuracy: 0.02)
        XCTAssertEqual(c.g, 100.0 / 255, accuracy: 0.02)
        XCTAssertEqual(c.b, 50.0 / 255, accuracy: 0.02)
    }

    func testOrientationOfWideRectangleIsHorizontal() {
        let img = solidRGB(100, 100, (0, 0, 0))
        let p = SurfaceAnalyzer.properties(of: rect(10, 40, 90, 55), in: img)
        // Longest edge is horizontal → orientation ≈ 0.
        XCTAssertEqual(min(p.orientation, .pi - p.orientation), 0, accuracy: 0.05)
    }
}
