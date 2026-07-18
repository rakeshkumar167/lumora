# Surface Detection — Stage 4: Region Segmentation + Validation (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn a Canny `EdgeMap` into candidate **region polygons** — segment the image into areas bounded by edges, trace them (with nesting) via the Stage 3 contour tracer, simplify, and validate away junk (too small/large/thin/irregular/self-intersecting).

**Architecture:** New `Morphology`, `RegionSegmenter`, `PolygonValidator` enums under `Sources/LumoraKit/SurfaceDetection/CV/`. `RegionSegmenter` seals edge gaps by dilation, inverts to a region mask, and reuses `ContourTracer` (Stage 3) + `PolygonApproximator`. Nesting comes for free from `ContourTracer`'s `parentIndex`. Pure Swift.

**Re-slice from the design doc (documented):** the design listed *adjacency merge* in this stage. Correct adjacency merge needs each region's **average color** (so a wall isn't fused into the floor), which is computed in Stage 5's properties step. Color-based adjacency merge therefore moves to **Stage 5**; Stage 4 is region segmentation + validation + nesting (nesting already delivered by `ContourTracer`). This is the showable-polygons milestone.

**Tech Stack:** Swift, XCTest, CoreGraphics (only the opt-in overlay). Target: `LumoraKit`; tests: `LumoraTests`.

## Global Constraints

- **Pure Swift only** — no OpenCV/Vision/ML. CoreGraphics only in the opt-in overlay.
- **Deterministic** — identical input yields identical output.
- Consumes Stage 1 `EdgeMap` and Stage 3 `ContourTracer`/`PolygonApproximator`/`Contour` unchanged.
- Coordinates are working-image **pixels**, top-left origin.
- All new types `public`; helpers may be `internal` for `@testable`.
- `swift test` stays green (currently 133 tests, 2 skipped) and grows.

---

## File Structure

- `Sources/LumoraKit/SurfaceDetection/CV/Morphology.swift` (create) — binary dilation.
- `Sources/LumoraKit/SurfaceDetection/CV/RegionSegmenter.swift` (create) — edges → region contours.
- `Sources/LumoraKit/SurfaceDetection/CV/PolygonValidator.swift` (create) — geometric validation.
- `Tests/LumoraTests/MorphologyTests.swift` (create)
- `Tests/LumoraTests/RegionSegmenterTests.swift` (create)
- `Tests/LumoraTests/PolygonValidatorTests.swift` (create)

---

### Task 1: `Morphology.dilate`

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/Morphology.swift`
- Test: `Tests/LumoraTests/MorphologyTests.swift`

**Interfaces:**
- Produces: `enum Morphology { static func dilate(_ binary: [Bool], width: Int, height: Int, radius: Int) -> [Bool] }` — square (Chebyshev) structuring element; every pixel within `radius` of a `true` input pixel becomes `true`.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/MorphologyTests.swift`:

```swift
import XCTest
@testable import LumoraKit

final class MorphologyTests: XCTestCase {
    func testDilateGrowsSinglePixelToBox() {
        var b = [Bool](repeating: false, count: 25) // 5x5
        b[2 * 5 + 2] = true
        let d = Morphology.dilate(b, width: 5, height: 5, radius: 1)
        // 3x3 box around (2,2) is now true.
        for y in 1...3 { for x in 1...3 { XCTAssertTrue(d[y * 5 + x]) } }
        XCTAssertFalse(d[0])            // corner untouched
        XCTAssertFalse(d[4 * 5 + 4])
    }

    func testDilateSealsAOnePixelGap() {
        // Two true pixels with a one-pixel gap → radius-1 dilation connects them.
        var b = [Bool](repeating: false, count: 15) // 5x3
        b[1 * 5 + 1] = true; b[1 * 5 + 3] = true
        let d = Morphology.dilate(b, width: 5, height: 3, radius: 1)
        XCTAssertTrue(d[1 * 5 + 2], "the gap pixel is filled")
    }

    func testDilateRadiusZeroIsIdentity() {
        var b = [Bool](repeating: false, count: 9)
        b[4] = true
        XCTAssertEqual(Morphology.dilate(b, width: 3, height: 3, radius: 0), b)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MorphologyTests`
Expected: FAIL — `Morphology` not found.

