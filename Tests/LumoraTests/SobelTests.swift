import XCTest
@testable import LumoraKit

final class SobelTests: XCTestCase {
    /// A vertical edge: left half 0, right half 1.
    private func verticalEdge(w: Int = 8, h: Int = 6) -> GrayImage {
        var px = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { px[y * w + x] = x < w / 2 ? 0 : 1 } }
        return GrayImage(width: w, height: h, pixels: px)
    }

    func testGradientIsLargeOnTheEdgeColumn() {
        let g = Sobel.gradients(verticalEdge())
        // At the boundary (x = 3→4) magnitude is high; deep in a flat region it is ~0.
        let onEdge = g.magnitude[3 * 8 + 3]
        let flat = g.magnitude[3 * 8 + 0]
        XCTAssertGreaterThan(onEdge, 0.5)
        XCTAssertLessThan(flat, 1e-3)
    }

    func testOrientationOnVerticalEdgeIsHorizontal() {
        let g = Sobel.gradients(verticalEdge())
        // Gradient of a left-dark→right-bright edge points in +x: angle ≈ 0.
        let angle = g.orientation[3 * 8 + 3]
        XCTAssertEqual(angle, 0, accuracy: 0.2)
    }
}
