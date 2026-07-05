import CoreGraphics
import XCTest
@testable import LumoraKit

final class HomographyTests: XCTestCase {
    private let srcCorners = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100),
        CGPoint(x: 0, y: 100),
    ]

    /// A rect→quad homography must land each source corner exactly on the
    /// corresponding destination corner — including a perspective (non-affine) quad.
    func testRectToQuadMapsCornersExactly() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let quad = [
            CGPoint(x: 10, y: 20),
            CGPoint(x: 210, y: 5),
            CGPoint(x: 190, y: 180),
            CGPoint(x: 30, y: 160),
        ]
        let h = Homography.rectToQuad(rect, quad)
        for i in 0..<4 {
            let p = h.apply(srcCorners[i])
            XCTAssertEqual(p.x, quad[i].x, accuracy: 1e-6)
            XCTAssertEqual(p.y, quad[i].y, accuracy: 1e-6)
        }
    }

    /// Mapping a rect onto an identical rect is the identity (interior points too).
    func testRectToIdenticalRectIsIdentity() {
        let rect = CGRect(x: 0, y: 0, width: 50, height: 80)
        let quad = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 50, y: 0),
            CGPoint(x: 50, y: 80),
            CGPoint(x: 0, y: 80),
        ]
        let p = Homography.rectToQuad(rect, quad).apply(CGPoint(x: 25, y: 40))
        XCTAssertEqual(p.x, 25, accuracy: 1e-6)
        XCTAssertEqual(p.y, 40, accuracy: 1e-6)
    }
}
