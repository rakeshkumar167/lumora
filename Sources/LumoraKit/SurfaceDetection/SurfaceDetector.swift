import CoreGraphics
import Vision

/// Detects large flat quad surfaces in a room photo. AppKit-free.
///
/// Two passes feed one ranker:
///  - region growing with a gradient barrier -> planes (walls/floors)
///  - Vision rectangle detection -> objects (screens, doors, panels)
public enum SurfaceDetector {
    public struct Options {
        public var workingWidth: Int      // region-pass raster width
        public var maxVisionWidth: Int    // cap fed to Vision (speed)
        public var ranker: SurfaceRanker.Config
        public var gradientBarrier: Double // edge strength that blocks region growth
        /// Luminance distance to the region's running mean that still joins the
        /// region. Loose: one wall under a lighting gradient stays one region.
        public var lumTolerance: Double
        /// Chroma distance ((R-G, G-B) plane) to the region's running mean.
        /// Tight: differently painted surfaces of similar brightness stay apart.
        public var chromaTolerance: Double
        public var minFillRatio: Double        // reject loose quad fits
        public var minRectangularity: Double   // reject degenerate/triangular quads
        /// A quad claiming most of the photo needs stronger region evidence:
        /// backgrounds wrapping around foreground objects fit huge loose quads
        /// (their fill hovers ~0.6) while a real dominant wall fills its quad.
        public var largeQuadAreaFraction: Double
        public var largeQuadFillRatio: Double
        /// Gradient magnitude at which a quad-edge sample counts as lying on a
        /// real image edge (samples near the photo border always count).
        public var edgeSupportMinGrad: Double
        /// Minimum fraction of supported edge samples; hallucinated quads run
        /// across featureless areas and score low.
        public var minEdgeSupport: Double

        public init(workingWidth: Int = 380, maxVisionWidth: Int = 1400,
                    ranker: SurfaceRanker.Config = .init(), gradientBarrier: Double = 14,
                    lumTolerance: Double = 34, chromaTolerance: Double = 16,
                    minFillRatio: Double = 0.55, minRectangularity: Double = 0.58,
                    largeQuadAreaFraction: Double = 0.5, largeQuadFillRatio: Double = 0.72,
                    edgeSupportMinGrad: Double = 7, minEdgeSupport: Double = 0.55) {
            self.workingWidth = workingWidth
            self.maxVisionWidth = maxVisionWidth
            self.ranker = ranker
            self.gradientBarrier = gradientBarrier
            self.lumTolerance = lumTolerance
            self.chromaTolerance = chromaTolerance
            self.minFillRatio = minFillRatio
            self.minRectangularity = minRectangularity
            self.largeQuadAreaFraction = largeQuadAreaFraction
            self.largeQuadFillRatio = largeQuadFillRatio
            self.edgeSupportMinGrad = edgeSupportMinGrad
            self.minEdgeSupport = minEdgeSupport
        }
    }

    public static func detect(in image: CGImage, options: Options = .init()) -> [DetectedQuad] {
        let img = resized(image, maxDimension: options.maxVisionWidth)
        guard let seg = segment(img, options: options) else { return [] }
        var candidates = regionPlaneCandidates(seg, options: options)
        candidates += objectCandidates(img, minAreaFraction: options.ranker.minAreaFraction)
        // Surfaces must lie within the photo; the quad fit and Vision can both
        // place corners past the frame, so clamp and re-measure before ranking.
        candidates = candidates.map { q in
            var q = q
            q.corners = q.corners.map { CGPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }
            q.areaFraction = SurfaceGeometry.polygonArea(q.corners)
            return q
        }
        // A real surface's outline follows visible edges (or the photo frame);
        // quads that cut across featureless areas are junk fits.
        candidates = candidates.filter {
            edgeSupport($0.corners, seg: seg, minGrad: options.edgeSupportMinGrad) >= options.minEdgeSupport
        }
        return SurfaceRanker.filterMergeRank(candidates, config: options.ranker)
    }

    // MARK: - Region (plane) pass

