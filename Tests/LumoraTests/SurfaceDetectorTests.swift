import XCTest
import CoreGraphics
import ImageIO
@testable import LumoraKit

final class SurfaceDetectorTests: XCTestCase {
    private let sampleDir = "Sources/Lumora/Resources/surface-detection"
    private let samples = ["sample", "sample1", "sample2", "sample3", "sample4"]

    private func load(_ name: String) -> CGImage? {
        let url = URL(fileURLWithPath: "\(sampleDir)/\(name).jpeg")
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    func testDetectsPlausibleSurfacesOnSamples() throws {
        var tested = 0
        let opts = SurfaceDetector.Options()
        for name in samples {
            guard let cg = load(name) else { continue }
            tested += 1
            let quads = SurfaceDetector.detect(in: cg, options: opts)
            XCTAssertLessThanOrEqual(quads.count, opts.ranker.maxResults, "\(name): too many")
            for q in quads {
                XCTAssertEqual(q.corners.count, 4, "\(name): quad must have 4 corners")
                XCTAssertGreaterThanOrEqual(q.areaFraction, opts.ranker.minAreaFraction - 1e-6, "\(name): under min area")
                for p in q.corners {
                    XCTAssertGreaterThanOrEqual(Double(p.x), -0.02); XCTAssertLessThanOrEqual(Double(p.x), 1.02)
                    XCTAssertGreaterThanOrEqual(Double(p.y), -0.02); XCTAssertLessThanOrEqual(Double(p.y), 1.02)
                }
            }
            dumpOverlay(cg, quads, name: name)
        }
        try XCTSkipIf(tested == 0, "sample images not found; skipped")
        XCTAssertGreaterThan(tested, 0)
    }

    // Writes an overlay PNG to the temp dir for manual inspection (never fails).
    private func dumpOverlay(_ cg: CGImage, _ quads: [DetectedQuad], name: String) {
        let W = min(cg.width, 1000), H = Int(Double(W) * Double(cg.height) / Double(cg.width))
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H)) // bottom-left origin
        let cols: [CGColor] = [.init(red: 1, green: 0.2, blue: 0.2, alpha: 1), .init(red: 0.2, green: 0.9, blue: 0.3, alpha: 1),
                               .init(red: 0.2, green: 0.5, blue: 1, alpha: 1), .init(red: 1, green: 0.6, blue: 0.1, alpha: 1),
                               .init(red: 0.7, green: 0.3, blue: 1, alpha: 1), .init(red: 0.1, green: 0.8, blue: 0.8, alpha: 1)]
        for (i, q) in quads.enumerated() {
            ctx.setStrokeColor(cols[i % cols.count]); ctx.setLineWidth(4)
            // corners are top-left normalized -> flip y for bottom-left CG context
            let pts = q.corners.map { CGPoint(x: Double($0.x) * Double(W), y: Double(H) - Double($0.y) * Double(H)) }
            ctx.beginPath(); ctx.move(to: pts[0]); for p in pts.dropFirst() { ctx.addLine(to: p) }; ctx.closePath(); ctx.strokePath()
        }
        guard let out = ctx.makeImage() else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("surfdet_\(name).png")
        guard let dst = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dst, out, nil); CGImageDestinationFinalize(dst)
        print("wrote \(url.path)")
    }
}
