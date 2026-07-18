import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
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

    func testWritesRegionOverlayArtifactWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["REGION_OVERLAY"] == "1" else {
            throw XCTSkip("set REGION_OVERLAY=1 to write the overlay artifact")
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let maxDim = Int(ProcessInfo.processInfo.environment["REGION_MAXDIM"] ?? "1000")!

        // Source: a real photo if REGION_IMAGE is set, else a synthetic room.
        let source: CGImage
        if let path = ProcessInfo.processInfo.environment["REGION_IMAGE"] {
            let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
            source = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        } else {
            let w = 320, h = 240
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(red: 0.82, green: 0.80, blue: 0.76, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setFillColor(CGColor(red: 0.55, green: 0.52, blue: 0.48, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h / 3))
            ctx.setFillColor(CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)); ctx.fill(CGRect(x: 110, y: 120, width: 110, height: 70))
            source = ctx.makeImage()!
        }

        let gray = ImagePreprocessor.grayscale(from: source, maxDimension: maxDim)
        let edges = CannyEdgeDetector.detect(gray)
        let regions = RegionSegmenter.regions(from: edges)
        let valid = regions.filter { PolygonValidator.isValid($0.points, frameWidth: gray.width, frameHeight: gray.height) }

        let W = gray.width, H = gray.height
        let out = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        out.draw(source, in: CGRect(x: 0, y: 0, width: W, height: H))
        out.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)); out.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let fH = CGFloat(H)
        let palette = [CGColor(red: 0.2, green: 1, blue: 0.5, alpha: 1), CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 1),
                       CGColor(red: 0.4, green: 0.6, blue: 1, alpha: 1), CGColor(red: 1, green: 0.4, blue: 0.8, alpha: 1),
                       CGColor(red: 1, green: 0.9, blue: 0.3, alpha: 1)]
        for (i, r) in valid.enumerated() {
            guard let first = r.points.first else { continue }
            let color = palette[i % palette.count]
            out.setStrokeColor(color); out.setLineWidth(2.5)
            out.setFillColor(color.copy(alpha: 0.18)!)
            out.move(to: CGPoint(x: first.x, y: fH - first.y))
            for p in r.points.dropFirst() { out.addLine(to: CGPoint(x: p.x, y: fH - p.y)) }
            out.closePath(); out.drawPath(using: .fillStroke)
        }
        let img = out.makeImage()!
        let dir = ProcessInfo.processInfo.environment["REGION_OVERLAY_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent("region_overlay.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        print("REGION_OVERLAY \(W)x\(H) regions:\(regions.count) valid:\(valid.count) -> \(url.path)")
    }
}
