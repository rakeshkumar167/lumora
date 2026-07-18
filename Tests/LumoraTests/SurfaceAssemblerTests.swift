import XCTest
import CoreGraphics
@testable import LumoraKit

final class SurfaceAssemblerTests: XCTestCase {
    private func solid(_ w: Int, _ h: Int) -> RGBImage {
        RGBImage(width: w, height: h, pixels: [UInt8](repeating: 128, count: w * h * 4))
    }
    private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [CGPoint] {
        [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
    }

    func testNormalizesAndSortsBySize() {
        let img = solid(100, 100)
        let small = rect(70, 70, 90, 90)
        let big = rect(5, 5, 60, 60)
        let out = SurfaceAssembler.assemble([small, big], rgb: img)
        XCTAssertEqual(out.count, 2)
        XCTAssertGreaterThan(out[0].area, out[1].area, "largest first")
        for s in out {
            for p in s.polygon {
                XCTAssertTrue((0.0...1.0).contains(Double(p.x)))
                XCTAssertTrue((0.0...1.0).contains(Double(p.y)))
            }
        }
    }

    func testMarksRectangleAsQuad() {
        let img = solid(100, 100)
        let out = SurfaceAssembler.assemble([rect(10, 10, 70, 60)], rgb: img)
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].isQuad)
        XCTAssertEqual(out[0].polygon.count, 4)
    }

    func testCapsToMaxResults() {
        let img = solid(200, 200)
        var polys: [[CGPoint]] = []
        for i in 0..<20 { let x = Double(i % 5) * 40; let y = Double(i / 5) * 40; polys.append(rect(x + 2, y + 2, x + 30, y + 30)) }
        let out = SurfaceAssembler.assemble(polys, rgb: img, config: .init(maxResults: 6, quadEpsilonFraction: 0.02))
        XCTAssertLessThanOrEqual(out.count, 6)
    }
}
