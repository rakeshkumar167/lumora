# Surface Detection — Stage 5: Properties + Merge + Confidence + DetectedSurface (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn validated region polygons into ranked `DetectedSurface`s: compute per-surface properties (incl. average color), merge over-segmented adjacent same-color pieces, score confidence, normalize to `[0,1]`, mark quads, rebuild nesting, and sort largest-first.

**Architecture:** New `RGBImage` + color extraction, `SurfaceAnalyzer` (properties), `PolygonMerger` (color+adjacency), `ConfidenceScorer`, `DetectedSurface` model, and `SurfaceAssembler` (the Stage-5 pipeline) under `Sources/LumoraKit/SurfaceDetection/CV/`. Pure Swift.

**Tech Stack:** Swift, XCTest, CoreGraphics (RGB raster + opt-in overlay). Target: `LumoraKit`; tests: `LumoraTests`.

## Global Constraints

- **Pure Swift only** — no OpenCV/Vision/ML. CoreGraphics for RGB rasterization + the opt-in overlay.
- **Deterministic.**
- `DetectedSurface` coordinates are **normalized `[0,1]`** (map to any display), unlike the pixel-space intermediate stages.
- Reuses `Contour`, `PolygonApproximator`, `PolygonValidator`, `RGBAColor`.
- Top-left origin, no vertical flip (see prior stages).
- All new types `public`; helpers may be `internal` for `@testable`.
- `swift test` stays green (currently 145 tests, 4 skipped) and grows.

---

## File Structure

- `Sources/LumoraKit/SurfaceDetection/CV/RGBImage.swift` (create) — RGB buffer + `ImagePreprocessor.rgb`.
- `Sources/LumoraKit/SurfaceDetection/CV/SurfaceAnalyzer.swift` (create) — `SurfaceProperties` + compute.
- `Sources/LumoraKit/SurfaceDetection/CV/PolygonMerger.swift` (create) — color+adjacency merge.
- `Sources/LumoraKit/SurfaceDetection/CV/ConfidenceScorer.swift` (create) — 0…1 score.
- `Sources/LumoraKit/SurfaceDetection/CV/DetectedSurface.swift` (create) — model + `SurfaceAssembler`.
- Tests: `RGBImageTests`, `SurfaceAnalyzerTests`, `PolygonMergerTests`, `ConfidenceScorerTests`, `SurfaceAssemblerTests`.

---

### Task 1: `RGBImage` + RGB extraction

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/RGBImage.swift`
- Test: `Tests/LumoraTests/RGBImageTests.swift`

**Interfaces:**
- Produces:
  - `struct RGBImage { let width, height: Int; var pixels: [UInt8] /* RGBA row-major */; func color(at x: Int, _ y: Int) -> RGBAColor }`.
  - `extension ImagePreprocessor { static func rgb(from image: CGImage, maxDimension: Int) -> RGBImage }` — downscaled (never up), top-left origin, RGBA8.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/RGBImageTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class RGBImageTests: XCTestCase {
    private func rgbCGImage(_ w: Int, _ h: Int, _ fill: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let (r, g, b) = fill(x, y); let i = (y * w + x) * 4
            bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b; bytes[i + 3] = 255
        } }
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    func testExtractsColorsWithCorrectOrientation() {
        // Top-left red, else blue: catches H and V flips.
        let img = rgbCGImage(4, 4) { x, y in (x < 2 && y < 2) ? (255, 0, 0) : (0, 0, 255) }
        let rgb = ImagePreprocessor.rgb(from: img, maxDimension: 4)
        XCTAssertEqual(rgb.width, 4); XCTAssertEqual(rgb.height, 4)
        let tl = rgb.color(at: 0, 0), br = rgb.color(at: 3, 3)
        XCTAssertGreaterThan(tl.r, 0.8); XCTAssertLessThan(tl.b, 0.2)
        XCTAssertGreaterThan(br.b, 0.8); XCTAssertLessThan(br.r, 0.2)
    }

    func testDownscales() {
        let img = rgbCGImage(8, 4) { _, _ in (128, 128, 128) }
        let rgb = ImagePreprocessor.rgb(from: img, maxDimension: 4)
        XCTAssertEqual(rgb.width, 4); XCTAssertEqual(rgb.height, 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RGBImageTests`
