import CoreGraphics
import Foundation

/// A ranked, normalized candidate surface. Coordinates are in [0,1]; `area` is
/// a fraction of the frame.
public struct DetectedSurface: Identifiable, Equatable {
    public var id: UUID
    public var polygon: [CGPoint]
    public var isQuad: Bool
    public var area: Double
    public var perimeter: Double
    public var aspectRatio: Double
    public var orientation: Double
    public var confidence: Double
    public var centroid: CGPoint
    public var boundingBox: CGRect
    public var averageColor: RGBAColor
    public var parentID: UUID?

    public init(id: UUID = UUID(), polygon: [CGPoint], isQuad: Bool, area: Double, perimeter: Double,
                aspectRatio: Double, orientation: Double, confidence: Double, centroid: CGPoint,
                boundingBox: CGRect, averageColor: RGBAColor, parentID: UUID? = nil) {
        self.id = id; self.polygon = polygon; self.isQuad = isQuad; self.area = area
        self.perimeter = perimeter; self.aspectRatio = aspectRatio; self.orientation = orientation
        self.confidence = confidence; self.centroid = centroid; self.boundingBox = boundingBox
        self.averageColor = averageColor; self.parentID = parentID
    }
}

/// Assemble validated region polygons into ranked, normalized DetectedSurfaces.
public enum SurfaceAssembler {
    public struct Config {
        public var maxResults: Int
        public var quadEpsilonFraction: Double // aggressive simplify epsilon = perimeter * this
        public init(maxResults: Int = 12, quadEpsilonFraction: Double = 0.03) {
            self.maxResults = maxResults; self.quadEpsilonFraction = quadEpsilonFraction
        }
    }

    public static func assemble(_ polygons: [[CGPoint]], rgb: RGBImage,
                                config: Config = .init()) -> [DetectedSurface] {
        if polygons.isEmpty { return [] }
        // 1. Merge over-segmented adjacent same-color pieces.
        let items = polygons.map { PolygonMerger.Item(polygon: $0, color: SurfaceAnalyzer.averageColor(of: $0, in: rgb)) }
        let merged = PolygonMerger.merge(items)

        let fw = rgb.width, fh = rgb.height
        let frameArea = Double(fw * fh)

        // 2. Build a surface per merged polygon.
        var surfaces: [DetectedSurface] = []
        for poly in merged where poly.count >= 3 {
            let props = SurfaceAnalyzer.properties(of: poly, in: rgb)
            // Quad approximation.
            let eps = max(1.0, props.perimeter * config.quadEpsilonFraction)
            let quad = PolygonApproximator.simplify(poly, epsilon: eps)
            let isQuad = quad.count == 4
            let usePoly = isQuad ? quad : poly
            let conf = ConfidenceScorer.score(usePoly, frameWidth: fw, frameHeight: fh)
            surfaces.append(DetectedSurface(
                polygon: normalize(usePoly, fw, fh),
                isQuad: isQuad,
                area: props.area / frameArea,
                perimeter: props.perimeter,
                aspectRatio: props.aspectRatio,
                orientation: props.orientation,
                confidence: conf,
                centroid: CGPoint(x: props.centroid.x / CGFloat(fw), y: props.centroid.y / CGFloat(fh)),
                boundingBox: CGRect(x: props.boundingBox.minX / CGFloat(fw), y: props.boundingBox.minY / CGFloat(fh),
                                    width: props.boundingBox.width / CGFloat(fw), height: props.boundingBox.height / CGFloat(fh)),
                averageColor: props.averageColor))
        }

        // 3. Sort largest-first, cap.
        surfaces.sort { $0.area > $1.area }
        if surfaces.count > config.maxResults { surfaces = Array(surfaces.prefix(config.maxResults)) }

        // 4. Rebuild nesting by containment (smallest enclosing surface).
        for i in surfaces.indices {
            let c = surfaces[i].centroid
            var bestArea = Double.greatestFiniteMagnitude
            var parent: UUID? = nil
            for j in surfaces.indices where j != i {
                if SurfaceAnalyzer.pointInPolygon(c, surfaces[j].polygon), surfaces[j].area < bestArea, surfaces[j].area > surfaces[i].area {
                    bestArea = surfaces[j].area; parent = surfaces[j].id
                }
            }
            surfaces[i].parentID = parent
        }
        return surfaces
    }

    static func normalize(_ poly: [CGPoint], _ w: Int, _ h: Int) -> [CGPoint] {
        poly.map { CGPoint(x: $0.x / CGFloat(w), y: $0.y / CGFloat(h)) }
    }
}
