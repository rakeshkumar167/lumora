# Surface Detection — Stage 3: Contours + Polygon Approximation (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trace the boundaries of regions in a binary image as contours **with nesting hierarchy** (a region inside another is a child), then simplify each contour to a polygon.

**Architecture:** New `Contour` model + `ConnectedComponents`, `ContourTracer`, `PolygonApproximator` enums under `Sources/LumoraKit/SurfaceDetection/CV/`. Pure Swift.

**Design deviation (documented):** the design doc named *Suzuki–Abe* for contours-with-hierarchy. Its hole-border/topology bookkeeping is error-prone to reimplement correctly in pure Swift. This stage delivers the **same contract** — contours with parent/child hierarchy ("findContours RETR_TREE equivalent") — via a more robust, testable route: **connected-components labeling → Moore-neighbor boundary tracing per component → containment-based nesting**. In the pipeline, each planar region ends up as its own foreground component (Stage 4 produces the region binary), so containment nesting yields correct "region-inside-region" hierarchy. This is a reversible internal change; the output type is what later stages consume.

**Tech Stack:** Swift, XCTest, CoreGraphics (only the opt-in overlay). Target: `LumoraKit`; tests: `LumoraTests`.

## Global Constraints

- **Pure Swift only** — no OpenCV/Vision/ML. CoreGraphics used only by the opt-in overlay test.
- **Deterministic** — identical input yields identical output; components are labeled and traced in raster-scan order.
- Coordinates are working-image **pixels**, top-left origin; contour points are `CGPoint`.
- Foreground = `true` in the input binary `[Bool]` (row-major, length `width*height`).
- All new types `public`; helpers may be `internal` for `@testable`.
- `swift test` stays green (currently 123 tests, 1 skipped) and grows.

---

## File Structure

- `Sources/LumoraKit/SurfaceDetection/CV/Contour.swift` (create) — `Contour` model.
- `Sources/LumoraKit/SurfaceDetection/CV/ConnectedComponents.swift` (create) — foreground component labeling.
- `Sources/LumoraKit/SurfaceDetection/CV/ContourTracer.swift` (create) — Moore boundary trace + containment hierarchy.
- `Sources/LumoraKit/SurfaceDetection/CV/PolygonApproximator.swift` (create) — Douglas–Peucker.
- `Tests/LumoraTests/ConnectedComponentsTests.swift` (create)
- `Tests/LumoraTests/ContourTracerTests.swift` (create)
- `Tests/LumoraTests/PolygonApproximatorTests.swift` (create)

---

### Task 1: `Contour` model + connected-components labeling

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/Contour.swift`
- Create: `Sources/LumoraKit/SurfaceDetection/CV/ConnectedComponents.swift`
- Test: `Tests/LumoraTests/ConnectedComponentsTests.swift`

**Interfaces:**
- Produces:
  - `struct Contour: Equatable { var points: [CGPoint]; var parentIndex: Int? }` — boundary points (pixel coords); `parentIndex` = index into the tracer's returned array of the smallest enclosing contour, or `nil` for top-level.
  - `struct LabelField { let width: Int; let height: Int; var labels: [Int]; let count: Int }` — `labels[y*w+x]` is 0 for background or 1…count for a component.
  - `enum ConnectedComponents { static func label(_ binary: [Bool], width: Int, height: Int) -> LabelField }` — 8-connected foreground components, labeled in raster-scan discovery order via iterative flood fill.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/ConnectedComponentsTests.swift`:

