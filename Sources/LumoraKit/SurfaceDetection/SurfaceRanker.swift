import CoreGraphics

/// Filters, de-duplicates, and orders detected quads.
public enum SurfaceRanker {
    public struct Config {
        /// Minimum share of the image; the "skip small surfaces" knob.
        public var minAreaFraction: Double
        public var maxResults: Int
        /// Ranking multiplier applied to `.plane` candidates (planes first).
        public var planeBoost: Double

        public init(minAreaFraction: Double = 0.05, maxResults: Int = 8, planeBoost: Double = 1.35) {
            self.minAreaFraction = minAreaFraction
            self.maxResults = maxResults
            self.planeBoost = planeBoost
        }
    }

    public static func filterMergeRank(_ candidates: [DetectedQuad], config: Config = .init()) -> [DetectedQuad] {
        func score(_ q: DetectedQuad) -> Double { q.areaFraction * (q.source == .plane ? config.planeBoost : 1) }
        let ranked = candidates
            .filter { $0.areaFraction >= config.minAreaFraction }
            .sorted { score($0) > score($1) }
        var kept: [DetectedQuad] = []
        for q in ranked {
            let ctr = SurfaceGeometry.centroid(q.corners)
            // Suppress a candidate nested inside an already-kept (larger) quad.
            if kept.contains(where: { SurfaceGeometry.contains(ctr, in: $0.corners) }) { continue }
            kept.append(q)
            if kept.count >= config.maxResults { break }
        }
        return kept
    }
}
