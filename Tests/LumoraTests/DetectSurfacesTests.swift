import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LumoraKit

final class DetectSurfacesTests: XCTestCase {
    /// A synthetic room: gradient wall, a floor band, and a dark rectangular screen.
    private func syntheticRoom(_ w: Int = 800, _ h: Int = 600) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.80, green: 0.78, blue: 0.74, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.55, green: 0.53, blue: 0.50, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h / 4)) // floor band
        ctx.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1))
        ctx.fill(CGRect(x: Double(w) * 0.35, y: Double(h) * 0.40, width: Double(w) * 0.35, height: Double(h) * 0.32)) // screen
        return ctx.makeImage()!
    }

    func testReturnsNormalizedSortedSurfaces() {
        let surfaces = SurfaceDetector.detectSurfaces(in: syntheticRoom())
        XCTAssertFalse(surfaces.isEmpty, "should detect at least one surface")
        // Largest first.
        for i in 1..<surfaces.count { XCTAssertGreaterThanOrEqual(surfaces[i - 1].area, surfaces[i].area) }
        // Normalized coordinates.
        for s in surfaces { for p in s.polygon {
            XCTAssertTrue((-0.01...1.01).contains(Double(p.x)))
            XCTAssertTrue((-0.01...1.01).contains(Double(p.y)))
        } }
    }

    func testRespectsMaxResults() {
        var opts = SurfaceDetector.Options()
        opts.ranker.maxResults = 3
        XCTAssertLessThanOrEqual(SurfaceDetector.detectSurfaces(in: syntheticRoom(), options: opts).count, 3)
    }

    func testWritesDetectSurfacesDemoWhenRequested() throws {
        guard let folder = ProcessInfo.processInfo.environment["DETECTSURF_DIR"] else {
            throw XCTSkip("set DETECTSURF_DIR")
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let fm = FileManager.default
        for name in try fm.contentsOfDirectory(atPath: folder).filter({ $0.lowercased().hasSuffix(".jpeg") }).sorted() {
            let path = (folder as NSString).appendingPathComponent(name)
            guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            let surfaces = SurfaceDetector.detectSurfaces(in: cg)
            let W = min(cg.width, 1200), H = Int(Double(W) * Double(cg.height) / Double(cg.width)), fH = CGFloat(H)
            let out = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            out.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
            out.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.4)); out.fill(CGRect(x: 0, y: 0, width: W, height: H))
            let palette = [CGColor(red: 0.2, green: 1, blue: 0.5, alpha: 1), CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 1),
                           CGColor(red: 0.4, green: 0.6, blue: 1, alpha: 1), CGColor(red: 1, green: 0.4, blue: 0.8, alpha: 1),
                           CGColor(red: 1, green: 0.9, blue: 0.3, alpha: 1), CGColor(red: 0.5, green: 1, blue: 1, alpha: 1)]
            for (i, s) in surfaces.enumerated() {
                let d = s.polygon.map { CGPoint(x: $0.x * CGFloat(W), y: fH - $0.y * CGFloat(H)) }
                guard let f = d.first else { continue }
                let c = palette[i % palette.count]
                out.setStrokeColor(c); out.setLineWidth(max(2, CGFloat(W) / 380)); out.setFillColor(c.copy(alpha: 0.16)!)
                out.move(to: f); for p in d.dropFirst() { out.addLine(to: p) }; out.closePath(); out.drawPath(using: .fillStroke)
            }
            let img = out.makeImage()!
            let outURL = URL(fileURLWithPath: (folder as NSString).appendingPathComponent("\((name as NSString).deletingPathExtension)_final.png"))
            let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, img, nil); _ = CGImageDestinationFinalize(dest)
            print("FINAL \(name) surfaces=\(surfaces.count) -> \(outURL.lastPathComponent)")
        }
    }
}
