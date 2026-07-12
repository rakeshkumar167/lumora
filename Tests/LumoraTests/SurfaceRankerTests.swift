import XCTest
import CoreGraphics
@testable import LumoraKit

final class SurfaceRankerTests: XCTestCase {
    private func square(_ x: Double, _ y: Double, _ s: Double, area: Double, source: QuadSource) -> DetectedQuad {
        DetectedQuad(corners: [CGPoint(x: x, y: y), CGPoint(x: x + s, y: y),
                               CGPoint(x: x + s, y: y + s), CGPoint(x: x, y: y + s)],
                     areaFraction: area, source: source)
    }

    func testDropsBelowMinArea() {
        let small = square(0, 0, 0.1, area: 0.02, source: .plane)
        let out = SurfaceRanker.filterMergeRank([small], config: .init(minAreaFraction: 0.05))
        XCTAssertTrue(out.isEmpty)
    }

    func testSuppressesNestedQuad() {
        let big = square(0, 0, 0.8, area: 0.64, source: .plane)
        let inner = square(0.3, 0.3, 0.1, area: 0.06, source: .object) // centroid inside big
        let out = SurfaceRanker.filterMergeRank([big, inner])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.source, .plane)
    }

    func testPlaneOutranksSlightlyLargerObject() {
        // disjoint quads so neither is suppressed
        let object = square(0, 0, 0.3, area: 0.12, source: .object)
        let plane = square(0.6, 0.6, 0.3, area: 0.10, source: .plane)
        let out = SurfaceRanker.filterMergeRank([object, plane], config: .init(planeBoost: 1.35))
        XCTAssertEqual(out.first?.source, .plane) // 0.10*1.35 = 0.135 > 0.12
    }

    func testCapsAtMaxResults() {
        var quads: [DetectedQuad] = []
        for i in 0..<10 { quads.append(square(Double(i) * 1.5, 0, 0.5, area: 0.08 + Double(i) * 0.001, source: .plane)) }
        let out = SurfaceRanker.filterMergeRank(quads, config: .init(maxResults: 3))
        XCTAssertEqual(out.count, 3)
    }
}