Expected: FAIL — `RGBImage` / `ImagePreprocessor.rgb` not found.

- [ ] **Step 3: Implement**

Create `Sources/LumoraKit/SurfaceDetection/CV/RGBImage.swift`:

```swift
import CoreGraphics
import Foundation

/// An RGBA8 image buffer, row-major, top-left origin.
public struct RGBImage {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8] // RGBA, length width*height*4

    public init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width; self.height = height; self.pixels = pixels
    }

    public func color(at x: Int, _ y: Int) -> RGBAColor {
        let i = (y * width + x) * 4
        return RGBAColor(r: Double(pixels[i]) / 255, g: Double(pixels[i + 1]) / 255,
                         b: Double(pixels[i + 2]) / 255, a: Double(pixels[i + 3]) / 255)
    }
}

extension ImagePreprocessor {
    /// Downscale (never up) so the longer side ≤ `maxDimension`; rasterize into
    /// a top-left-origin RGBA8 buffer.
    public static func rgb(from image: CGImage, maxDimension: Int) -> RGBImage {
        let longSide = max(image.width, image.height)
        let scale = longSide > maxDimension ? Double(maxDimension) / Double(longSide) : 1.0
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        let cs = CGColorSpaceCreateDeviceRGB()
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return RGBImage(width: w, height: h, pixels: bytes)
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return RGBImage(width: w, height: h, pixels: bytes)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter RGBImageTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/RGBImage.swift Tests/LumoraTests/RGBImageTests.swift
git commit -m "feat(detect): RGBImage + RGB extraction

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `SurfaceAnalyzer` — polygon properties + average color

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/SurfaceAnalyzer.swift`
- Test: `Tests/LumoraTests/SurfaceAnalyzerTests.swift`