```swift
import XCTest
@testable import LumoraKit

final class ConnectedComponentsTests: XCTestCase {
    /// Paint filled rectangles (true) into a binary grid.
    private func grid(_ w: Int, _ h: Int, _ rects: [(Int, Int, Int, Int)]) -> [Bool] {
        var b = [Bool](repeating: false, count: w * h)
        for (x0, y0, x1, y1) in rects { for y in y0...y1 { for x in x0...x1 { b[y * w + x] = true } } }
        return b
    }

    func testSingleComponent() {
        let f = ConnectedComponents.label(grid(20, 20, [(5, 5, 12, 12)]), width: 20, height: 20)
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f.labels[8 * 20 + 8], 1)
        XCTAssertEqual(f.labels[0], 0)
    }

    func testTwoSeparateComponents() {
        let f = ConnectedComponents.label(grid(30, 20, [(2, 2, 8, 8), (18, 2, 26, 8)]), width: 30, height: 20)
        XCTAssertEqual(f.count, 2)
        XCTAssertNotEqual(f.labels[5 * 30 + 5], f.labels[5 * 30 + 22])
        XCTAssertGreaterThan(f.labels[5 * 30 + 5], 0)
        XCTAssertGreaterThan(f.labels[5 * 30 + 22], 0)
    }

    func testDiagonalPixelsAre8Connected() {
        var b = [Bool](repeating: false, count: 9)
        b[0] = true; b[4] = true // (0,0) and (1,1) touch diagonally
        let f = ConnectedComponents.label(b, width: 3, height: 3)
        XCTAssertEqual(f.count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ConnectedComponentsTests`
Expected: FAIL — `ConnectedComponents` / `LabelField` not found.

- [ ] **Step 3: Implement `Contour` + `ConnectedComponents`**

Create `Sources/LumoraKit/SurfaceDetection/CV/Contour.swift`:

```swift
import CoreGraphics

/// A traced region boundary with optional nesting parent.
public struct Contour: Equatable {
    public var points: [CGPoint]
    public var parentIndex: Int?
    public init(points: [CGPoint], parentIndex: Int? = nil) {
        self.points = points; self.parentIndex = parentIndex
    }
}
```

Create `Sources/LumoraKit/SurfaceDetection/CV/ConnectedComponents.swift`:

```swift
import Foundation

/// Foreground component labels: 0 = background, 1…count = components.
public struct LabelField: Equatable {
    public let width: Int
    public let height: Int
    public var labels: [Int]
    public let count: Int
}

/// 8-connected connected-component labeling via iterative flood fill.
public enum ConnectedComponents {
    public static func label(_ binary: [Bool], width w: Int, height h: Int) -> LabelField {
        var labels = [Int](repeating: 0, count: w * h)
        var next = 0
        let dx = [-1, 0, 1, -1, 1, -1, 0, 1]
        let dy = [-1, -1, -1, 0, 0, 1, 1, 1]
        var stack: [Int] = []
        for start in 0..<(w * h) where binary[start] && labels[start] == 0 {
            next += 1
            labels[start] = next
            stack.append(start)
            while let idx = stack.popLast() {
                let x = idx % w, y = idx / w
                for k in 0..<8 {
                    let nx = x + dx[k], ny = y + dy[k]
                    if nx >= 0, nx < w, ny >= 0, ny < h {
                        let j = ny * w + nx
                        if binary[j], labels[j] == 0 { labels[j] = next; stack.append(j) }
                    }
                }
            }
        }
        return LabelField(width: w, height: h, labels: labels, count: next)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ConnectedComponentsTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/Contour.swift \
        Sources/LumoraKit/SurfaceDetection/CV/ConnectedComponents.swift \
        Tests/LumoraTests/ConnectedComponentsTests.swift
git commit -m "feat(detect): Contour model + connected-components labeling

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `ContourTracer` — Moore trace + containment hierarchy

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/ContourTracer.swift`
- Test: `Tests/LumoraTests/ContourTracerTests.swift`

