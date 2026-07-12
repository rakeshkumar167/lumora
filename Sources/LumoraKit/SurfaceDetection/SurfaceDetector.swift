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

        public init(workingWidth: Int = 380, maxVisionWidth: Int = 1400,
                    ranker: SurfaceRanker.Config = .init(), gradientBarrier: Double = 30,
                    lumTolerance: Double = 34, chromaTolerance: Double = 16,
                    minFillRatio: Double = 0.55, minRectangularity: Double = 0.58) {
            self.workingWidth = workingWidth
            self.maxVisionWidth = maxVisionWidth
            self.ranker = ranker
            self.gradientBarrier = gradientBarrier
            self.lumTolerance = lumTolerance
            self.chromaTolerance = chromaTolerance
            self.minFillRatio = minFillRatio
            self.minRectangularity = minRectangularity
        }
    }

    public static func detect(in image: CGImage, options: Options = .init()) -> [DetectedQuad] {
        let img = resized(image, maxDimension: options.maxVisionWidth)
        var candidates = regionPlaneCandidates(img, options: options)
        candidates += objectCandidates(img, minAreaFraction: options.ranker.minAreaFraction)
        // Surfaces must lie within the photo; the quad fit and Vision can both
        // place corners past the frame, so clamp and re-measure before ranking.
        candidates = candidates.map { q in
            var q = q
            q.corners = q.corners.map { CGPoint(x: min(max($0.x, 0), 1), y: min(max($0.y, 0), 1)) }
            q.areaFraction = SurfaceGeometry.polygonArea(q.corners)
            return q
        }
        return SurfaceRanker.filterMergeRank(candidates, config: options.ranker)
    }

    // MARK: - Region (plane) pass

    static func regionPlaneCandidates(_ image: CGImage, options: Options) -> [DetectedQuad] {
        let W = options.workingWidth
        let H = max(1, Int(Double(W) * Double(image.height) / Double(image.width)))
        guard var px = pixelsTopLeft(image, width: W, height: H) else { return [] }
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

        var visited = [Bool](repeating: false, count: W * H)
        var stack: [Int] = []
        var out: [DetectedQuad] = []
        let minPix = Double(W * H) * options.ranker.minAreaFraction
        for start in 0..<(W * H) {
            if visited[start] { continue }
            if grad[start] > options.gradientBarrier { visited[start] = true; continue } // edges never seed
            visited[start] = true
            stack.removeAll(keepingCapacity: true); stack.append(start)
            var pts: [CGPoint] = []
            var count = 0
            var sumR = 0.0, sumG = 0.0, sumB = 0.0
            while let cur = stack.popLast() {
                let cx = cur % W, cy = cur / W
                pts.append(CGPoint(x: cx, y: cy)); count += 1
                sumR += Double(px[cur * 4]); sumG += Double(px[cur * 4 + 1]); sumB += Double(px[cur * 4 + 2])
                let inv = 1.0 / Double(count)
                let mR = sumR * inv, mG = sumG * inv, mB = sumB * inv
                let mLum = 0.299 * mR + 0.587 * mG + 0.114 * mB
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = cx + dx, ny = cy + dy
                    if nx < 0 || ny < 0 || nx >= W || ny >= H { continue }
                    let ni = ny * W + nx
                    if visited[ni] { continue }
                    if grad[ni] > options.gradientBarrier { continue }     // barrier
                    let r = Double(px[ni * 4]), g = Double(px[ni * 4 + 1]), b = Double(px[ni * 4 + 2])
                    if abs(lum[ni] - mLum) > options.lumTolerance { continue }
                    let dRG = (r - g) - (mR - mG), dGB = (g - b) - (mG - mB)
                    if (dRG * dRG + dGB * dGB).squareRoot() > options.chromaTolerance { continue }
                    visited[ni] = true; stack.append(ni)
                }
            }
            if Double(count) < minPix { continue }
            let quad = SurfaceGeometry.enclosingQuad(SurfaceGeometry.convexHull(pts))
            guard quad.count == 4 else { continue }
            let qa = SurfaceGeometry.polygonArea(quad)
            guard qa > 0, Double(count) / qa >= options.minFillRatio else { continue }
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

    // MARK: - Object pass (Vision)

    static func objectCandidates(_ image: CGImage, minAreaFraction: Double) -> [DetectedQuad] {
        let req = VNDetectRectanglesRequest()
        req.minimumSize = 0.15
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