**Interfaces:**
- Consumes: `RGBImage`, `RGBAColor`.
- Produces:
  - `struct SurfaceProperties: Equatable { var area, perimeter, aspectRatio, orientation: Double; var centroid: CGPoint; var boundingBox: CGRect; var averageColor: RGBAColor }` (pixel units).
  - `enum SurfaceAnalyzer { static func properties(of polygon: [CGPoint], in rgb: RGBImage) -> SurfaceProperties; static func averageColor(of polygon: [CGPoint], in rgb: RGBImage) -> RGBAColor; static func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool }`.
  - `averageColor` samples image pixels inside the polygon's bbox (stride-limited so large polygons stay fast), averaging those passing point-in-polygon.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/SurfaceAnalyzerTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class SurfaceAnalyzerTests: XCTestCase {
    private func solidRGB(_ w: Int, _ h: Int, _ c: (UInt8, UInt8, UInt8)) -> RGBImage {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) { px[i * 4] = c.0; px[i * 4 + 1] = c.1; px[i * 4 + 2] = c.2; px[i * 4 + 3] = 255 }
        return RGBImage(width: w, height: h, pixels: px)
    }

    private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [CGPoint] {
        [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
    }

    func testRectangleGeometry() {
        let img = solidRGB(100, 100, (10, 20, 30))
        let p = SurfaceAnalyzer.properties(of: rect(10, 20, 50, 60), in: img)
        XCTAssertEqual(p.area, 40 * 40, accuracy: 1)
        XCTAssertEqual(p.perimeter, 2 * (40 + 40), accuracy: 1)
        XCTAssertEqual(Double(p.centroid.x), 30, accuracy: 1)
        XCTAssertEqual(Double(p.centroid.y), 40, accuracy: 1)
        XCTAssertEqual(p.aspectRatio, 1, accuracy: 0.01)
    }

    func testAverageColorOfRegion() {
        let img = solidRGB(50, 50, (200, 100, 50))
        let c = SurfaceAnalyzer.averageColor(of: rect(5, 5, 45, 45), in: img)
        XCTAssertEqual(c.r, 200.0 / 255, accuracy: 0.02)
        XCTAssertEqual(c.g, 100.0 / 255, accuracy: 0.02)
        XCTAssertEqual(c.b, 50.0 / 255, accuracy: 0.02)
    }

    func testOrientationOfWideRectangleIsHorizontal() {
        let img = solidRGB(100, 100, (0, 0, 0))
        let p = SurfaceAnalyzer.properties(of: rect(10, 40, 90, 55), in: img)
        // Longest edge is horizontal → orientation ≈ 0.
        XCTAssertEqual(min(p.orientation, .pi - p.orientation), 0, accuracy: 0.05)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SurfaceAnalyzerTests`
Expected: FAIL — `SurfaceAnalyzer` not found.

- [ ] **Step 3: Implement**

Create `Sources/LumoraKit/SurfaceDetection/CV/SurfaceAnalyzer.swift`:

```swift
import CoreGraphics
import Foundation

public struct SurfaceProperties: Equatable {
    public var area: Double
    public var perimeter: Double
    public var aspectRatio: Double
    public var orientation: Double  // longest-edge orientation in [0, π)
    public var centroid: CGPoint
    public var boundingBox: CGRect
    public var averageColor: RGBAColor
}

public enum SurfaceAnalyzer {
    public static func properties(of polygon: [CGPoint], in rgb: RGBImage) -> SurfaceProperties {
        let area = polygonArea(polygon)
        let perim = perimeter(polygon)
        let bb = bounds(polygon)
        let bw = Double(bb.width), bh = Double(bb.height)
        let aspect = (bw > 0 && bh > 0) ? max(bw, bh) / min(bw, bh) : 1
        return SurfaceProperties(area: area, perimeter: perim, aspectRatio: aspect,
                                 orientation: longestEdgeOrientation(polygon),
                                 centroid: centroid(polygon), boundingBox: bb,
                                 averageColor: averageColor(of: polygon, in: rgb))
    }

    public static func averageColor(of polygon: [CGPoint], in rgb: RGBImage) -> RGBAColor {
        let bb = bounds(polygon)
        let x0 = max(0, Int(bb.minX)), x1 = min(rgb.width - 1, Int(bb.maxX))
        let y0 = max(0, Int(bb.minY)), y1 = min(rgb.height - 1, Int(bb.maxY))
        if x1 < x0 || y1 < y0 { return .white }
        // Cap sampling to ~4000 points for speed on large surfaces.
        let stride = max(1, Int((Double((x1 - x0 + 1) * (y1 - y0 + 1)) / 4000).squareRoot()))
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        var y = y0
        while y <= y1 {
            var x = x0
            while x <= x1 {
                if pointInPolygon(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5), polygon) {
                    let c = rgb.color(at: x, y); r += c.r; g += c.g; b += c.b; n += 1
                }
                x += stride
            }
            y += stride
        }
        if n == 0 { return .white }
        return RGBAColor(r: r / n, g: g / n, b: b / n)
    }

    static func polygonArea(_ poly: [CGPoint]) -> Double {
        if poly.count < 3 { return 0 }
        var s = 0.0, j = poly.count - 1
        for i in poly.indices { s += Double(poly[j].x + poly[i].x) * Double(poly[j].y - poly[i].y); j = i }
        return abs(s) / 2
    }

    static func perimeter(_ poly: [CGPoint]) -> Double {
        if poly.count < 2 { return 0 }
        var p = 0.0, j = poly.count - 1
        for i in poly.indices {
            let dx = Double(poly[i].x - poly[j].x), dy = Double(poly[i].y - poly[j].y)
            p += (dx * dx + dy * dy).squareRoot(); j = i
        }
        return p
    }

    static func centroid(_ poly: [CGPoint]) -> CGPoint {
        if poly.count < 3 { // degenerate → average of points
            var sx = 0.0, sy = 0.0
            for p in poly { sx += Double(p.x); sy += Double(p.y) }
            let n = Double(max(poly.count, 1))
            return CGPoint(x: sx / n, y: sy / n)
        }
        var a = 0.0, cx = 0.0, cy = 0.0, j = poly.count - 1
        for i in poly.indices {
            let cross = Double(poly[j].x) * Double(poly[i].y) - Double(poly[i].x) * Double(poly[j].y)
            a += cross
            cx += (Double(poly[j].x) + Double(poly[i].x)) * cross
            cy += (Double(poly[j].y) + Double(poly[i].y)) * cross
            j = i
        }
        if abs(a) < 1e-9 { return bounds(poly).center }
        a *= 0.5
        return CGPoint(x: cx / (6 * a), y: cy / (6 * a))
    }

    static func longestEdgeOrientation(_ poly: [CGPoint]) -> Double {
        var best = -1.0, angle = 0.0, j = poly.count - 1
        for i in poly.indices {
            let dx = Double(poly[i].x - poly[j].x), dy = Double(poly[i].y - poly[j].y)
            let len = dx * dx + dy * dy
            if len > best { best = len; angle = atan2(dy, dx) }
            j = i
        }
        var a = angle.truncatingRemainder(dividingBy: .pi)
        if a < 0 { a += .pi }
        return a
    }

    static func bounds(_ poly: [CGPoint]) -> CGRect {
        var a = poly[0], b = poly[0]
        for p in poly { a.x = min(a.x, p.x); a.y = min(a.y, p.y); b.x = max(b.x, p.x); b.y = max(b.y, p.y) }
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    public static func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        if poly.count < 3 { return false }
        var inside = false, j = poly.count - 1
        for i in poly.indices {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) {
                let t = (p.y - a.y) / (b.y - a.y)
                if p.x < a.x + t * (b.x - a.x) { inside.toggle() }
            }
            j = i
        }
        return inside
    }
}

