import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LumoraKit

final class CalibrationEndToEndTests: XCTestCase {
    func testCalibrationPipelineOnRealPhoto() throws {
        guard let path = ProcessInfo.processInfo.environment["CAL_IMAGE"],
              let dir = ProcessInfo.processInfo.environment["CAL_DIR"] else { throw XCTSkip("env") }
        let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
        let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)!

        // Simulate the photographed scene: paint magenta markers at an inset,
        // slightly trapezoidal quad (as a tilted photo would capture them).
        let W = min(cg.width, 1200), H = Int(Double(W) * Double(cg.height) / Double(cg.width))
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
        let m = CalibrationPattern.markerColor
        ctx.setFillColor(CGColor(red: m.r, green: m.g, blue: m.b, alpha: 1))
        let markers = [(0.12, 0.15), (0.88, 0.10), (0.92, 0.88), (0.08, 0.92)] // normalized top-left
        let r = Double(min(W, H)) * 0.03
        for (nx, ny) in markers {
            let cx = nx * Double(W), cy = (1 - ny) * Double(H) // to CG y-up
            ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        }
        let photo = ctx.makeImage()!

        let corners = CalibrationMarkerDetector.detectCorners(in: photo)
        XCTAssertNotNil(corners, "markers should be found")
        guard let corners, let rect = PerspectiveRectifier.rectify(photo, corners: corners) else { return }
        let surfaces = SurfaceDetector.detectSurfaces(in: rect)
        XCTAssertFalse(surfaces.isEmpty)

        // Write the rectified image with detected surfaces for eyeballing.
        let rw = rect.width, rh = rect.height, frh = CGFloat(rh)
        let out = CGContext(data: nil, width: rw, height: rh, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        out.draw(rect, in: CGRect(x: 0, y: 0, width: rw, height: rh))
        out.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)); out.fill(CGRect(x: 0, y: 0, width: rw, height: rh))
        let palette = [CGColor(red: 0.2, green: 1, blue: 0.5, alpha: 1), CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 1),
                       CGColor(red: 0.4, green: 0.6, blue: 1, alpha: 1), CGColor(red: 1, green: 0.4, blue: 0.8, alpha: 1)]
        for (i, s) in surfaces.enumerated() {
            let d = s.polygon.map { CGPoint(x: $0.x * CGFloat(rw), y: frh - $0.y * CGFloat(rh)) }
            guard let f = d.first else { continue }
            let c = palette[i % palette.count]
            out.setStrokeColor(c); out.setLineWidth(3); out.setFillColor(c.copy(alpha: 0.16)!)
            out.move(to: f); for p in d.dropFirst() { out.addLine(to: p) }; out.closePath(); out.drawPath(using: .fillStroke)
        }
        let img = out.makeImage()!
        let url = URL(fileURLWithPath: dir).appendingPathComponent("calibration_result.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil); _ = CGImageDestinationFinalize(dest)
        print("CALIBRATION rectified \(rw)x\(rh) surfaces=\(surfaces.count) -> \(url.path)")
    }
}
