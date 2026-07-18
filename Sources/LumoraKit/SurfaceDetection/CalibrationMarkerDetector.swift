import CoreGraphics
import Foundation

/// Locate the four projected magenta corner markers in an uploaded photo.
public enum CalibrationMarkerDetector {
    public struct Options {
        public var workingWidth: Int
        public var minLuma: Double
        public var minBlobAreaFraction: Double
        public init(workingWidth: Int = 900, minLuma: Double = 0.2, minBlobAreaFraction: Double = 0.0002) {
            self.workingWidth = workingWidth
            self.minLuma = minLuma
            self.minBlobAreaFraction = minBlobAreaFraction
        }
    }

    public static func detectCorners(in image: CGImage, options: Options = .init()) -> [CGPoint]? {
        let rgb = ImagePreprocessor.rgb(from: image, maxDimension: options.workingWidth)
        let w = rgb.width, h = rgb.height

        // Magenta mask: R and B high, clearly above G (rejects white/gray/green/red/blue).
        var mask = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let c = rgb.color(at: x, y)
                let luma = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
                if c.r > 0.4, c.b > 0.25, (c.r + c.b - 2 * c.g) > 0.3, luma > options.minLuma {
                    mask[y * w + x] = true
                }
            }
        }

        let field = ConnectedComponents.label(mask, width: w, height: h)
        if field.count < 4 { return nil }

        // Per-label centroid + area.
        var sx = [Double](repeating: 0, count: field.count + 1)
        var sy = [Double](repeating: 0, count: field.count + 1)
        var cnt = [Int](repeating: 0, count: field.count + 1)
        for y in 0..<h {
            for x in 0..<w {
                let l = field.labels[y * w + x]
                if l > 0 { sx[l] += Double(x); sy[l] += Double(y); cnt[l] += 1 }
            }
        }
        let minArea = Double(w * h) * options.minBlobAreaFraction
        var centers: [CGPoint] = []
        for l in 1...field.count where Double(cnt[l]) >= minArea {
            centers.append(CGPoint(x: sx[l] / Double(cnt[l]), y: sy[l] / Double(cnt[l])))
        }
        if centers.count < 4 { return nil }

        // Corner blobs by extremes (top-left origin).
        func pick(_ key: (CGPoint) -> Double, _ maximize: Bool) -> CGPoint {
            maximize ? centers.max { key($0) < key($1) }! : centers.min { key($0) < key($1) }!
        }
        let tl = pick({ Double($0.x + $0.y) }, false)
        let br = pick({ Double($0.x + $0.y) }, true)
        let tr = pick({ Double($0.x - $0.y) }, true)
        let bl = pick({ Double($0.x - $0.y) }, false)

        let ordered = [tl, tr, br, bl]
        // Require four distinct corner blobs.
        if Set(ordered.map { "\($0.x),\($0.y)" }).count < 4 { return nil }

        return ordered.map { CGPoint(x: $0.x / CGFloat(w), y: $0.y / CGFloat(h)) }
    }
}
