# Auto Surface Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From an imported room photo, auto-detect the large flat quad surfaces (skipping small clutter), let the user keep/discard each in a review sheet, and drop the kept quads onto the canvas as editable surfaces.

**Architecture:** A hybrid, plane-first detector. Pure geometry + ranking live in `LumoraKit/SurfaceDetection/` (TDD-unit-tested). The image pipeline (`SurfaceDetector`) also lives in LumoraKit — it needs only CoreGraphics + Vision (no AppKit) — and is validated by a test that loads the five bundled sample photos and asserts invariants (+ dumps overlay PNGs for eyeball checks). The app target only loads the photo (`NSOpenPanel` → `CGImage`), runs the detector off-main, shows the review sheet, and commits kept quads via a new `ProjectStore` method.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit (app target only), CoreGraphics, Vision, ImageIO, XCTest.

## Global Constraints

- LumoraKit must stay **AppKit-free**. CoreGraphics, Vision, ImageIO are allowed (all headless on macOS). Only the `Lumora` app target may import AppKit/SwiftUI.
- All quad corners downstream use **normalized 0–1, top-left origin, ordered TL, TR, BR, BL** — matching `Surface.points`.
- Trust `swift build` / `swift test` over SourceKit's in-editor diagnostics (known to be stale in this repo).
- Keep the package compiling at every step. Commit per task.
- Co-author every commit: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

### Task 1: Pure geometry primitives

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/SurfaceGeometry.swift`
- Test: `Tests/LumoraTests/SurfaceGeometryTests.swift`

**Interfaces:**
- Produces: `enum SurfaceGeometry` with static funcs `polygonArea([CGPoint]) -> Double`, `centroid([CGPoint]) -> CGPoint`, `convexHull([CGPoint]) -> [CGPoint]`, `reduceToQuad([CGPoint]) -> [CGPoint]`, `orderedCorners([CGPoint]) -> [CGPoint]`, `contains(CGPoint, in: [CGPoint]) -> Bool`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/LumoraTests/SurfaceGeometryTests.swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class SurfaceGeometryTests: XCTestCase {
    func testPolygonAreaOfUnitSquare() {
        let sq = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        XCTAssertEqual(SurfaceGeometry.polygonArea(sq), 1.0, accuracy: 1e-9)
    }

    func testPolygonAreaIsOrderIndependent() {
        let tri = [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 0, y: 3)]
        XCTAssertEqual(SurfaceGeometry.polygonArea(tri), 6.0, accuracy: 1e-9)
    }

    func testCentroid() {
        let sq = [CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 0), CGPoint(x: 2, y: 2), CGPoint(x: 0, y: 2)]
        XCTAssertEqual(SurfaceGeometry.centroid(sq), CGPoint(x: 1, y: 1))
    }

    func testConvexHullDropsInteriorAndCollinearPoints() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 2, y: 0), CGPoint(x: 2, y: 2),
                   CGPoint(x: 0, y: 2), CGPoint(x: 1, y: 1) /*interior*/, CGPoint(x: 1, y: 0) /*collinear*/]
        let hull = SurfaceGeometry.convexHull(pts)
        XCTAssertEqual(hull.count, 4)
        XCTAssertEqual(SurfaceGeometry.polygonArea(hull), 4.0, accuracy: 1e-9)
    }

    func testReduceToQuadKeepsFourStrongestCorners() {
        // A square with two tiny bumps -> should reduce back to the square.
        let poly = [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 10, y: 0),
                    CGPoint(x: 10, y: 10), CGPoint(x: 5, y: 10.1), CGPoint(x: 0, y: 10)]
        let quad = SurfaceGeometry.reduceToQuad(poly)
        XCTAssertEqual(quad.count, 4)
        XCTAssertEqual(SurfaceGeometry.polygonArea(quad), 100.0, accuracy: 2.0)
    }

    func testReduceToQuadPassesThroughFourPoints() {
        let quad = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        XCTAssertEqual(SurfaceGeometry.reduceToQuad(quad).count, 4)
    }

    func testOrderedCornersTopLeftOrigin() {
        // scrambled; TL=(0,0) TR=(4,0) BR=(4,3) BL=(0,3)
        let scrambled = [CGPoint(x: 4, y: 3), CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 3), CGPoint(x: 4, y: 0)]
        let o = SurfaceGeometry.orderedCorners(scrambled)
        XCTAssertEqual(o, [CGPoint(x: 0, y: 0), CGPoint(x: 4, y: 0), CGPoint(x: 4, y: 3), CGPoint(x: 0, y: 3)])
    }

    func testContains() {
        let sq = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 0, y: 10)]
        XCTAssertTrue(SurfaceGeometry.contains(CGPoint(x: 5, y: 5), in: sq))
        XCTAssertFalse(SurfaceGeometry.contains(CGPoint(x: 15, y: 5), in: sq))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SurfaceGeometryTests`
