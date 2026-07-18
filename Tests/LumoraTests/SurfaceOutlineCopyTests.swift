import XCTest
@testable import LumoraKit

final class SurfaceOutlineCopyTests: XCTestCase {
    private func sourceSurface() -> Surface {
        var s = Surface(
            name: "Wall Panel",
            points: [
                CGPoint(x: 0.1, y: 0.2),
                CGPoint(x: 0.4, y: 0.25),
                CGPoint(x: 0.4, y: 0.6),
                CGPoint(x: 0.1, y: 0.55),
            ],
            shape: .quad,
            media: .effect(.aurora, .magenta, .violet)
        )
        s.rotation = 0.35
        s.opacity = 0.7
        s.zIndex = 3
        s.isVisible = false
        return s
    }

    func testPreservesGeometryAndDisplayProperties() {
        let src = sourceSurface()
        let copy = src.outlineCopyWithGrid()
        XCTAssertEqual(copy.name, src.name)
        XCTAssertEqual(copy.points, src.points)
        XCTAssertEqual(copy.shape, src.shape)
        XCTAssertEqual(copy.rotation, src.rotation)
        XCTAssertEqual(copy.opacity, src.opacity)
        XCTAssertEqual(copy.zIndex, src.zIndex)
        XCTAssertEqual(copy.isVisible, src.isVisible)
    }

    func testGetsFreshIdentity() {
        let src = sourceSurface()
        let copy = src.outlineCopyWithGrid()
        XCTAssertNotEqual(copy.id, src.id)
    }

    func testMediaResetToGridDefault() {
        let copy = sourceSurface().outlineCopyWithGrid()
        XCTAssertEqual(
            copy.media,
            .effect(.grid, .cyan, RGBAColor(r: 0.05, g: 0.06, b: 0.09))
        )
    }

    func testSourceIsNotMutated() {
        let src = sourceSurface()
        let originalID = src.id
        _ = src.outlineCopyWithGrid()
        XCTAssertEqual(src.id, originalID)
        XCTAssertEqual(src.media, .effect(.aurora, .magenta, .violet))
    }
}
