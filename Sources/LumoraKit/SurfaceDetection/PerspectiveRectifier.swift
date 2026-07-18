import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Perspective-rectify a photo so four corner points map to a rectangle, via
/// CoreImage's CIPerspectiveCorrection. The output aspect is derived from the
/// corner quad (which is the projector rectangle as captured).
public enum PerspectiveRectifier {
    public static func rectify(_ image: CGImage, corners: [CGPoint]) -> CGImage? {
        guard corners.count == 4 else { return nil }
        let ci = CIImage(cgImage: image)
        let W = CGFloat(image.width), H = CGFloat(image.height)
        // Normalized top-left → CoreImage pixel coords (bottom-left origin: flip y).
        func p(_ c: CGPoint) -> CGPoint { CGPoint(x: c.x * W, y: (1 - c.y) * H) }

        let f = CIFilter.perspectiveCorrection()
        f.inputImage = ci
        f.topLeft = p(corners[0])
        f.topRight = p(corners[1])
        f.bottomRight = p(corners[2])
        f.bottomLeft = p(corners[3])
        f.crop = true
        guard let output = f.outputImage else { return nil }

        let ctx = CIContext(options: nil)
        return ctx.createCGImage(output, from: output.extent)
    }
}