    static func regionPlaneCandidates(_ seg: Segmentation, options: Options) -> [DetectedQuad] {
        let W = seg.width, H = seg.height
        var out: [DetectedQuad] = []
        let minPix = Double(W * H) * options.ranker.minAreaFraction
        var regionPts: [Int: [CGPoint]] = [:]
        for i in 0..<(W * H) where seg.labels[i] >= 0 {
            regionPts[seg.labels[i], default: []].append(CGPoint(x: i % W, y: i / W))
        }
        for (_, pts) in regionPts {
            let count = pts.count
            if Double(count) < minPix { continue }
            let quad = SurfaceGeometry.enclosingQuad(SurfaceGeometry.convexHull(pts))
            guard quad.count == 4 else { continue }
            let qa = SurfaceGeometry.polygonArea(quad)
            let requiredFill = qa >= Double(W * H) * options.largeQuadAreaFraction
                ? options.largeQuadFillRatio : options.minFillRatio
            guard qa > 0, Double(count) / qa >= requiredFill else { continue }
            // Reject degenerate/triangular fits: a real wall quad fills most of
            // its bounding box; a collapsed triangle fills roughly half.
            let bb = SurfaceGeometry.boundingBoxArea(quad)
            guard bb > 0, qa / bb >= options.minRectangularity else { continue }
            let ordered = SurfaceGeometry.orderedCorners(quad)
            let norm = ordered.map { CGPoint(x: Double($0.x) / Double(W), y: Double($0.y) / Double(H)) }
            out.append(DetectedQuad(corners: norm, areaFraction: qa / Double(W * H), source: .plane))
        }
        return out
    }

    struct Segmentation {
        var labels: [Int]       // -1 = barrier/unassigned, else region id
        var barrier: [Bool]     // gradient above the growth barrier
        var gradient: [Double]  // Sobel magnitude of the blurred raster
        var width: Int
        var height: Int
    }

