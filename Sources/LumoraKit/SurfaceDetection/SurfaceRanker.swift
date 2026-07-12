import CoreGraphics

/// Filters, de-duplicates, and orders detected quads.
public enum SurfaceRanker {
    public struct Config {
        /// Minimum share of the image; the "skip small surfaces" knob.
        public var minAreaFraction: Double
        /// Maximum share of the image; quads near full-frame are the photo
        /// itself (uniform background), not a projection surface.
        public var maxAreaFraction: Double
        public var maxResults: Int
        /// Ranking multiplier applied to `.plane` candidates (planes first).
        public var planeBoost: Double
        /// Suppress a candidate whose overlap with an already-kept quad
        /// exceeds this fraction of the smaller quad's area. Catches the
        /// plane pass and the Vision pass proposing the same surface with
        /// slightly different corners.
        public var overlapThreshold: Double
        /// Overlapping quads only count as the *same* surface when their
        /// areas are also similar (smaller/larger above this). A screen
        /// nested inside a wall is two surfaces, not a duplicate.
        public var duplicateAreaRatio: Double

        public init(minAreaFraction: Double = 0.05, maxAreaFraction: Double = 0.93,
                    maxResults: Int = 8, planeBoost: Double = 1.35,
                    overlapThreshold: Double = 0.45, duplicateAreaRatio: Double = 0.5) {
            self.minAreaFraction = minAreaFraction
            self.maxAreaFraction = maxAreaFraction
            self.maxResults = maxResults
            self.planeBoost = planeBoost
            self.overlapThreshold = overlapThreshold
            self.duplicateAreaRatio = duplicateAreaRatio
        }
    }

    public static func filterMergeRank(_ candidates: [DetectedQuad], config: Config = .init()) -> [DetectedQuad] {
        func score(_ q: DetectedQuad) -> Double { q.areaFraction * (q.source == .plane ? config.planeBoost : 1) }
        let ranked = candidates
            .filter { $0.areaFraction >= config.minAreaFraction && $0.areaFraction <= config.maxAreaFraction }
            .sorted { score($0) > score($1) }
        var kept: [DetectedQuad] = []
        for q in ranked {
            if kept.contains(where: { k in
                let ratio = min(q.areaFraction, k.areaFraction) / max(q.areaFraction, k.areaFraction)
                return ratio >= config.duplicateAreaRatio &&
                    SurfaceGeometry.overlapOverSmaller(q.corners, k.corners) > config.overlapThreshold
            }) { continue }
            kept.append(q)
            if kept.count >= config.maxResults { break }
        }
        return kept
    }
}