Expected: FAIL to build ("Cannot find 'SurfaceGeometry' in scope").

- [ ] **Step 3: Write the implementation**

```swift
// Sources/LumoraKit/SurfaceDetection/SurfaceGeometry.swift
import CoreGraphics

/// Pure 2-D polygon helpers used by surface detection. No AppKit/Vision.
public enum SurfaceGeometry {
    /// Absolute polygon area via the shoelace formula (order-independent).
    public static func polygonArea(_ pts: [CGPoint]) -> Double {
        guard pts.count >= 3 else { return 0 }
        var a = 0.0
        for i in 0..<pts.count {
            let j = (i + 1) % pts.count
            a += Double(pts[i].x * pts[j].y - pts[j].x * pts[i].y)
        }
        return abs(a) / 2
    }

    public static func centroid(_ pts: [CGPoint]) -> CGPoint {
        guard !pts.isEmpty else { return .zero }
        var x = 0.0, y = 0.0
        for p in pts { x += Double(p.x); y += Double(p.y) }
        return CGPoint(x: x / Double(pts.count), y: y / Double(pts.count))
    }

    private static func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        Double((a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x))
    }

    /// Convex hull (Andrew's monotone chain). Collinear/interior points dropped.
    public static func convexHull(_ pts: [CGPoint]) -> [CGPoint] {
        let s = pts.sorted { $0.x < $1.x || ($0.x == $1.x && $0.y < $1.y) }
        guard s.count >= 3 else { return s }
        var lower: [CGPoint] = []
        for p in s {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        var upper: [CGPoint] = []
        for p in s.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        lower.removeLast(); upper.removeLast()
        return lower + upper
    }

    /// Reduce a polygon to 4 vertices by greedily removing the vertex whose
    /// removal loses the least triangle area (keeps the strongest corners).
    public static func reduceToQuad(_ poly: [CGPoint]) -> [CGPoint] {
        var v = poly
        while v.count > 4 {
            var worst = 0
            var worstLoss = Double.greatestFiniteMagnitude
            for i in 0..<v.count {
                let a = v[(i - 1 + v.count) % v.count]
                let c = v[(i + 1) % v.count]
                let loss = abs(cross(a, v[i], c)) / 2
                if loss < worstLoss { worstLoss = loss; worst = i }
            }
            v.remove(at: worst)
        }
        return v
    }

    /// Order four points as TL, TR, BR, BL in a top-left origin (y grows down).
    public static func orderedCorners(_ quad: [CGPoint]) -> [CGPoint] {
        guard quad.count == 4 else { return quad }
        let tl = quad.min { $0.x + $0.y < $1.x + $1.y }!
        let br = quad.max { $0.x + $0.y < $1.x + $1.y }!
        let tr = quad.max { $0.x - $0.y < $1.x - $1.y }!
        let bl = quad.min { $0.x - $0.y < $1.x - $1.y }!
        return [tl, tr, br, bl]
    }

    /// Ray-casting point-in-polygon test.
    public static func contains(_ pt: CGPoint, in poly: [CGPoint]) -> Bool {
        guard poly.count >= 3 else { return false }
        var c = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            if ((poly[i].y > pt.y) != (poly[j].y > pt.y)) &&
                (pt.x < (poly[j].x - poly[i].x) * (pt.y - poly[i].y) / (poly[j].y - poly[i].y) + poly[i].x) {
                c.toggle()
            }
            j = i
        }
        return c
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SurfaceGeometryTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/SurfaceGeometry.swift Tests/LumoraTests/SurfaceGeometryTests.swift
git commit -m "Add pure polygon geometry for surface detection

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: DetectedQuad model + ranker

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/DetectedQuad.swift`
- Create: `Sources/LumoraKit/SurfaceDetection/SurfaceRanker.swift`
- Test: `Tests/LumoraTests/SurfaceRankerTests.swift`