    /// Region-grow the downscaled raster into segments. Shared by the plane
    /// pass and diagnostics.
    static func segment(_ image: CGImage, options: Options) -> Segmentation? {
        let W = options.workingWidth
        let H = max(1, Int(Double(W) * Double(image.height) / Double(image.width)))
        guard var px = pixelsTopLeft(image, width: W, height: H) else { return nil }
        boxBlur(&px, width: W, height: H)   // denoise before measuring gradients

        var lum = [Double](repeating: 0, count: W * H)
        for i in 0..<(W * H) {
            lum[i] = 0.299 * Double(px[i * 4]) + 0.587 * Double(px[i * 4 + 1]) + 0.114 * Double(px[i * 4 + 2])
        }
        var grad = [Double](repeating: 0, count: W * H)
        for y in 1..<(H - 1) {
            for x in 1..<(W - 1) {
                func L(_ xx: Int, _ yy: Int) -> Double { lum[yy * W + xx] }
                let gx = -L(x-1,y-1) - 2*L(x-1,y) - L(x-1,y+1) + L(x+1,y-1) + 2*L(x+1,y) + L(x+1,y+1)
                let gy = -L(x-1,y-1) - 2*L(x,y-1) - L(x+1,y-1) + L(x-1,y+1) + 2*L(x,y+1) + L(x+1,y+1)
                grad[y * W + x] = (gx * gx + gy * gy).squareRoot()
            }
        }

        var barrier = [Bool](repeating: false, count: W * H)
        for i in 0..<(W * H) where grad[i] > options.gradientBarrier { barrier[i] = true }

        var labels = [Int](repeating: -1, count: W * H)
        var visited = [Bool](repeating: false, count: W * H)
        var stack: [Int] = []
        var nextLabel = 0
        for start in 0..<(W * H) {
            if visited[start] { continue }
            if barrier[start] { visited[start] = true; continue }
            visited[start] = true
            let label = nextLabel; nextLabel += 1
            stack.removeAll(keepingCapacity: true); stack.append(start)
            var count = 0
            var sumR = 0.0, sumG = 0.0, sumB = 0.0
            while let cur = stack.popLast() {
                let cx = cur % W, cy = cur / W
                labels[cur] = label; count += 1
                sumR += Double(px[cur * 4]); sumG += Double(px[cur * 4 + 1]); sumB += Double(px[cur * 4 + 2])
                let inv = 1.0 / Double(count)
                let mR = sumR * inv, mG = sumG * inv, mB = sumB * inv
                let mLum = 0.299 * mR + 0.587 * mG + 0.114 * mB
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = cx + dx, ny = cy + dy
                    if nx < 0 || ny < 0 || nx >= W || ny >= H { continue }
                    let ni = ny * W + nx
                    if visited[ni] { continue }
                    if barrier[ni] { continue }
                    let r = Double(px[ni * 4]), g = Double(px[ni * 4 + 1]), b = Double(px[ni * 4 + 2])
                    if abs(lum[ni] - mLum) > options.lumTolerance { continue }
                    let dRG = (r - g) - (mR - mG), dGB = (g - b) - (mG - mB)
                    if (dRG * dRG + dGB * dGB).squareRoot() > options.chromaTolerance { continue }
                    visited[ni] = true; stack.append(ni)
                }
            }
        }
        return Segmentation(labels: labels, barrier: barrier, gradient: grad, width: W, height: H)
    }

    // MARK: - Object pass (Vision)

    static func objectCandidates(_ image: CGImage, minAreaFraction: Double) -> [DetectedQuad] {
        let req = VNDetectRectanglesRequest()
        req.minimumSize = 0.08   // windows/doors are narrow slices of a room photo
        req.minimumAspectRatio = 0.1
        req.maximumObservations = 30
        req.quadratureTolerance = 20  // lax enough for perspective, rejects skewed junk
        req.minimumConfidence = 0.45  // drop weak/garbage rectangles
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([req])
        let obs = req.results ?? []
        return obs.compactMap { o in
            // Vision: normalized, bottom-left origin -> top-left (y' = 1 - y).
            let raw = [o.topLeft, o.topRight, o.bottomRight, o.bottomLeft].map { CGPoint(x: $0.x, y: 1 - $0.y) }
            let ordered = SurfaceGeometry.orderedCorners(raw)
            let area = SurfaceGeometry.polygonArea(ordered)
            guard area >= minAreaFraction else { return nil }
            return DetectedQuad(corners: ordered, areaFraction: area, source: .object)
        }
    }

    // MARK: - Edge support

    /// Fraction of samples along the quad's edges that lie on a visible image
    /// edge (gradient >= minGrad within a small window) or at the photo border
    /// (a surface cut off by the frame has no gradient there).
    static func edgeSupport(_ corners: [CGPoint], seg: Segmentation, minGrad: Double) -> Double {
        let W = seg.width, H = seg.height
        var supported = 0, total = 0
        let steps = 24
        for i in 0..<corners.count {
            let a = corners[i], b = corners[(i + 1) % corners.count]
            for s in 0...steps {
                let t = Double(s) / Double(steps)
                let xi = Int((Double(a.x) + (Double(b.x) - Double(a.x)) * t) * Double(W - 1) + 0.5)
                let yi = Int((Double(a.y) + (Double(b.y) - Double(a.y)) * t) * Double(H - 1) + 0.5)
                total += 1
                if xi <= 2 || yi <= 2 || xi >= W - 3 || yi >= H - 3 { supported += 1; continue }
                var ok = false
                for dy in -2...2 where !ok {
                    for dx in -2...2 where seg.gradient[(yi + dy) * W + (xi + dx)] >= minGrad {
                        ok = true; break
                    }
                }
                if ok { supported += 1 }
            }
        }
        return total > 0 ? Double(supported) / Double(total) : 0
    }

    // MARK: - Raster helpers

    /// In-place 3x3 box blur on the RGB channels (separable, edge-clamped).
    private static func boxBlur(_ px: inout [UInt8], width W: Int, height H: Int) {
        var tmp = px
        for y in 0..<H {
            let row = y * W
            for x in 0..<W {
                let x0 = max(0, x - 1), x1 = min(W - 1, x + 1)
                for ch in 0..<3 {
                    let s = Int(px[(row + x0) * 4 + ch]) + Int(px[(row + x) * 4 + ch]) + Int(px[(row + x1) * 4 + ch])
                    tmp[(row + x) * 4 + ch] = UInt8(s / 3)
                }
            }
        }
        for y in 0..<H {
            let y0 = max(0, y - 1) * W, y1 = min(H - 1, y + 1) * W, yc = y * W
            for x in 0..<W {
                for ch in 0..<3 {
                    let s = Int(tmp[(y0 + x) * 4 + ch]) + Int(tmp[(yc + x) * 4 + ch]) + Int(tmp[(y1 + x) * 4 + ch])
                    px[(yc + x) * 4 + ch] = UInt8(s / 3)
                }
            }
        }
    }

    /// Rasterize into a top-left-origin RGBA8 buffer. CGBitmapContext memory
    /// already stores row 0 as the top scanline, so no flip is applied — an
    /// extra flip here would vertically mirror the raster.
    private static func pixelsTopLeft(_ image: CGImage, width w: Int, height h: Int) -> [UInt8]? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let p = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        return Array(UnsafeBufferPointer(start: p, count: w * h * 4))
    }

    private static func resized(_ image: CGImage, maxDimension: Int) -> CGImage {
        let m = max(image.width, image.height)
        if m <= maxDimension { return image }
        let scale = Double(maxDimension) / Double(m)
        let w = Int(Double(image.width) * scale), h = Int(Double(image.height) * scale)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }
}