**Interfaces:**
- Consumes: `ConnectedComponents.label`, `LabelField`, `Contour`.
- Produces: `enum ContourTracer { static func traceContours(binary: [Bool], width: Int, height: Int) -> [Contour] }` — one contour per foreground component (Moore-neighbor boundary trace, clockwise); `parentIndex` set to the smallest other contour that contains the component's first boundary point.
- Internal helpers (for `@testable`): `mooreTrace(_ labels: LabelField, label: Int, start: (Int, Int)) -> [CGPoint]`, `pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool`, `polygonArea(_ poly: [CGPoint]) -> Double`.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/ContourTracerTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class ContourTracerTests: XCTestCase {
    private func grid(_ w: Int, _ h: Int, _ paint: (Int, Int) -> Bool) -> [Bool] {
        var b = [Bool](repeating: false, count: w * h)
        for y in 0..<h { for x in 0..<w { b[y * w + x] = paint(x, y) } }
        return b
    }

    private func bbox(_ pts: [CGPoint]) -> (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
        var a = pts[0], b = pts[0]
        for p in pts { a.x = min(a.x, p.x); a.y = min(a.y, p.y); b.x = max(b.x, p.x); b.y = max(b.y, p.y) }
        return (a.x, a.y, b.x, b.y)
    }

    func testTracesFilledRectangleBoundary() {
        let b = grid(24, 24) { x, y in (5...18).contains(x) && (5...18).contains(y) }
        let cs = ContourTracer.traceContours(binary: b, width: 24, height: 24)
        XCTAssertEqual(cs.count, 1)
        let bb = bbox(cs[0].points)
        XCTAssertEqual(bb.minX, 5, accuracy: 1); XCTAssertEqual(bb.minY, 5, accuracy: 1)
        XCTAssertEqual(bb.maxX, 18, accuracy: 1); XCTAssertEqual(bb.maxY, 18, accuracy: 1)
        XCTAssertNil(cs[0].parentIndex)
    }

    func testTwoSeparateRectanglesAreBothTopLevel() {
        let b = grid(40, 20) { x, y in ((2...10).contains(x) || (28...36).contains(x)) && (4...14).contains(y) }
        let cs = ContourTracer.traceContours(binary: b, width: 40, height: 20)
        XCTAssertEqual(cs.count, 2)
        XCTAssertTrue(cs.allSatisfy { $0.parentIndex == nil })
    }

    func testInnerComponentIsChildOfSurroundingFrame() {
        // A square ring (frame) with a separate filled square inside its hole.
        let b = grid(40, 40) { x, y in
            let onFrame = (5...34).contains(x) && (5...34).contains(y)
                && !((9...30).contains(x) && (9...30).contains(y))
            let inner = (15...24).contains(x) && (15...24).contains(y)
            return onFrame || inner
        }
        let cs = ContourTracer.traceContours(binary: b, width: 40, height: 40)
        XCTAssertEqual(cs.count, 2)
        // Exactly one contour has the other as parent.
        let children = cs.filter { $0.parentIndex != nil }
        XCTAssertEqual(children.count, 1)
        // The child is the smaller (inner) contour.
        let childIdx = cs.firstIndex { $0.parentIndex != nil }!
        let parentIdx = cs[childIdx].parentIndex!
        XCTAssertLessThan(ContourTracer.polygonArea(cs[childIdx].points),
                          ContourTracer.polygonArea(cs[parentIdx].points))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ContourTracerTests`
Expected: FAIL — `ContourTracer` not found.

- [ ] **Step 3: Implement `ContourTracer`**

Create `Sources/LumoraKit/SurfaceDetection/CV/ContourTracer.swift`:

```swift
import CoreGraphics
import Foundation

/// Region-boundary contours with containment hierarchy.
///
/// Each foreground component's outer boundary is traced (Moore-neighbor
/// tracing, clockwise). Nesting is derived by point-in-polygon containment:
/// a contour's parent is the smallest other contour that encloses it.
public enum ContourTracer {
    public static func traceContours(binary: [Bool], width w: Int, height h: Int) -> [Contour] {
        let field = ConnectedComponents.label(binary, width: w, height: h)
        if field.count == 0 { return [] }

        // First boundary-start pixel (raster order) for each label.
        var starts = [(Int, Int)?](repeating: nil, count: field.count + 1)
        for y in 0..<h {
            for x in 0..<w {
                let l = field.labels[y * w + x]
                if l > 0, starts[l] == nil { starts[l] = (x, y) }
            }
        }

        var polys: [[CGPoint]] = []
        for label in 1...field.count {
            guard let s = starts[label] else { continue }
            polys.append(mooreTrace(field, label: label, start: s))
        }

        // Containment hierarchy: parent = smallest OTHER polygon enclosing this
        // polygon's first point.
        var contours: [Contour] = []
        for i in polys.indices {
            let p0 = polys[i][0]
            var bestParent: Int? = nil
            var bestArea = Double.greatestFiniteMagnitude
            for j in polys.indices where j != i {
                if pointInPolygon(p0, polys[j]) {
                    let a = polygonArea(polys[j])
                    if a < bestArea { bestArea = a; bestParent = j }
                }
            }
            contours.append(Contour(points: polys[i], parentIndex: bestParent))
        }
        return contours
    }

    // 8 directions clockwise: W, NW, N, NE, E, SE, S, SW.
    private static let dx = [-1, -1, 0, 1, 1, 1, 0, -1]
    private static let dy = [0, -1, -1, -1, 0, 1, 1, 1]

    private static func dirIndex(_ ddx: Int, _ ddy: Int) -> Int {
        for d in 0..<8 where dx[d] == ddx && dy[d] == ddy { return d }
        return 0
    }

    /// Moore-neighbor boundary trace (clockwise) of one component.
    static func mooreTrace(_ field: LabelField, label: Int, start: (Int, Int)) -> [CGPoint] {
        let w = field.width, h = field.height
        func isFg(_ x: Int, _ y: Int) -> Bool { x >= 0 && x < w && y >= 0 && y < h && field.labels[y * w + x] == label }

        var boundary: [CGPoint] = []
        var px = start.0, py = start.1
        // Came from the west (the pixel to the left is background since `start`
        // is the first pixel of its component in raster order).
        var bx = start.0 - 1, by = start.1
        let maxSteps = 8 * w * h + 8
        var steps = 0
        while steps < maxSteps {
            boundary.append(CGPoint(x: px, y: py))
            let startDir = dirIndex(bx - px, by - py)
            var foundNext = false
            var nx = px, ny = py, nbx = bx, nby = by
            for k in 1...8 {
                let d = (startDir + k) % 8
                let cx = px + dx[d], cy = py + dy[d]
                if isFg(cx, cy) {
                    nx = cx; ny = cy
                    let pd = (d + 7) % 8            // the neighbor examined just before (background)
                    nbx = px + dx[pd]; nby = py + dy[pd]
                    foundNext = true
                    break
                }
            }
            if !foundNext { break }                 // isolated pixel
            if nx == start.0 && ny == start.1 { break } // closed the loop
            px = nx; py = ny; bx = nbx; by = nby
            steps += 1
        }
        return boundary
    }

    /// Ray-cast point-in-polygon (even-odd rule).
    static func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        if poly.count < 3 { return false }
        var inside = false
        var j = poly.count - 1
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

    /// Absolute polygon area (shoelace).
    static func polygonArea(_ poly: [CGPoint]) -> Double {
        if poly.count < 3 { return 0 }
        var s = 0.0
        var j = poly.count - 1
        for i in poly.indices {
            s += Double(poly[j].x + poly[i].x) * Double(poly[j].y - poly[i].y)
            j = i
        }
        return abs(s) / 2
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ContourTracerTests`
Expected: PASS (3 tests). If `testTracesFilledRectangleBoundary` reports a truncated boundary (bbox smaller than expected), the loop-close criterion stopped early — inspect and, if needed, relax the stop to Jacob's criterion (stop only when returning to `start` from the original backtrack pixel). If containment is wrong, verify `mooreTrace` produces a closed clockwise ring.

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/ContourTracer.swift \
        Tests/LumoraTests/ContourTracerTests.swift
git commit -m "feat(detect): ContourTracer (Moore trace + containment hierarchy)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `PolygonApproximator` — Douglas–Peucker

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/PolygonApproximator.swift`
- Test: `Tests/LumoraTests/PolygonApproximatorTests.swift`

**Interfaces:**
- Produces: `enum PolygonApproximator { static func simplify(_ points: [CGPoint], epsilon: Double) -> [CGPoint] }` — Douglas–Peucker on an open polyline; the caller treats a contour as closed by simplifying its point list (endpoints preserved).

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/PolygonApproximatorTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class PolygonApproximatorTests: XCTestCase {
    func testStraightLineReducesToEndpoints() {
        let pts = (0...10).map { CGPoint(x: Double($0), y: 0.0) }
        let s = PolygonApproximator.simplify(pts, epsilon: 0.5)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s.first, CGPoint(x: 0, y: 0))
        XCTAssertEqual(s.last, CGPoint(x: 10, y: 0))
    }

    func testRightAngleKeepsTheCorner() {
        var pts = (0...10).map { CGPoint(x: Double($0), y: 0.0) }
        pts += (1...10).map { CGPoint(x: 10.0, y: Double($0)) }
        let s = PolygonApproximator.simplify(pts, epsilon: 0.5)
        XCTAssertEqual(s.count, 3, "start, corner, end")
        XCTAssertEqual(s[1], CGPoint(x: 10, y: 0))
    }

    func testJitterWithinEpsilonIsRemoved() {
        let pts = (0...10).map { CGPoint(x: Double($0), y: ($0 % 2 == 0) ? 0.2 : -0.2) }
        let s = PolygonApproximator.simplify(pts, epsilon: 0.5)
        XCTAssertEqual(s.count, 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PolygonApproximatorTests`
Expected: FAIL — `PolygonApproximator` not found.

- [ ] **Step 3: Implement `PolygonApproximator`**

Create `Sources/LumoraKit/SurfaceDetection/CV/PolygonApproximator.swift`:

```swift
import CoreGraphics
import Foundation

/// Douglas–Peucker polyline simplification.
public enum PolygonApproximator {
    public static func simplify(_ points: [CGPoint], epsilon: Double) -> [CGPoint] {
        if points.count < 3 { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true; keep[points.count - 1] = true
        simplifyRange(points, 0, points.count - 1, epsilon, &keep)
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    private static func simplifyRange(_ pts: [CGPoint], _ lo: Int, _ hi: Int,
                                      _ eps: Double, _ keep: inout [Bool]) {
        if hi <= lo + 1 { return }
        var maxDist = 0.0, idx = lo
        for i in (lo + 1)..<hi {
            let d = perpDistance(pts[i], pts[lo], pts[hi])
            if d > maxDist { maxDist = d; idx = i }
        }
        if maxDist > eps {
            keep[idx] = true
            simplifyRange(pts, lo, idx, eps, &keep)
            simplifyRange(pts, idx, hi, eps, &keep)
        }
    }

    /// Perpendicular distance from `p` to the segment (a, b).
    static func perpDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let len = (dx * dx + dy * dy).squareRoot()
        if len < 1e-12 { return Double((p.x - a.x).magnitude + (p.y - a.y).magnitude) }
        let area2 = abs(dx * Double(p.y - a.y) - dy * Double(p.x - a.x))
        return area2 / len
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PolygonApproximatorTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS — ~132 tests (123 + 9 new), 0 failures (1 skipped overlay).

- [ ] **Step 6: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/PolygonApproximator.swift \
        Tests/LumoraTests/PolygonApproximatorTests.swift
git commit -m "feat(detect): Douglas-Peucker polygon approximation

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Eyeball overlay — traced + simplified polygons with hierarchy

**Files:**
- Test: `Tests/LumoraTests/ContourTracerTests.swift` (add one opt-in artifact test; add `import ImageIO` + `import UniformTypeIdentifiers`)

**Interfaces:**
- Consumes: `ContourTracer.traceContours`, `PolygonApproximator.simplify`.
- Produces: no library symbols — writes a PNG.

- [ ] **Step 1: Add the artifact test**

Add the imports to the top of `ContourTracerTests.swift`:

```swift
import ImageIO
import UniformTypeIdentifiers
```

Add to `ContourTracerTests`:

```swift
    func testWritesContourOverlayArtifactWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["CONTOUR_OVERLAY"] == "1" else {
            throw XCTSkip("set CONTOUR_OVERLAY=1 to write the overlay artifact")
        }
        // Binary: an outer frame with a nested filled square inside its hole,
        // plus a separate square elsewhere — exercises nesting + siblings.
        let w = 200, h = 160
        let b = grid(w, h) { x, y in
            let frame = (20...120).contains(x) && (20...120).contains(y)
                && !((34...106).contains(x) && (34...106).contains(y))
            let nested = (55...85).contains(x) && (55...85).contains(y)
            let sibling = (150...185).contains(x) && (40...110).contains(y)
            return frame || nested || sibling
        }
        let contours = ContourTracer.traceContours(binary: b, width: w, height: h)

        let cs = CGColorSpaceCreateDeviceRGB()
        let out = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        out.setFillColor(CGColor(red: 0.09, green: 0.09, blue: 0.11, alpha: 1)); out.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let H = CGFloat(h)
        let palette = [CGColor(red: 0.2, green: 1, blue: 0.4, alpha: 1),
                       CGColor(red: 1, green: 0.7, blue: 0.2, alpha: 1),
                       CGColor(red: 0.4, green: 0.6, blue: 1, alpha: 1)]
        for (i, c) in contours.enumerated() {
            let poly = PolygonApproximator.simplify(c.points, epsilon: 2.0)
            let depth = c.parentIndex == nil ? 0 : 1
            out.setStrokeColor(palette[(depth + i) % palette.count]); out.setLineWidth(2)
            guard let first = poly.first else { continue }
            out.move(to: CGPoint(x: first.x, y: H - first.y))
            for p in poly.dropFirst() { out.addLine(to: CGPoint(x: p.x, y: H - p.y)) }
            out.closePath(); out.strokePath()
        }
        let img = out.makeImage()!
        let dir = ProcessInfo.processInfo.environment["CONTOUR_OVERLAY_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent("contour_overlay.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        print("CONTOUR_OVERLAY written to: \(url.path) — contours: \(contours.count), nested: \(contours.filter { $0.parentIndex != nil }.count)")
    }
```

- [ ] **Step 2: Run the artifact test**

Run: `CONTOUR_OVERLAY=1 swift test --filter ContourTracerTests/testWritesContourOverlayArtifactWhenRequested`
Expected: PASS; prints path and counts (expect 3 contours, 1 nested).

- [ ] **Step 3: Eyeball the artifact**

Open/Read the printed `contour_overlay.png`. Confirm: the frame's outer square, the nested inner square, and the separate sibling square are each outlined as clean simplified polygons (≈4 corners each), and the nested square is drawn inside the frame.

- [ ] **Step 4: Confirm default `swift test` skips it**

Run: `swift test --filter ContourTracerTests`
Expected: the artifact test reports **skipped**; the others PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/LumoraTests/ContourTracerTests.swift
git commit -m "test(detect): contour + polygon overlay artifact (opt-in)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (Stage 3 slice of the design doc):**
- Contour detection with hierarchy ("findContours RETR_TREE equivalent") → Tasks 1–2 (CC + Moore + containment; deviation from literal Suzuki–Abe documented at top). ✅
- Keep nested polygons separate, linked to parent → Task 2 (`parentIndex`). ✅
- Polygon approximation (`approxPolyDP`) → Task 3 (Douglas–Peucker). ✅
- Deterministic, pure Swift → all tasks. ✅
- Eyeball overlay verification → Task 4. ✅

**Placeholder scan:** No TBD/TODO; every code step complete; notes are concrete debugging/import guidance. ✅

**Type consistency:** `Contour` (Task 1) produced by `ContourTracer.traceContours` (Task 2) and consumed by the overlay (Task 4). `LabelField` (Task 1) consumed by `mooreTrace` (Task 2). `PolygonApproximator.simplify([CGPoint], epsilon:) -> [CGPoint]` (Task 3) consumed by the overlay (Task 4). Contour points are `[CGPoint]`, matching what Stage 4/5 will consume. ✅

**Scope check:** Contours + polygon simplification only. Validation, adjacency merge, properties, confidence, ranking, and integration are later stages. ✅
```