extension CGRect { var center: CGPoint { CGPoint(x: midX, y: midY) } }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SurfaceAnalyzerTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/SurfaceAnalyzer.swift Tests/LumoraTests/SurfaceAnalyzerTests.swift
git commit -m "feat(detect): SurfaceAnalyzer (properties + average color)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `PolygonMerger` — color + adjacency merge

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/PolygonMerger.swift`
- Test: `Tests/LumoraTests/PolygonMergerTests.swift`

**Interfaces:**
- Produces:
  - `enum PolygonMerger { struct Item { var polygon: [CGPoint]; var color: RGBAColor }; struct Config { var colorTolerance: Double; var adjacencyDistance: Double }; static func merge(_ items: [Item], config: Config = .init()) -> [[CGPoint]] }`.
  - Union-find groups items that are **adjacent** (min boundary-point distance ≤ `adjacencyDistance`) **and** color-similar (Euclidean RGB distance ≤ `colorTolerance`); each group is replaced by the **convex hull** of its combined points. Non-merged items pass through unchanged.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/PolygonMergerTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class PolygonMergerTests: XCTestCase {
    private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [CGPoint] {
        [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
    }

    func testMergesAdjacentSameColorRectangles() {
        let a = PolygonMerger.Item(polygon: rect(0, 0, 20, 40), color: RGBAColor(r: 0.5, g: 0.5, b: 0.5))
        let b = PolygonMerger.Item(polygon: rect(21, 0, 40, 40), color: RGBAColor(r: 0.52, g: 0.5, b: 0.49))
        let merged = PolygonMerger.merge([a, b])
        XCTAssertEqual(merged.count, 1)
        // Hull spans both.
        let xs = merged[0].map { $0.x }
        XCTAssertEqual(xs.min()!, 0, accuracy: 1); XCTAssertEqual(xs.max()!, 40, accuracy: 1)
    }

    func testKeepsAdjacentDifferentColorRectanglesSeparate() {
        let a = PolygonMerger.Item(polygon: rect(0, 0, 20, 40), color: RGBAColor(r: 0.1, g: 0.1, b: 0.1))
        let b = PolygonMerger.Item(polygon: rect(21, 0, 40, 40), color: RGBAColor(r: 0.9, g: 0.9, b: 0.9))
        XCTAssertEqual(PolygonMerger.merge([a, b]).count, 2)
    }

    func testKeepsFarApartSameColorSeparate() {
        let a = PolygonMerger.Item(polygon: rect(0, 0, 20, 20), color: RGBAColor(r: 0.5, g: 0.5, b: 0.5))
        let b = PolygonMerger.Item(polygon: rect(60, 60, 80, 80), color: RGBAColor(r: 0.5, g: 0.5, b: 0.5))
        XCTAssertEqual(PolygonMerger.merge([a, b]).count, 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PolygonMergerTests`
Expected: FAIL — `PolygonMerger` not found.

- [ ] **Step 3: Implement**

Create `Sources/LumoraKit/SurfaceDetection/CV/PolygonMerger.swift`:

