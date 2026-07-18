import XCTest
import CoreGraphics
@testable import LumoraKit

final class CalibrationMarkerDetectorTests: XCTestCase {
    /// A scene (mid-gray + a bright white distractor rectangle) with four magenta
    /// discs at the given normalized centers.
    private func sceneWithMarkers(_ centers: [(Double, Double)], w: Int = 400, h: Int = 300) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.4, green: 0.42, blue: 0.4, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Bright white distractor — would fool a brightness-only detector.
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: Double(w) * 0.45, y: Double(h) * 0.45, width: 40, height: 30))
        let m = CalibrationPattern.markerColor
        ctx.setFillColor(CGColor(red: m.r, green: m.g, blue: m.b, alpha: 1))
        let r = Double(min(w, h)) * CalibrationPattern.markerRadiusFraction
        for (nx, ny) in centers {
            // CGContext y-up; place discs so top-left-origin normalized maps correctly.
            let cx = nx * Double(w), cy = (1 - ny) * Double(h)
            ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        }
        return ctx.makeImage()!
    }

    func testFindsFourCornersOrdered() {
        let img = sceneWithMarkers([(0.1, 0.1), (0.9, 0.1), (0.9, 0.9), (0.1, 0.9)])
        let corners = CalibrationMarkerDetector.detectCorners(in: img)
        XCTAssertNotNil(corners)
        guard let c = corners else { return }
        XCTAssertEqual(c.count, 4)
        XCTAssertEqual(Double(c[0].x), 0.1, accuracy: 0.05); XCTAssertEqual(Double(c[0].y), 0.1, accuracy: 0.05) // TL
        XCTAssertEqual(Double(c[1].x), 0.9, accuracy: 0.05); XCTAssertEqual(Double(c[1].y), 0.1, accuracy: 0.05) // TR
        XCTAssertEqual(Double(c[2].x), 0.9, accuracy: 0.05); XCTAssertEqual(Double(c[2].y), 0.9, accuracy: 0.05) // BR
        XCTAssertEqual(Double(c[3].x), 0.1, accuracy: 0.05); XCTAssertEqual(Double(c[3].y), 0.9, accuracy: 0.05) // BL
    }

    func testPerspectiveMarkersStillOrderedCorrectly() {
        // Trapezoid (near corners pulled in at the top) — still TL,TR,BR,BL.
        let img = sceneWithMarkers([(0.25, 0.15), (0.75, 0.15), (0.92, 0.85), (0.08, 0.85)])
        let c = CalibrationMarkerDetector.detectCorners(in: img)
        XCTAssertNotNil(c)
        guard let c = c else { return }
        XCTAssertLessThan(Double(c[0].x), 0.5); XCTAssertLessThan(Double(c[0].y), 0.5)   // TL upper-left
        XCTAssertGreaterThan(Double(c[2].x), 0.5); XCTAssertGreaterThan(Double(c[2].y), 0.5) // BR lower-right
    }

    func testReturnsNilWhenNoMarkers() {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertNil(CalibrationMarkerDetector.detectCorners(in: ctx.makeImage()!))
    }
}