**Interfaces:**
- Consumes: `SurfaceGeometry.centroid`, `SurfaceGeometry.contains` (Task 1).
- Produces:
  - `enum QuadSource: String, Codable, Equatable { case plane, object }`
  - `struct DetectedQuad: Equatable { var corners: [CGPoint]; var areaFraction: Double; var source: QuadSource; init(corners:areaFraction:source:) }`
  - `enum SurfaceRanker { struct Config { var minAreaFraction: Double; var maxResults: Int; var planeBoost: Double; init(minAreaFraction: Double = 0.05, maxResults: Int = 8, planeBoost: Double = 1.35) }; static func filterMergeRank(_:config:) -> [DetectedQuad] }`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/LumoraTests/SurfaceRankerTests.swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class SurfaceRankerTests: XCTestCase {
    private func square(_ x: Double, _ y: Double, _ s: Double, area: Double, source: QuadSource) -> DetectedQuad {
        DetectedQuad(corners: [CGPoint(x: x, y: y), CGPoint(x: x + s, y: y),
                               CGPoint(x: x + s, y: y + s), CGPoint(x: x, y: y + s)],
                     areaFraction: area, source: source)
    }

    func testDropsBelowMinArea() {
        let small = square(0, 0, 0.1, area: 0.02, source: .plane)
        let out = SurfaceRanker.filterMergeRank([small], config: .init(minAreaFraction: 0.05))
        XCTAssertTrue(out.isEmpty)
    }

    func testSuppressesNestedQuad() {
        let big = square(0, 0, 0.8, area: 0.64, source: .plane)
        let inner = square(0.3, 0.3, 0.1, area: 0.06, source: .object) // centroid inside big
        let out = SurfaceRanker.filterMergeRank([big, inner])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.source, .plane)
    }

    func testPlaneOutranksSlightlyLargerObject() {
        // disjoint quads so neither is suppressed
        let object = square(0, 0, 0.3, area: 0.12, source: .object)
        let plane = square(0.6, 0.6, 0.3, area: 0.10, source: .plane)
        let out = SurfaceRanker.filterMergeRank([object, plane], config: .init(planeBoost: 1.35))
        XCTAssertEqual(out.first?.source, .plane) // 0.10*1.35 = 0.135 > 0.12
    }

    func testCapsAtMaxResults() {
        var quads: [DetectedQuad] = []
        for i in 0..<10 { quads.append(square(Double(i) * 1.5, 0, 0.5, area: 0.08 + Double(i) * 0.001, source: .plane)) }
        let out = SurfaceRanker.filterMergeRank(quads, config: .init(maxResults: 3))
        XCTAssertEqual(out.count, 3)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SurfaceRankerTests`
Expected: FAIL to build ("Cannot find 'DetectedQuad'/'SurfaceRanker' in scope").

- [ ] **Step 3: Write the implementation**

```swift
// Sources/LumoraKit/SurfaceDetection/DetectedQuad.swift
import CoreGraphics

/// Which detector proposed a quad.
public enum QuadSource: String, Codable, Equatable {
    case plane   // region segmentation (walls, floors)
    case object  // Vision rectangle (screens, doors, panels)
}

/// A candidate surface: a quad in normalized 0–1 top-left coordinates,
/// ordered TL, TR, BR, BL.
public struct DetectedQuad: Equatable {
    public var corners: [CGPoint]
    public var areaFraction: Double
    public var source: QuadSource

    public init(corners: [CGPoint], areaFraction: Double, source: QuadSource) {
        self.corners = corners
        self.areaFraction = areaFraction
        self.source = source
    }
}
```

```swift
// Sources/LumoraKit/SurfaceDetection/SurfaceRanker.swift
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SurfaceRankerTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/DetectedQuad.swift Sources/LumoraKit/SurfaceDetection/SurfaceRanker.swift Tests/LumoraTests/SurfaceRankerTests.swift
git commit -m "Add DetectedQuad model and plane-first ranker

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: The detector (region planes + Vision objects)

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/SurfaceDetector.swift`
- Test: `Tests/LumoraTests/SurfaceDetectorTests.swift`

**Interfaces:**
- Consumes: `SurfaceGeometry.*` (Task 1), `DetectedQuad`, `SurfaceRanker` (Task 2).
- Produces: `enum SurfaceDetector { struct Options { var workingWidth: Int = 380; var maxVisionWidth: Int = 1400; var ranker = SurfaceRanker.Config(); var gradientBarrier: Double = 42; var quantizeLevels: Int = 6; var minFillRatio: Double = 0.62 }; static func detect(in: CGImage, options: Options = .init()) -> [DetectedQuad] }`

**Note on validation:** image detection isn't exact, so this task's test asserts *invariants* on the five bundled samples (count in range, corners in [0,1], area ≥ threshold) and dumps overlay PNGs to `NSTemporaryDirectory()` for a human look. It skips gracefully if the sample files aren't present.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/LumoraTests/SurfaceDetectorTests.swift
import XCTest
import CoreGraphics
import ImageIO
@testable import LumoraKit

final class SurfaceDetectorTests: XCTestCase {
    private let sampleDir = "Sources/Lumora/Resources/surface-detection"
    private let samples = ["sample", "sample1", "sample2", "sample3", "sample4"]

    private func load(_ name: String) -> CGImage? {
        let url = URL(fileURLWithPath: "\(sampleDir)/\(name).jpeg")
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    func testDetectsPlausibleSurfacesOnSamples() throws {
        var tested = 0
        let opts = SurfaceDetector.Options()
        for name in samples {
            guard let cg = load(name) else { continue }
            tested += 1
            let quads = SurfaceDetector.detect(in: cg, options: opts)
            XCTAssertLessThanOrEqual(quads.count, opts.ranker.maxResults, "\(name): too many")
            for q in quads {
                XCTAssertEqual(q.corners.count, 4, "\(name): quad must have 4 corners")
                XCTAssertGreaterThanOrEqual(q.areaFraction, opts.ranker.minAreaFraction - 1e-6, "\(name): under min area")
                for p in q.corners {
                    XCTAssertGreaterThanOrEqual(Double(p.x), -0.02); XCTAssertLessThanOrEqual(Double(p.x), 1.02)
                    XCTAssertGreaterThanOrEqual(Double(p.y), -0.02); XCTAssertLessThanOrEqual(Double(p.y), 1.02)
                }
            }
            dumpOverlay(cg, quads, name: name)
        }
        try XCTSkipIf(tested == 0, "sample images not found; skipped")
        XCTAssertGreaterThan(tested, 0)
    }

    // Writes an overlay PNG to the temp dir for manual inspection (never fails).
    private func dumpOverlay(_ cg: CGImage, _ quads: [DetectedQuad], name: String) {
        let W = min(cg.width, 1000), H = Int(Double(W) * Double(cg.height) / Double(cg.width))
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H)) // bottom-left origin
        let cols: [CGColor] = [.init(red: 1, green: 0.2, blue: 0.2, alpha: 1), .init(red: 0.2, green: 0.9, blue: 0.3, alpha: 1),
                               .init(red: 0.2, green: 0.5, blue: 1, alpha: 1), .init(red: 1, green: 0.6, blue: 0.1, alpha: 1),
                               .init(red: 0.7, green: 0.3, blue: 1, alpha: 1), .init(red: 0.1, green: 0.8, blue: 0.8, alpha: 1)]
        for (i, q) in quads.enumerated() {
            ctx.setStrokeColor(cols[i % cols.count]); ctx.setLineWidth(4)
            // corners are top-left normalized -> flip y for bottom-left CG context
            let pts = q.corners.map { CGPoint(x: Double($0.x) * Double(W), y: Double(H) - Double($0.y) * Double(H)) }
            ctx.beginPath(); ctx.move(to: pts[0]); for p in pts.dropFirst() { ctx.addLine(to: p) }; ctx.closePath(); ctx.strokePath()
        }
        guard let out = ctx.makeImage() else { return }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("surfdet_\(name).png")
        guard let dst = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dst, out, nil); CGImageDestinationFinalize(dst)
        print("wrote \(url.path)")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SurfaceDetectorTests`
Expected: FAIL to build ("Cannot find 'SurfaceDetector' in scope").

- [ ] **Step 3: Write the implementation**

```swift
// Sources/LumoraKit/SurfaceDetection/SurfaceDetector.swift
import CoreGraphics
import Vision

/// Detects large flat quad surfaces in a room photo. AppKit-free.
///
/// Two passes feed one ranker:
///  - region segmentation with a gradient barrier -> planes (walls/floors)
///  - Vision rectangle detection -> objects (screens, doors, panels)
public enum SurfaceDetector {
    public struct Options {
        public var workingWidth: Int      // region-pass raster width
        public var maxVisionWidth: Int    // cap fed to Vision (speed)
        public var ranker: SurfaceRanker.Config
        public var gradientBarrier: Double // edge strength that blocks region growth
        public var quantizeLevels: Int
        public var minFillRatio: Double    // reject loose quad fits

        public init(workingWidth: Int = 380, maxVisionWidth: Int = 1400,
                    ranker: SurfaceRanker.Config = .init(), gradientBarrier: Double = 42,
                    quantizeLevels: Int = 6, minFillRatio: Double = 0.62) {
            self.workingWidth = workingWidth
            self.maxVisionWidth = maxVisionWidth
            self.ranker = ranker
            self.gradientBarrier = gradientBarrier
            self.quantizeLevels = quantizeLevels
            self.minFillRatio = minFillRatio
        }
    }

    public static func detect(in image: CGImage, options: Options = .init()) -> [DetectedQuad] {
        let img = resized(image, maxDimension: options.maxVisionWidth)
        var candidates = regionPlaneCandidates(img, options: options)
        candidates += objectCandidates(img, minAreaFraction: options.ranker.minAreaFraction)
        return SurfaceRanker.filterMergeRank(candidates, config: options.ranker)
    }

    // MARK: - Region (plane) pass

    static func regionPlaneCandidates(_ image: CGImage, options: Options) -> [DetectedQuad] {
        let W = options.workingWidth
        let H = max(1, Int(Double(W) * Double(image.height) / Double(image.width)))
        guard let px = pixelsTopLeft(image, width: W, height: H) else { return [] }

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
        let levels = options.quantizeLevels
        func bin(_ i: Int) -> Int {
            let r = Int(px[i * 4]) * (levels - 1) / 255
            let g = Int(px[i * 4 + 1]) * (levels - 1) / 255
            let b = Int(px[i * 4 + 2]) * (levels - 1) / 255
            return (r * levels + g) * levels + b
        }

        var label = [Int](repeating: -1, count: W * H)
        var stack: [Int] = []
        var id = 0
        var out: [DetectedQuad] = []
        let minPix = Double(W * H) * options.ranker.minAreaFraction
        for start in 0..<(W * H) {
            if label[start] != -1 { continue }
            let target = bin(start)
            stack.removeAll(keepingCapacity: true); stack.append(start); label[start] = id
            var pts: [CGPoint] = []
            var count = 0
            while let cur = stack.popLast() {
                let cx = cur % W, cy = cur / W
                pts.append(CGPoint(x: cx, y: cy)); count += 1
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                    let nx = cx + dx, ny = cy + dy
                    if nx < 0 || ny < 0 || nx >= W || ny >= H { continue }
                    let ni = ny * W + nx
                    if grad[ni] > options.gradientBarrier { continue }     // barrier
                    if label[ni] == -1 && bin(ni) == target { label[ni] = id; stack.append(ni) }
                }
            }
            id += 1
            if Double(count) < minPix { continue }
            let quad = SurfaceGeometry.reduceToQuad(SurfaceGeometry.convexHull(pts))
            guard quad.count == 4 else { continue }
            let qa = SurfaceGeometry.polygonArea(quad)
            guard qa > 0, Double(count) / qa >= options.minFillRatio else { continue }
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
        req.quadratureTolerance = 35
        req.minimumConfidence = 0.0
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

    /// Rasterize into a top-left-origin RGBA8 buffer (flips the default
    /// bottom-left CG context so row 0 is the top of the image).
    private static func pixelsTopLeft(_ image: CGImage, width w: Int, height h: Int) -> [UInt8]? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SurfaceDetectorTests`
Expected: PASS (invariants hold; console prints `wrote …/surfdet_*.png`).

- [ ] **Step 5: Eyeball the overlays**

Read the dumped PNGs (path printed in the test output, under the temp dir — e.g. `surfdet_sample.png`, `surfdet_sample4.png`). Confirm big walls/objects are captured and no single quad swallows the whole frame. If a threshold needs a nudge (`gradientBarrier`, `minFillRatio`, `minAreaFraction`), adjust `Options` defaults and re-run Step 4. This is a judgment check, not an assertion.

- [ ] **Step 6: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/SurfaceDetector.swift Tests/LumoraTests/SurfaceDetectorTests.swift
git commit -m "Add hybrid surface detector (region planes + Vision objects)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: App integration — commit, review sheet, toolbar button

**Files:**
- Modify: `Sources/Lumora/ProjectStore.swift` (add `addDetectedSurfaces`)
- Create: `Sources/Lumora/Views/SurfaceDetectionReviewView.swift`
- Modify: `Sources/Lumora/Views/WorkspaceView.swift` (toolbar button, open panel, sheet)
- Test: `Tests/LumoraTests/AddDetectedSurfacesTests.swift`

**Interfaces:**
- Consumes: `DetectedQuad`, `SurfaceDetector.detect` (Task 3); `Surface`, `MediaAssignment`, `RGBAColor` (existing).
- Produces: `ProjectStore.addDetectedSurfaces(_ quads: [[CGPoint]])`; `SurfaceDetectionReviewView(image:quads:onAdd:onCancel:)`.

- [ ] **Step 1: Write the failing test** (for the pure store logic)

```swift
// Tests/LumoraTests/AddDetectedSurfacesTests.swift
import XCTest
import CoreGraphics
@testable import Lumora
import LumoraKit

@MainActor
final class AddDetectedSurfacesTests: XCTestCase {
    func testAppendsOneSurfacePerQuadAndSelectsFirst() {
        let store = ProjectStore()
        let before = store.surfaces.count
        let q1 = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.4, y: 0.1), CGPoint(x: 0.4, y: 0.5), CGPoint(x: 0.1, y: 0.5)]
        let q2 = [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.9, y: 0.5), CGPoint(x: 0.9, y: 0.9), CGPoint(x: 0.5, y: 0.9)]
        store.addDetectedSurfaces([q1, q2])
        XCTAssertEqual(store.surfaces.count, before + 2)
        XCTAssertEqual(store.surfaces[store.surfaces.count - 2].points, q1)
        XCTAssertEqual(store.selectedID, store.surfaces[store.surfaces.count - 2].id)
        XCTAssertEqual(store.surfaces.last?.shape, .quad)
    }

    func testIgnoresEmptyInput() {
        let store = ProjectStore()
        let before = store.surfaces.count
        store.addDetectedSurfaces([])
        XCTAssertEqual(store.surfaces.count, before)
    }
}
```

> If `ProjectStore()` needs arguments, mirror the initializer used in existing tests (check `Tests/LumoraTests/ProjectCodableTests.swift`). Adjust the test's construction to match; the assertions stay the same.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AddDetectedSurfacesTests`
Expected: FAIL to build ("value of type 'ProjectStore' has no member 'addDetectedSurfaces'").

- [ ] **Step 3: Add the store method**

In `Sources/Lumora/ProjectStore.swift`, after `addSurface()`:

```swift
    /// Append one editable quad surface per detected corner set (normalized,
    /// TL,TR,BR,BL) and select the first one added.
    func addDetectedSurfaces(_ quads: [[CGPoint]]) {
        guard !quads.isEmpty else { return }
        var firstID: Surface.ID?
        for pts in quads {
            var s = Surface(name: "Surface \(surfaces.count + 1)", points: pts, shape: .quad)
            s.media = .effect(.grid, .cyan, RGBAColor(r: 0.05, g: 0.06, b: 0.09))
            surfaces.append(s)
            if firstID == nil { firstID = s.id }
        }
        if let firstID { selectSurface(firstID) }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AddDetectedSurfacesTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Create the review sheet**

```swift
// Sources/Lumora/Views/SurfaceDetectionReviewView.swift
import AppKit
import LumoraKit
import SwiftUI

/// Sheet that previews auto-detected surfaces on the room photo and lets the
/// user keep/discard each before adding them to the canvas.
struct SurfaceDetectionReviewView: View {
    let image: NSImage
    let quads: [DetectedQuad]
    let onAdd: ([[CGPoint]]) -> Void
    let onCancel: () -> Void

    @State private var keep: [Bool]

    init(image: NSImage, quads: [DetectedQuad],
         onAdd: @escaping ([[CGPoint]]) -> Void, onCancel: @escaping () -> Void) {
        self.image = image
        self.quads = quads
        self.onAdd = onAdd
        self.onCancel = onCancel
        _keep = State(initialValue: Array(repeating: true, count: quads.count))
    }

    private let palette: [Color] = [.red, .green, .blue, .orange, .purple, .teal, .yellow, .pink]
    private var keptCount: Int { keep.filter { $0 }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(quads.isEmpty ? "No surfaces detected"
                     : "Detected \(quads.count) surface\(quads.count == 1 ? "" : "s")")
                    .font(.headline)
                Spacer()
            }
            .padding()

            GeometryReader { geo in
                let fit = aspectFit(imageSize: image.size, in: geo.size)
                ZStack {
                    Image(nsImage: image).resizable().scaledToFit()
                    Canvas { ctx, _ in
                        for (i, q) in quads.enumerated() where i < keep.count && keep[i] {
                            let col = palette[i % palette.count]
                            let pts = q.corners.map {
                                CGPoint(x: fit.minX + Double($0.x) * fit.width,
                                        y: fit.minY + Double($0.y) * fit.height)
                            }
                            var path = Path()
                            path.move(to: pts[0]); for p in pts.dropFirst() { path.addLine(to: p) }; path.closeSubpath()
                            ctx.fill(path, with: .color(col.opacity(0.16)))
                            ctx.stroke(path, with: .color(col), lineWidth: 3)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(minHeight: 340)
            .background(Color.black.opacity(0.06))

            if !quads.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quads.indices, id: \.self) { i in
                            Toggle(isOn: binding(i)) {
                                Label("\(i + 1) · \(Int(quads[i].areaFraction * 100))%",
                                      systemImage: quads[i].source == .plane ? "rectangle.dashed" : "tv")
                            }
                            .toggleStyle(.button)
                            .tint(palette[i % palette.count])
                        }
                    }
                    .padding()
                }
            }

            Divider()
            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                Spacer()
                Button("Add \(keptCount) Surface\(keptCount == 1 ? "" : "s")") {
                    let selected = quads.enumerated()
                        .filter { $0.offset < keep.count && keep[$0.offset] }
                        .map { $0.element.corners }
                    onAdd(selected)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(keptCount == 0)
            }
            .padding()
        }
        .frame(width: 760, height: 660)
    }

    private func binding(_ i: Int) -> Binding<Bool> {
        Binding(get: { keep[i] }, set: { keep[i] = $0 })
    }

    private func aspectFit(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }
}
```

- [ ] **Step 6: Wire the toolbar button + open panel + sheet in `WorkspaceView.swift`**

Add state near the top of `WorkspaceView`:

```swift
    @State private var reviewImage: NSImage?
    @State private var reviewQuads: [DetectedQuad] = []
    @State private var showReview = false
    @State private var detecting = false