```swift
import CoreGraphics
import Foundation

/// Merge over-segmented adjacent same-color polygons (e.g. wall panels split by
/// interior seams) via convex hull of each merged group.
public enum PolygonMerger {
    public struct Item {
        public var polygon: [CGPoint]
        public var color: RGBAColor
        public init(polygon: [CGPoint], color: RGBAColor) { self.polygon = polygon; self.color = color }
    }
    public struct Config {
        public var colorTolerance: Double   // Euclidean RGB distance
        public var adjacencyDistance: Double // px between nearest boundary points
        public init(colorTolerance: Double = 0.14, adjacencyDistance: Double = 6) {
            self.colorTolerance = colorTolerance; self.adjacencyDistance = adjacencyDistance
        }
    }

    public static func merge(_ items: [Item], config: Config = .init()) -> [[CGPoint]] {
        let n = items.count
        if n <= 1 { return items.map { $0.polygon } }
        var parent = Array(0..<n)
        func find(_ i: Int) -> Int { var r = i; while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }; return r }
        func union(_ i: Int, _ j: Int) { parent[find(i)] = find(j) }

        for i in 0..<n {
            for j in (i + 1)..<n where colorClose(items[i].color, items[j].color, config.colorTolerance)
                && adjacent(items[i].polygon, items[j].polygon, config.adjacencyDistance) {
                union(i, j)
            }
        }
        var groups: [Int: [CGPoint]] = [:]
        for i in 0..<n { groups[find(i), default: []].append(contentsOf: items[i].polygon) }
        return groups.values.map { convexHull($0) }
    }

    static func colorClose(_ a: RGBAColor, _ b: RGBAColor, _ tol: Double) -> Bool {
        let dr = a.r - b.r, dg = a.g - b.g, db = a.b - b.b
        return (dr * dr + dg * dg + db * db).squareRoot() <= tol
    }

    static func adjacent(_ a: [CGPoint], _ b: [CGPoint], _ maxDist: Double) -> Bool {
        let d2 = maxDist * maxDist
        for p in a { for q in b {
            let dx = Double(p.x - q.x), dy = Double(p.y - q.y)
            if dx * dx + dy * dy <= d2 { return true }
        } }
        return false
    }

    /// Andrew's monotone chain convex hull.
    static func convexHull(_ pts: [CGPoint]) -> [CGPoint] {
        let p = Array(Set(pts.map { HPoint($0) })).map { $0.cg }.sorted {
            $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y
        }
        if p.count < 3 { return p }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
            Double(a.x - o.x) * Double(b.y - o.y) - Double(a.y - o.y) * Double(b.x - o.x)
        }
        var lower: [CGPoint] = []
        for pt in p { while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], pt) <= 0 { lower.removeLast() }; lower.append(pt) }
        var upper: [CGPoint] = []
        for pt in p.reversed() { while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], pt) <= 0 { upper.removeLast() }; upper.append(pt) }
        lower.removeLast(); upper.removeLast()
        return lower + upper
    }

    // Hashable wrapper so we can dedup CGPoints before hulling.
    private struct HPoint: Hashable {
        let x: CGFloat, y: CGFloat
        init(_ p: CGPoint) { x = p.x; y = p.y }
        var cg: CGPoint { CGPoint(x: x, y: y) }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PolygonMergerTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/PolygonMerger.swift Tests/LumoraTests/PolygonMergerTests.swift
git commit -m "feat(detect): PolygonMerger (color+adjacency, convex-hull union)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `ConfidenceScorer`

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/ConfidenceScorer.swift`
- Test: `Tests/LumoraTests/ConfidenceScorerTests.swift`