- [ ] **Step 3: Implement `Morphology`**

Create `Sources/LumoraKit/SurfaceDetection/CV/Morphology.swift`:

```swift
import Foundation

/// Binary morphology on row-major `[Bool]` images.
public enum Morphology {
    /// Dilate with a square (Chebyshev) structuring element of the given radius.
    public static func dilate(_ binary: [Bool], width w: Int, height h: Int, radius: Int) -> [Bool] {
        if radius <= 0 { return binary }
        var out = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w where binary[y * w + x] {
                let x0 = max(0, x - radius), x1 = min(w - 1, x + radius)
                let y0 = max(0, y - radius), y1 = min(h - 1, y + radius)
                for ny in y0...y1 { for nx in x0...x1 { out[ny * w + nx] = true } }
            }
        }
        return out
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MorphologyTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/Morphology.swift \
        Tests/LumoraTests/MorphologyTests.swift
git commit -m "feat(detect): binary dilation (Morphology)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `RegionSegmenter` — edges → region polygons

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/RegionSegmenter.swift`
- Test: `Tests/LumoraTests/RegionSegmenterTests.swift`

**Interfaces:**
- Consumes: `EdgeMap`, `Morphology.dilate`, `ContourTracer.traceContours`, `PolygonApproximator.simplify`, `Contour`.
- Produces: `enum RegionSegmenter { struct Config { var dilateRadius: Int; var simplifyEpsilon: Double }; static func regions(from edges: EdgeMap, config: Config = .init()) -> [Contour] }` — dilates edges into barriers, inverts to a region mask (non-barrier = region interior), traces region contours (with nesting), and simplifies each contour's points (preserving `parentIndex`).

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/RegionSegmenterTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class RegionSegmenterTests: XCTestCase {
    /// EdgeMap whose true pixels form a rectangle OUTLINE (its border only).
    private func rectangleOutline(w: Int, h: Int, x0: Int, y0: Int, x1: Int, y1: Int) -> EdgeMap {
        var e = [Bool](repeating: false, count: w * h)
        for x in x0...x1 { e[y0 * w + x] = true; e[y1 * w + x] = true }
        for y in y0...y1 { e[y * w + x0] = true; e[y * w + x1] = true }
        return EdgeMap(width: w, height: h, edges: e)
    }

    private func bbox(_ p: [CGPoint]) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var a = p[0], b = p[0]
        for q in p { a.x = min(a.x, q.x); a.y = min(a.y, q.y); b.x = max(b.x, q.x); b.y = max(b.y, q.y) }
        return (a.x, a.y, b.x, b.y)
    }

    func testInteriorRegionRecoveredFromRectangleOutline() {
        let edges = rectangleOutline(w: 60, h: 60, x0: 15, y0: 15, x1: 45, y1: 45)
        let regions = RegionSegmenter.regions(from: edges)
        // Expect at least the interior region and the exterior region.
        XCTAssertGreaterThanOrEqual(regions.count, 2)
        // One region's bbox should sit inside the outline (the interior).
        let interior = regions.first { r in
            let (minX, minY, maxX, maxY) = bbox(r.points)
            return minX >= 14 && minY >= 14 && maxX <= 46 && maxY <= 46
                && (maxX - minX) > 15 && (maxY - minY) > 15
        }
        XCTAssertNotNil(interior, "interior region should be recovered")
    }

    func testEmptyEdgesYieldOneRegion() {
        let edges = EdgeMap(width: 30, height: 30, edges: [Bool](repeating: false, count: 900))
        // No barriers → the whole frame is one region.
        XCTAssertEqual(RegionSegmenter.regions(from: edges).count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RegionSegmenterTests`
Expected: FAIL — `RegionSegmenter` not found.

- [ ] **Step 3: Implement `RegionSegmenter`**

Create `Sources/LumoraKit/SurfaceDetection/CV/RegionSegmenter.swift`:

```swift
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
        public init(dilateRadius: Int = 1, simplifyEpsilon: Double = 2.5) {
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RegionSegmenterTests`
Expected: PASS (2 tests). If `testInteriorRegionRecoveredFromRectangleOutline` fails because the interior was merged with the exterior, the outline had a gap the dilation didn't seal — raise `dilateRadius` in the test's config or verify the outline is closed.

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/RegionSegmenter.swift \
        Tests/LumoraTests/RegionSegmenterTests.swift
git commit -m "feat(detect): RegionSegmenter (edges -> region polygons)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `PolygonValidator`

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/PolygonValidator.swift`
- Test: `Tests/LumoraTests/PolygonValidatorTests.swift`

**Interfaces:**
- Produces:
  - `enum PolygonValidator { struct Config { var minAreaFraction, maxAreaFraction, minFillRatio, maxAspectRatio: Double; var minPoints: Int }; static func isValid(_ poly: [CGPoint], frameWidth: Int, frameHeight: Int, config: Config = .init()) -> Bool }`.
  - Rejects polygons that are: fewer than `minPoints`; area fraction outside `[minAreaFraction, maxAreaFraction]`; bbox fill ratio (`area / bboxArea`) below `minFillRatio` (thin/L-shaped); bbox aspect ratio above `maxAspectRatio` (slivers); or self-intersecting.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/PolygonValidatorTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class PolygonValidatorTests: XCTestCase {
    private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [CGPoint] {
        [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
    }

    func testAcceptsAReasonableRectangle() {
        let poly = rect(20, 20, 60, 55) // ~26% of a 100x100 frame, well-filled
        XCTAssertTrue(PolygonValidator.isValid(poly, frameWidth: 100, frameHeight: 100))
    }

    func testRejectsTinyPolygon() {
        let poly = rect(10, 10, 13, 13) // ~0.09% of frame
        XCTAssertFalse(PolygonValidator.isValid(poly, frameWidth: 100, frameHeight: 100))
    }

    func testRejectsFrameFillingPolygon() {
        let poly = rect(1, 1, 99, 99) // ~96% of frame
        XCTAssertFalse(PolygonValidator.isValid(poly, frameWidth: 100, frameHeight: 100))
    }

    func testRejectsThinSliver() {
        let poly = rect(5, 48, 95, 50) // 90x2, aspect 45
        XCTAssertFalse(PolygonValidator.isValid(poly, frameWidth: 100, frameHeight: 100))
    }

    func testRejectsSelfIntersectingBowtie() {
        // Bowtie: crossing edges.
        let poly = [CGPoint(x: 20, y: 20), CGPoint(x: 60, y: 55),
                    CGPoint(x: 60, y: 20), CGPoint(x: 20, y: 55)]
        XCTAssertFalse(PolygonValidator.isValid(poly, frameWidth: 100, frameHeight: 100))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PolygonValidatorTests`
Expected: FAIL — `PolygonValidator` not found.

- [ ] **Step 3: Implement `PolygonValidator`**

Create `Sources/LumoraKit/SurfaceDetection/CV/PolygonValidator.swift`:

```swift
import CoreGraphics
import Foundation

/// Geometric validity checks for candidate surface polygons.
public enum PolygonValidator {
    public struct Config {
        public var minAreaFraction: Double
        public var maxAreaFraction: Double
        public var minFillRatio: Double   // polygon area / bbox area
        public var maxAspectRatio: Double // longer bbox side / shorter
        public var minPoints: Int
        public init(minAreaFraction: Double = 0.008, maxAreaFraction: Double = 0.9,
                    minFillRatio: Double = 0.35, maxAspectRatio: Double = 12, minPoints: Int = 3) {
            self.minAreaFraction = minAreaFraction
            self.maxAreaFraction = maxAreaFraction
            self.minFillRatio = minFillRatio
            self.maxAspectRatio = maxAspectRatio
            self.minPoints = minPoints
        }
    }

    public static func isValid(_ poly: [CGPoint], frameWidth: Int, frameHeight: Int,
                               config: Config = .init()) -> Bool {
        if poly.count < config.minPoints { return false }
        let frameArea = Double(frameWidth * frameHeight)
        if frameArea <= 0 { return false }

        let area = polygonArea(poly)
        let frac = area / frameArea
        if frac < config.minAreaFraction || frac > config.maxAreaFraction { return false }

        let (minX, minY, maxX, maxY) = bounds(poly)
        let bw = Double(maxX - minX), bh = Double(maxY - minY)
        if bw <= 0 || bh <= 0 { return false }
        if area / (bw * bh) < config.minFillRatio { return false }
        if max(bw, bh) / min(bw, bh) > config.maxAspectRatio { return false }
        if isSelfIntersecting(poly) { return false }
        return true
    }

    static func polygonArea(_ poly: [CGPoint]) -> Double {
        if poly.count < 3 { return 0 }
        var s = 0.0, j = poly.count - 1
        for i in poly.indices {
            s += Double(poly[j].x + poly[i].x) * Double(poly[j].y - poly[i].y)
            j = i
        }
        return abs(s) / 2
    }

    static func bounds(_ poly: [CGPoint]) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var a = poly[0], b = poly[0]
        for p in poly { a.x = min(a.x, p.x); a.y = min(a.y, p.y); b.x = max(b.x, p.x); b.y = max(b.y, p.y) }
        return (a.x, a.y, b.x, b.y)
    }

    /// True if any pair of non-adjacent polygon edges properly intersects.
    static func isSelfIntersecting(_ poly: [CGPoint]) -> Bool {
        let n = poly.count
        if n < 4 { return false }
        for i in 0..<n {
            let a1 = poly[i], a2 = poly[(i + 1) % n]
            for j in (i + 1)..<n {
                // Skip adjacent edges (sharing a vertex).
                if j == i { continue }
                if (j + 1) % n == i || j == (i + 1) % n { continue }
                let b1 = poly[j], b2 = poly[(j + 1) % n]
                if segmentsProperlyIntersect(a1, a2, b1, b2) { return true }
            }
        }
        return false
    }

    private static func segmentsProperlyIntersect(_ p1: CGPoint, _ p2: CGPoint,
                                                  _ p3: CGPoint, _ p4: CGPoint) -> Bool {
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
            Double(a.x - o.x) * Double(b.y - o.y) - Double(a.y - o.y) * Double(b.x - o.x)
        }
        let d1 = cross(p3, p4, p1), d2 = cross(p3, p4, p2)
        let d3 = cross(p1, p2, p3), d4 = cross(p1, p2, p4)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0))
            && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PolygonValidatorTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS — ~143 tests (133 + 10 new), 0 failures (2 skipped).

- [ ] **Step 6: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/PolygonValidator.swift \
        Tests/LumoraTests/PolygonValidatorTests.swift
git commit -m "feat(detect): PolygonValidator (geometric validity)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Eyeball overlay — validated region polygons (synthetic + real)

**Files:**
- Test: `Tests/LumoraTests/RegionSegmenterTests.swift` (add one opt-in artifact test; add `import ImageIO`, `import UniformTypeIdentifiers`)

**Interfaces:**
- Consumes: `ImagePreprocessor.grayscale`, `CannyEdgeDetector.detect`, `RegionSegmenter.regions`, `PolygonValidator.isValid`.
- Produces: no library symbols — writes a PNG. Reads `REGION_IMAGE` (optional real photo path; falls back to a synthetic room) and `REGION_OVERLAY_DIR`.

- [ ] **Step 1: Add the artifact test**

Add imports to the top of `RegionSegmenterTests.swift`:

```swift
import ImageIO
import UniformTypeIdentifiers
```

Add to `RegionSegmenterTests`:

```swift
    func testWritesRegionOverlayArtifactWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["REGION_OVERLAY"] == "1" else {
            throw XCTSkip("set REGION_OVERLAY=1 to write the overlay artifact")
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let maxDim = Int(ProcessInfo.processInfo.environment["REGION_MAXDIM"] ?? "1000")!

        // Source: a real photo if REGION_IMAGE is set, else a synthetic room.
        let source: CGImage
        if let path = ProcessInfo.processInfo.environment["REGION_IMAGE"] {
            let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
            source = CGImageSourceCreateImageAtIndex(src, 0, nil)!
        } else {
            let w = 320, h = 240
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.setFillColor(CGColor(red: 0.82, green: 0.80, blue: 0.76, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setFillColor(CGColor(red: 0.55, green: 0.52, blue: 0.48, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h / 3))
            ctx.setFillColor(CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)); ctx.fill(CGRect(x: 110, y: 120, width: 110, height: 70))
            source = ctx.makeImage()!
        }

        let gray = ImagePreprocessor.grayscale(from: source, maxDimension: maxDim)
        let edges = CannyEdgeDetector.detect(gray)
        let regions = RegionSegmenter.regions(from: edges)
        let valid = regions.filter { PolygonValidator.isValid($0.points, frameWidth: gray.width, frameHeight: gray.height) }

        let W = gray.width, H = gray.height
        let out = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        out.draw(source, in: CGRect(x: 0, y: 0, width: W, height: H))
        out.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)); out.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let fH = CGFloat(H)
        let palette = [CGColor(red: 0.2, green: 1, blue: 0.5, alpha: 1), CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 1),
                       CGColor(red: 0.4, green: 0.6, blue: 1, alpha: 1), CGColor(red: 1, green: 0.4, blue: 0.8, alpha: 1),
                       CGColor(red: 1, green: 0.9, blue: 0.3, alpha: 1)]
        for (i, r) in valid.enumerated() {
            guard let first = r.points.first else { continue }
            let color = palette[i % palette.count]
            out.setStrokeColor(color); out.setLineWidth(2.5)
            out.setFillColor(color.copy(alpha: 0.18)!)
            out.move(to: CGPoint(x: first.x, y: fH - first.y))
            for p in r.points.dropFirst() { out.addLine(to: CGPoint(x: p.x, y: fH - p.y)) }
            out.closePath(); out.drawPath(using: .fillStroke)
        }
        let img = out.makeImage()!
        let dir = ProcessInfo.processInfo.environment["REGION_OVERLAY_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent("region_overlay.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        print("REGION_OVERLAY \(W)x\(H) regions:\(regions.count) valid:\(valid.count) -> \(url.path)")
    }
```

- [ ] **Step 2: Run on the synthetic room, then a real photo**

Synthetic: `REGION_OVERLAY=1 swift test --filter RegionSegmenterTests/testWritesRegionOverlayArtifactWhenRequested`
Real: `REGION_OVERLAY=1 REGION_IMAGE=/Users/zaks/Downloads/room-images/IMG_5533.jpeg swift test --filter RegionSegmenterTests/testWritesRegionOverlayArtifactWhenRequested`
Expected: PASS; prints region/valid counts and the PNG path.

- [ ] **Step 3: Eyeball + tune**

Open/Read `region_overlay.png`. Confirm the synthetic screen rectangle is captured as one filled polygon and the wall/floor bands as regions. On the real photo, confirm major flat surfaces (TV, marble wall, door, cabinet, floor) come out as sane polygons; expect some junk from cluttered areas — that is what Stage 5 ranking prunes. If regions over-fragment or leak, tune `RegionSegmenter.Config.dilateRadius` (raise to seal gaps) / `simplifyEpsilon` and `PolygonValidator.Config` thresholds. Record any default changes in a follow-up commit.

- [ ] **Step 4: Confirm default `swift test` skips it**

Run: `swift test --filter RegionSegmenterTests`
Expected: the artifact test reports **skipped**; the other tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/LumoraTests/RegionSegmenterTests.swift
git commit -m "test(detect): validated region-polygon overlay artifact (opt-in)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (Stage 4 slice of the design doc):**
- Region binary from edges → Tasks 1–2 (dilate → invert → trace). ✅
- Polygon approximation applied to region contours → Task 2 (`simplify`). ✅
- Polygon validation (too small/large/thin/irregular/self-intersecting/out-of-frame) → Task 3. ✅
- Nested regions kept separate → inherited from `ContourTracer.parentIndex` via `RegionSegmenter` (Task 2). ✅
- Adjacency merge → deliberately moved to Stage 5 (needs average color); documented at top. ✅
- Eyeball verification on real photos → Task 4. ✅

**Placeholder scan:** No TBD/TODO; every code step complete; notes are concrete tuning/import guidance. ✅

**Type consistency:** `Morphology.dilate([Bool],…) -> [Bool]` (Task 1) consumed by `RegionSegmenter` (Task 2). `RegionSegmenter.regions -> [Contour]` (Task 2) consumed by the overlay (Task 4) and validated per-polygon by `PolygonValidator.isValid([CGPoint],…) -> Bool` (Task 3). `Contour`/`EdgeMap`/`PolygonApproximator`/`ContourTracer` reused unchanged from earlier stages. ✅

**Scope check:** Region segmentation + validation + nesting only. Properties, confidence, color-based adjacency merge, `DetectedSurface`, ranking, and integration are Stages 5–6. ✅
```

