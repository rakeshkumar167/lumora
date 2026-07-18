import CoreGraphics
import Foundation

/// Segment an edge map into candidate region polygons.
///
/// Edges are dilated into barriers; the non-barrier pixels form region
/// interiors; each region's boundary is traced (with nesting) and simplified.
public enum RegionSegmenter {
    public struct Config {
        public var dilateRadius: Int       // seal edge gaps
        public var simplifyEpsilon: Double // Douglas–Peucker tolerance (px)
        // dilateRadius 2 seals typical Canny edge gaps: at radius 1 a real
        // room's flat surfaces leak through 1px gaps into one giant blob.
        public init(dilateRadius: Int = 2, simplifyEpsilon: Double = 2.5) {
            self.dilateRadius = dilateRadius
            self.simplifyEpsilon = simplifyEpsilon
        }
    }

    public static func regions(from edges: EdgeMap, config: Config = .init()) -> [Contour] {
        let w = edges.width, h = edges.height
        let barrier = Morphology.dilate(edges.edges, width: w, height: h, radius: config.dilateRadius)
        var mask = [Bool](repeating: false, count: w * h)
        for i in mask.indices { mask[i] = !barrier[i] }
        let contours = ContourTracer.traceContours(binary: mask, width: w, height: h)
        return contours.map {
            Contour(points: PolygonApproximator.simplify($0.points, epsilon: config.simplifyEpsilon),
                    parentIndex: $0.parentIndex)
        }
    }
}
