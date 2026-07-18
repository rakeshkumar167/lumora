import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
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

    func testWritesRankedSurfaceDemoWhenRequested() throws {
        guard let folder = ProcessInfo.processInfo.environment["SURFACE_DEMO_DIR"] else {
            throw XCTSkip("set SURFACE_DEMO_DIR")
        }
        let maxDim = Int(ProcessInfo.processInfo.environment["SURFACE_DEMO_MAXDIM"] ?? "1200")!
        let cs = CGColorSpaceCreateDeviceRGB()
        let fm = FileManager.default
        let jpegs = try fm.contentsOfDirectory(atPath: folder)
            .filter { $0.lowercased().hasSuffix(".jpeg") || $0.lowercased().hasSuffix(".jpg") }.sorted()

        for name in jpegs {
            let path = (folder as NSString).appendingPathComponent(name)
            guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            let gray = ImagePreprocessor.grayscale(from: cg, maxDimension: maxDim)
            let rgb = ImagePreprocessor.rgb(from: cg, maxDimension: maxDim)
            let edges = CannyEdgeDetector.detect(gray)
            let regions = RegionSegmenter.regions(from: edges)
            let valid = regions.filter { PolygonValidator.isValid($0.points, frameWidth: gray.width, frameHeight: gray.height) }
            let surfaces = SurfaceAssembler.assemble(valid.map { $0.points }, rgb: rgb)

            let W = gray.width, H = gray.height, fH = CGFloat(H)
            let out = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            out.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
            out.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.4)); out.fill(CGRect(x: 0, y: 0, width: W, height: H))
            let palette = [CGColor(red: 0.2, green: 1, blue: 0.5, alpha: 1), CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 1),
                           CGColor(red: 0.4, green: 0.6, blue: 1, alpha: 1), CGColor(red: 1, green: 0.4, blue: 0.8, alpha: 1),
                           CGColor(red: 1, green: 0.9, blue: 0.3, alpha: 1), CGColor(red: 0.5, green: 1, blue: 1, alpha: 1)]
            for (i, s) in surfaces.enumerated() {
                let denorm = s.polygon.map { CGPoint(x: $0.x * CGFloat(W), y: fH - $0.y * CGFloat(H)) }
                guard let first = denorm.first else { continue }
                let color = palette[i % palette.count]
                out.setStrokeColor(color); out.setLineWidth(max(2, CGFloat(W) / 380))
                out.setFillColor(color.copy(alpha: 0.16)!)
                out.move(to: first); for p in denorm.dropFirst() { out.addLine(to: p) }
                out.closePath(); out.drawPath(using: .fillStroke)
            }
            let img = out.makeImage()!
            let base = (name as NSString).deletingPathExtension
            let outURL = URL(fileURLWithPath: (folder as NSString).appendingPathComponent("\(base)_surfaces.png"))
            let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, img, nil)
            _ = CGImageDestinationFinalize(dest)
            print("SURFACES \(name) \(W)x\(H) count=\(surfaces.count) quads=\(surfaces.filter { $0.isQuad }.count) -> \(outURL.lastPathComponent)")
        }
    }
}