```

Add a button in `toolbar` next to **Add Line** (inside the same `HStack`, after the Add Line button):

```swift
            Button {
                detectSurfaces()
            } label: {
                Label("Detect Surfaces", systemImage: "viewfinder.rectangular")
            }
            .disabled(detecting)
```

Attach the sheet to the root `HSplitView` (add `.sheet` after the closing of the split view's content, before the final `}` of `body`):

```swift
        .sheet(isPresented: $showReview) {
            if let img = reviewImage {
                SurfaceDetectionReviewView(
                    image: img,
                    quads: reviewQuads,
                    onAdd: { corners in
                        store.addDetectedSurfaces(corners)
                        showReview = false
                    },
                    onCancel: { showReview = false }
                )
            }
        }
```

Add the detection method inside `WorkspaceView` (near `openProject()`):

```swift
    /// Pick a room photo, run detection off the main thread, then present the
    /// keep/discard review sheet.
    private func detectSurfaces() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let nsImage = NSImage(contentsOf: url),
              let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        detecting = true
        Task {
            let quads = SurfaceDetector.detect(in: cg)
            await MainActor.run {
                reviewImage = nsImage
                reviewQuads = quads
                detecting = false
                showReview = true
            }
        }
    }
```

Add `import UniformTypeIdentifiers` if not already present (it is — used for `.lumora`). `.heic`/`.jpeg`/`.png`/`.image` are `UTType` members.

- [ ] **Step 7: Build and smoke-test**

Run: `swift build`
Expected: builds clean. (Ignore any SourceKit "cannot find in scope" noise.)

Launch the app, click **Detect Surfaces**, pick `Sources/Lumora/Resources/surface-detection/sample.jpeg`, confirm the review sheet shows overlaid quads, toggle a couple off, click **Add** — the kept quads appear as selectable/warp-editable surfaces on the canvas.

- [ ] **Step 8: Commit**

```bash
git add Sources/Lumora/ProjectStore.swift Sources/Lumora/Views/SurfaceDetectionReviewView.swift Sources/Lumora/Views/WorkspaceView.swift Tests/LumoraTests/AddDetectedSurfacesTests.swift
git commit -m "Wire auto surface detection into the workspace (button, review sheet, commit)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Docs — mark old approach superseded, note what shipped