**Interfaces:**
- Produces: `enum ConfidenceScorer { static func score(_ polygon: [CGPoint], frameWidth: Int, frameHeight: Int) -> Double }` — 0…1 from bbox fill ratio (rectangularity), a moderate-size preference, and an aspect penalty for slivers.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/ConfidenceScorerTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class ConfidenceScorerTests: XCTestCase {
    private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [CGPoint] {
        [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
    }

    func testCleanRectangleScoresHigh() {
        let s = ConfidenceScorer.score(rect(20, 20, 70, 65), frameWidth: 100, frameHeight: 100)
        XCTAssertGreaterThan(s, 0.6)
    }

    func testThinSliverScoresLowerThanRectangle() {
        let sliver = ConfidenceScorer.score(rect(5, 49, 95, 51), frameWidth: 100, frameHeight: 100)
        let clean = ConfidenceScorer.score(rect(20, 20, 70, 65), frameWidth: 100, frameHeight: 100)
        XCTAssertLessThan(sliver, clean)
    }

    func testScoreInUnitRange() {
        let s = ConfidenceScorer.score(rect(0, 0, 100, 100), frameWidth: 100, frameHeight: 100)
        XCTAssertGreaterThanOrEqual(s, 0); XCTAssertLessThanOrEqual(s, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConfidenceScorerTests`
Expected: FAIL — `ConfidenceScorer` not found.

- [ ] **Step 3: Implement**

Create `Sources/LumoraKit/SurfaceDetection/CV/ConfidenceScorer.swift`:

```swift
import CoreGraphics
import Foundation

/// A 0…1 confidence that a polygon is a clean planar surface.
public enum ConfidenceScorer {
    public static func score(_ polygon: [CGPoint], frameWidth: Int, frameHeight: Int) -> Double {
        if polygon.count < 3 { return 0 }
        let area = polygonArea(polygon)
        let bb = bounds(polygon)
        let bw = Double(bb.width), bh = Double(bb.height)
        if bw <= 0 || bh <= 0 { return 0 }

        // Rectangularity: how fully the polygon fills its bounding box.
        let fill = min(1, area / (bw * bh))
        // Aspect: penalize slivers (aspect 1 → 1.0, aspect ≥ 8 → ~0).
        let aspect = max(bw, bh) / min(bw, bh)
        let aspectScore = max(0, 1 - (aspect - 1) / 7)
        // Size: prefer a meaningful chunk of the frame, saturating.
        let frac = area / Double(frameWidth * frameHeight)
        let sizeScore = min(1, frac / 0.05)

        let s = 0.5 * fill + 0.3 * aspectScore + 0.2 * sizeScore
        return max(0, min(1, s))
    }

    static func polygonArea(_ poly: [CGPoint]) -> Double {
        var s = 0.0, j = poly.count - 1
        for i in poly.indices { s += Double(poly[j].x + poly[i].x) * Double(poly[j].y - poly[i].y); j = i }
        return abs(s) / 2
    }
    static func bounds(_ poly: [CGPoint]) -> CGRect {
        var a = poly[0], b = poly[0]
        for p in poly { a.x = min(a.x, p.x); a.y = min(a.y, p.y); b.x = max(b.x, p.x); b.y = max(b.y, p.y) }
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ConfidenceScorerTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/ConfidenceScorer.swift Tests/LumoraTests/ConfidenceScorerTests.swift
git commit -m "feat(detect): ConfidenceScorer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: `DetectedSurface` + `SurfaceAssembler`

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/DetectedSurface.swift`
- Test: `Tests/LumoraTests/SurfaceAssemblerTests.swift`

**Interfaces:**
- Consumes: everything above + `PolygonApproximator`, `PolygonValidator`.
- Produces:
  - `struct DetectedSurface: Identifiable, Equatable { var id: UUID; var polygon: [CGPoint]; var isQuad: Bool; var area, perimeter, aspectRatio, orientation, confidence: Double; var centroid: CGPoint; var boundingBox: CGRect; var averageColor: RGBAColor; var parentID: UUID? }` — polygon/centroid/boundingBox normalized `[0,1]`; `area` a frame fraction.
  - `enum SurfaceAssembler { struct Config { var maxResults: Int; var quadEpsilonFraction: Double }; static func assemble(_ polygons: [[CGPoint]], rgb: RGBImage, config: Config = .init()) -> [DetectedSurface] }` — computes each polygon's avg color, merges (via `PolygonMerger`), then for each merged polygon computes properties + confidence, marks quad (aggressive Douglas–Peucker → exactly 4 pts), normalizes coordinates, rebuilds nesting by containment, sorts by area desc, and caps to `maxResults`.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/SurfaceAssemblerTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class SurfaceAssemblerTests: XCTestCase {
    private func solid(_ w: Int, _ h: Int) -> RGBImage {
        RGBImage(width: w, height: h, pixels: [UInt8](repeating: 128, count: w * h * 4))
    }
    private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [CGPoint] {
        [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
    }

    func testNormalizesAndSortsBySize() {
        let img = solid(100, 100)
        let small = rect(70, 70, 90, 90)
        let big = rect(5, 5, 60, 60)
        let out = SurfaceAssembler.assemble([small, big], rgb: img)
        XCTAssertEqual(out.count, 2)
        XCTAssertGreaterThan(out[0].area, out[1].area, "largest first")
        for s in out {
            for p in s.polygon {
                XCTAssertTrue((0.0...1.0).contains(Double(p.x)))
                XCTAssertTrue((0.0...1.0).contains(Double(p.y)))
            }
        }
    }

    func testMarksRectangleAsQuad() {
        let img = solid(100, 100)
        let out = SurfaceAssembler.assemble([rect(10, 10, 70, 60)], rgb: img)
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].isQuad)
        XCTAssertEqual(out[0].polygon.count, 4)
    }

    func testCapsToMaxResults() {
        let img = solid(200, 200)
        var polys: [[CGPoint]] = []
        for i in 0..<20 { let x = Double(i % 5) * 40; let y = Double(i / 5) * 40; polys.append(rect(x + 2, y + 2, x + 30, y + 30)) }
        let out = SurfaceAssembler.assemble(polys, rgb: img, config: .init(maxResults: 6, quadEpsilonFraction: 0.02))
        XCTAssertLessThanOrEqual(out.count, 6)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SurfaceAssemblerTests`
Expected: FAIL — `DetectedSurface` / `SurfaceAssembler` not found.

- [ ] **Step 3: Implement**

Create `Sources/LumoraKit/SurfaceDetection/CV/DetectedSurface.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SurfaceAssemblerTests`
Expected: PASS (3 tests). If `testNormalizesAndSortsBySize` merges the two rects (they shouldn't — far apart, same gray), verify `PolygonMerger.adjacencyDistance`. If `isQuad` is false for a clean rect, loosen `quadEpsilonFraction`.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS — ~159 tests (145 + 14 new), 0 failures (4 skipped).

- [ ] **Step 6: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/DetectedSurface.swift Tests/LumoraTests/SurfaceAssemblerTests.swift
git commit -m "feat(detect): DetectedSurface + SurfaceAssembler (merge/props/confidence/rank)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Demo — ranked surfaces on the real photos, save results

**Files:**
- Test: `Tests/LumoraTests/SurfaceAssemblerTests.swift` (add one opt-in demo test; add `import ImageIO`, `import UniformTypeIdentifiers`)

**Interfaces:**
- Consumes: `ImagePreprocessor.grayscale`/`.rgb`, `CannyEdgeDetector`, `RegionSegmenter`, `PolygonValidator`, `SurfaceAssembler`.
- Produces: no library symbols — writes `<name>_surfaces.png` overlays.

- [ ] **Step 1: Add the demo test**

Add imports to the top of `SurfaceAssemblerTests.swift`:

```swift
import ImageIO
import UniformTypeIdentifiers
```

Add to `SurfaceAssemblerTests`:

```swift
    func testWritesRankedSurfaceDemoWhenRequested() throws {
        guard let folder = ProcessInfo.processInfo.environment["SURFACE_DEMO_DIR"] else {
            throw XCTSkip("set SURFACE_DEMO_DIR")
        }
        let maxDim = Int(ProcessInfo.processInfo.environment["SURFACE_DEMO_MAXDIM"] ?? "1200")!
        let cs = CGColorSpaceCreateDeviceRGB()
        let fm = FileManager.default
        let jpegs = try fm.contentsOfDirectory(atPath: folder)
            .filter { $0.lowercased().hasSuffix(".jpeg") || $0.lowercased().hasSuffix(".jpg") }.sorted()

        for name in jpegs {
            let path = (folder as NSString).appendingPathComponent(name)
            guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            let gray = ImagePreprocessor.grayscale(from: cg, maxDimension: maxDim)
            let rgb = ImagePreprocessor.rgb(from: cg, maxDimension: maxDim)
            let edges = CannyEdgeDetector.detect(gray)
            let regions = RegionSegmenter.regions(from: edges)
            let valid = regions.filter { PolygonValidator.isValid($0.points, frameWidth: gray.width, frameHeight: gray.height) }
            let surfaces = SurfaceAssembler.assemble(valid.map { $0.points }, rgb: rgb)

            let W = gray.width, H = gray.height, fH = CGFloat(H)
            let out = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            out.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
            out.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.4)); out.fill(CGRect(x: 0, y: 0, width: W, height: H))
            let palette = [CGColor(red: 0.2, green: 1, blue: 0.5, alpha: 1), CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 1),
                           CGColor(red: 0.4, green: 0.6, blue: 1, alpha: 1), CGColor(red: 1, green: 0.4, blue: 0.8, alpha: 1),
                           CGColor(red: 1, green: 0.9, blue: 0.3, alpha: 1), CGColor(red: 0.5, green: 1, blue: 1, alpha: 1)]
            for (i, s) in surfaces.enumerated() {
                let denorm = s.polygon.map { CGPoint(x: $0.x * CGFloat(W), y: fH - $0.y * CGFloat(H)) }
                guard let first = denorm.first else { continue }
                let color = palette[i % palette.count]
                out.setStrokeColor(color); out.setLineWidth(max(2, CGFloat(W) / 380))
                out.setFillColor(color.copy(alpha: 0.16)!)
                out.move(to: first); for p in denorm.dropFirst() { out.addLine(to: p) }
                out.closePath(); out.drawPath(using: .fillStroke)
            }
            let img = out.makeImage()!
            let base = (name as NSString).deletingPathExtension
            let outURL = URL(fileURLWithPath: (folder as NSString).appendingPathComponent("\(base)_surfaces.png"))
            let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, img, nil)
            _ = CGImageDestinationFinalize(dest)
            print("SURFACES \(name) \(W)x\(H) count=\(surfaces.count) quads=\(surfaces.filter { $0.isQuad }.count) -> \(outURL.lastPathComponent)")
        }
    }
```

- [ ] **Step 2: Run the demo on the sample folder**

Run: `SURFACE_DEMO_DIR=/Users/zaks/Downloads/room-images swift test --filter SurfaceAssemblerTests/testWritesRankedSurfaceDemoWhenRequested`
Expected: PASS; prints per-image surface/quad counts and writes `<name>_surfaces.png`.

- [ ] **Step 3: Eyeball + tune**

Read the `_surfaces.png` overlays. Confirm the marble-wall fragments are merged, surfaces are ranked (biggest = whole surfaces), and normalized polygons overlay correctly. Tune `PolygonMerger.Config` (colorTolerance/adjacencyDistance) and `SurfaceAssembler.Config` (maxResults) if over/under-merged.

- [ ] **Step 4: Confirm default `swift test` skips it**

Run: `swift test --filter SurfaceAssemblerTests`
Expected: the demo test reports **skipped**; the others PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/LumoraTests/SurfaceAssemblerTests.swift
git commit -m "test(detect): ranked-surface demo overlay (opt-in)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (Stage 5 slice of the design doc):**
- Compute properties (area, perimeter, centroid, bbox, aspect, orientation, avg color) → Task 2. ✅
- Merge adjacent polygons (shared edge + similar color) → Task 3 (color+adjacency, convex-hull union). ✅
- Confidence score → Task 4. ✅
- Unify into `DetectedSurface`; normalized; quad-or-polygon; nesting; sort largest-first → Task 5. ✅
- Real-photo demo/verification → Task 6. ✅

**Placeholder scan:** No TBD/TODO; every code step complete; notes are concrete tuning guidance. ✅

**Type consistency:** `RGBImage` (T1) consumed by `SurfaceAnalyzer` (T2) and `SurfaceAssembler` (T5). `SurfaceAnalyzer.averageColor` feeds `PolygonMerger.Item.color` (T3←T5). `ConfidenceScorer.score` (T4) called in `SurfaceAssembler` (T5). `PolygonApproximator.simplify` reused for quad detection. `DetectedSurface` (T5) is the Stage-6 input. ✅

**Scope check:** Properties + merge + confidence + assembly/ranking only. Integration into `detect()`, region-growing source, and ProjectStore/review are Stage 6. ✅
```

