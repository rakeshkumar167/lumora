import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LumoraKit

final class ContourTracerTests: XCTestCase {
    private func grid(_ w: Int, _ h: Int, _ paint: (Int, Int) -> Bool) -> [Bool] {
        var b = [Bool](repeating: false, count: w * h)
        for y in 0..<h { for x in 0..<w { b[y * w + x] = paint(x, y) } }
        return b
    }

    private func bbox(_ pts: [CGPoint]) -> (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
        var a = pts[0], b = pts[0]
        for p in pts { a.x = min(a.x, p.x); a.y = min(a.y, p.y); b.x = max(b.x, p.x); b.y = max(b.y, p.y) }
        return (a.x, a.y, b.x, b.y)
    }

    func testTracesFilledRectangleBoundary() {
        let b = grid(24, 24) { x, y in (5...18).contains(x) && (5...18).contains(y) }
        let cs = ContourTracer.traceContours(binary: b, width: 24, height: 24)
        XCTAssertEqual(cs.count, 1)
        let bb = bbox(cs[0].points)
        XCTAssertEqual(bb.minX, 5, accuracy: 1); XCTAssertEqual(bb.minY, 5, accuracy: 1)
        XCTAssertEqual(bb.maxX, 18, accuracy: 1); XCTAssertEqual(bb.maxY, 18, accuracy: 1)
        XCTAssertNil(cs[0].parentIndex)
    }

    func testTwoSeparateRectanglesAreBothTopLevel() {
        let b = grid(40, 20) { x, y in ((2...10).contains(x) || (28...36).contains(x)) && (4...14).contains(y) }
        let cs = ContourTracer.traceContours(binary: b, width: 40, height: 20)
        XCTAssertEqual(cs.count, 2)
        XCTAssertTrue(cs.allSatisfy { $0.parentIndex == nil })
    }

    func testInnerComponentIsChildOfSurroundingFrame() {
        // A square ring (frame) with a separate filled square inside its hole.
        let b = grid(40, 40) { x, y in
            let onFrame = (5...34).contains(x) && (5...34).contains(y)
                && !((9...30).contains(x) && (9...30).contains(y))
            let inner = (15...24).contains(x) && (15...24).contains(y)
            return onFrame || inner
        }
        let cs = ContourTracer.traceContours(binary: b, width: 40, height: 40)
        XCTAssertEqual(cs.count, 2)
        // Exactly one contour has the other as parent.
        let children = cs.filter { $0.parentIndex != nil }
        XCTAssertEqual(children.count, 1)
        // The child is the smaller (inner) contour.
        let childIdx = cs.firstIndex { $0.parentIndex != nil }!
        let parentIdx = cs[childIdx].parentIndex!
        XCTAssertLessThan(ContourTracer.polygonArea(cs[childIdx].points),
                          ContourTracer.polygonArea(cs[parentIdx].points))
    }

    func testWritesContourOverlayArtifactWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["CONTOUR_OVERLAY"] == "1" else {
            throw XCTSkip("set CONTOUR_OVERLAY=1 to write the overlay artifact")
        }
        // Binary: an outer frame with a nested filled square inside its hole,
        // plus a separate square elsewhere — exercises nesting + siblings.
        let w = 200, h = 160
        let b = grid(w, h) { x, y in
            let frame = (20...120).contains(x) && (20...120).contains(y)
                && !((34...106).contains(x) && (34...106).contains(y))
            let nested = (55...85).contains(x) && (55...85).contains(y)
            let sibling = (150...185).contains(x) && (40...110).contains(y)
            return frame || nested || sibling
        }
        let contours = ContourTracer.traceContours(binary: b, width: w, height: h)

        let cs = CGColorSpaceCreateDeviceRGB()
        let out = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        out.setFillColor(CGColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)); out.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let H = CGFloat(h)
        let palette = [CGColor(red: 0.2, green: 1, blue: 0.4, alpha: 1),
                       CGColor(red: 1, green: 0.7, blue: 0.2, alpha: 1),
                       CGColor(red: 0.4, green: 0.6, blue: 1, alpha: 1)]
        for (i, c) in contours.enumerated() {
            let poly = PolygonApproximator.simplify(c.points, epsilon: 2.0)
            let depth = c.parentIndex == nil ? 0 : 1
            out.setStrokeColor(palette[(depth + i) % palette.count]); out.setLineWidth(2)
            guard let first = poly.first else { continue }
            out.move(to: CGPoint(x: first.x, y: H - first.y))
            for p in poly.dropFirst() { out.addLine(to: CGPoint(x: p.x, y: H - p.y)) }
            out.closePath(); out.strokePath()
        }
        let img = out.makeImage()!
        let dir = ProcessInfo.processInfo.environment["CONTOUR_OVERLAY_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent("contour_overlay.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        print("CONTOUR_OVERLAY written to: \(url.path) — contours: \(contours.count), nested: \(contours.filter { $0.parentIndex != nil }.count)")
    }
}