**Files:**
- Modify: `docs/BACKLOG.md`

- [ ] **Step 1: Update the backlog**

In `docs/BACKLOG.md`, under "Paused — ready to build on request", replace the "Marker calibration & auto-surface detection" bullet's opening with a note that it is **superseded** by the shipped hybrid detector (design: `docs/superpowers/specs/2026-07-12-auto-surface-detection-design.md`), and add a short "Done recently" entry describing the shipped feature: hybrid plane-first detector (region segmentation + Vision), size filter, plane-first ranking, keep/discard review sheet, quads committed as editable surfaces; `SurfaceDetection/` in LumoraKit is unit-tested, the detector validated against the five bundled samples.

- [ ] **Step 2: Run the full test suite**

Run: `swift test`
Expected: all tests pass.

- [ ] **Step 3: Commit**

```bash
git add docs/BACKLOG.md
git commit -m "Docs: mark fiducial calibration superseded; note shipped surface detection

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

- **Spec coverage:** hybrid plane-first detector (Task 3) ✓; region + gradient barrier + 4-corner fit ✓; Vision objects ✓; min-area filter + nested suppression + plane-first ranking (Task 2) ✓; pure geometry unit-tested (Task 1) ✓; file-picker import + keep/discard review + commit to blank canvas (Task 4) ✓; no backdrop / no fiducials ✓; docs (Task 5) ✓.
- **Coordinate consistency:** region raster is flipped to top-left origin (`pixelsTopLeft`), Vision converted `1 - y`, both ordered by `orderedCorners`, matching `Surface.points`. ✓
- **Type consistency:** `DetectedQuad`, `QuadSource`, `SurfaceRanker.Config`, `SurfaceDetector.Options`, and `addDetectedSurfaces([[CGPoint]])` are named identically across tasks. ✓
- **Placeholders:** none — every code step is complete. The one conditional note (ProjectStore initializer in the test) points to a concrete file to mirror.
