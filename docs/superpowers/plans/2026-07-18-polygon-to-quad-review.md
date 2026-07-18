# Polygon → Quad Review Toggle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A reversible per-surface **Make Quad** toggle in the detection review sheet that converts a detected polygon into a 4-corner quad (longest-adjacent-edges parallelogram, min-area enclosing-quad fallback).

**Architecture:** A pure, unit-tested `PolygonToQuad.convert` in LumoraKit (reusing `SurfaceGeometry` hull/quad/order helpers) plus a small, reversible per-item toggle in `SurfaceDetectionReviewView`. No model or save-format change.

**Tech Stack:** Swift, XCTest, SwiftUI/AppKit. LumoraKit geometry is unit-tested; the review-sheet change is build- + launch-verified.

## Global Constraints

- **Pure Swift** in LumoraKit; reuse `SurfaceGeometry` (`convexHull`, `enclosingQuad`, `orderedCorners`, `contains`).
- Points are normalized `[0,1]` top-left; `convert` always returns exactly 4 corners ordered TL,TR,BR,BL.
- Candidate-quad fitness uses **IoU** (intersection/union), not `overlapOverSmaller` (which is 1.0 for any quad contained in the polygon).
- Review-sheet toggle is **reversible** and shown only for non-quad items.
- LumoraKit tests stay green (currently 163) and grow; app verified by `swift build` + launch.

---

## File Structure

- `Sources/LumoraKit/SurfaceDetection/PolygonToQuad.swift` (create) — `convert` + sampled IoU.
- `Tests/LumoraTests/PolygonToQuadTests.swift` (create).
- `Sources/Lumora/Views/SurfaceDetectionReviewView.swift` (modify) — per-item Make Quad toggle.

---

### Task 1: `PolygonToQuad.convert` (LumoraKit)

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/PolygonToQuad.swift`
- Test: `Tests/LumoraTests/PolygonToQuadTests.swift`

**Interfaces:**
- Consumes: `SurfaceGeometry.convexHull`, `.enclosingQuad`, `.orderedCorners`, `.contains`.
- Produces: `enum PolygonToQuad { static func convert(_ polygon: [CGPoint]) -> [CGPoint] }` — returns 4 ordered corners. `count == 4` → ordered as-is; `count == 3` → parallelogram then ordered; `count < 3` → input unchanged; otherwise builds a best-3-adjacent-edge quad and a best-2-adjacent-edge parallelogram, picks the higher-IoU one if it clears **0.70**, else the enclosing-quad fallback.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/PolygonToQuadTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class PolygonToQuadTests: XCTestCase {
    private func area(_ p: [CGPoint]) -> Double { SurfaceGeometry.polygonArea(p) }

    /// Sampled IoU for assertions (independent of the implementation's own).
    private func iou(_ a: [CGPoint], _ b: [CGPoint]) -> Double {
        let pts = a + b
        var minX = pts[0].x, minY = pts[0].y, maxX = pts[0].x, maxY = pts[0].y
        for p in pts { minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y) }
        var inter = 0, uni = 0
        let s = 60
        for i in 0..<s { for j in 0..<s {
            let x = Double(minX) + (Double(maxX - minX)) * (Double(i) + 0.5) / Double(s)
            let y = Double(minY) + (Double(maxY - minY)) * (Double(j) + 0.5) / Double(s)
            let p = CGPoint(x: x, y: y)
            let ina = SurfaceGeometry.contains(p, in: a), inb = SurfaceGeometry.contains(p, in: b)
            if ina && inb { inter += 1 }
            if ina || inb { uni += 1 }
        } }
        return uni > 0 ? Double(inter) / Double(uni) : 0
    }

    func testAlreadyQuadReturnsFourCorners() {
        let sq = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        let q = PolygonToQuad.convert(sq)
        XCTAssertEqual(q.count, 4)
        XCTAssertEqual(Set(q.map { "\($0.x),\($0.y)" }), Set(sq.map { "\($0.x),\($0.y)" }))
    }

    func testThreePointsCompleteParallelogram() {
        // A=(0,0) B=(0,4) C=(3,4) → D = A + C − B = (3,0).
        let q = PolygonToQuad.convert([CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 4), CGPoint(x: 3, y: 4)])
        XCTAssertEqual(q.count, 4)
        XCTAssertTrue(q.contains { abs($0.x - 3) < 1e-6 && abs($0.y - 0) < 1e-6 }, "computed 4th corner (3,0)")
        XCTAssertEqual(area(q), 12, accuracy: 1e-6)
    }

    func testFivePointDominatedByThreeEdgesRecoversRectangle() {
        // Rectangle 10×6 with the left edge split by an extra midpoint (0,3).
        let poly = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 6),
                    CGPoint(x: 0, y: 6), CGPoint(x: 0, y: 3)]
        let q = PolygonToQuad.convert(poly)
        XCTAssertEqual(q.count, 4)
        // Recovers the clean rectangle → high IoU with the (nearly identical) polygon.
        XCTAssertGreaterThan(iou(q, poly), 0.9)
        XCTAssertEqual(area(q), 60, accuracy: 2)
    }

    func testBlobFallsBackToEnclosingQuad() {
        // Regular octagon — no 2–3 dominant adjacent edges.
        var poly: [CGPoint] = []
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi
            poly.append(CGPoint(x: 5 + 4 * cos(a), y: 5 + 4 * sin(a)))
        }
        let q = PolygonToQuad.convert(poly)
        XCTAssertEqual(q.count, 4)
        // The enclosing quad covers the whole octagon.
        XCTAssertGreaterThan(iou(q, poly), 0.75)
        XCTAssertGreaterThanOrEqual(area(q), area(poly) - 1e-6)
    }

    func testAlwaysReturnsFourOrderedCorners() {
        let poly = [CGPoint(x: 0, y: 0), CGPoint(x: 6, y: 1), CGPoint(x: 7, y: 5),
                    CGPoint(x: 3, y: 7), CGPoint(x: -1, y: 4), CGPoint(x: 0, y: 2)]
        XCTAssertEqual(PolygonToQuad.convert(poly).count, 4)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PolygonToQuadTests`
Expected: FAIL — `PolygonToQuad` not found.

- [ ] **Step 3: Implement `PolygonToQuad`**

Create `Sources/LumoraKit/SurfaceDetection/PolygonToQuad.swift`:

```swift
import CoreGraphics
import Foundation

/// Convert a detected polygon into a 4-corner quad, keeping the dominant real
/// edges as the base (a parallelogram from the 2–3 longest adjacent edges), with
/// a min-area enclosing-quad fallback for shapes that don't fit that heuristic.
public enum PolygonToQuad {
    public static func convert(_ polygon: [CGPoint]) -> [CGPoint] {
        let n = polygon.count
        if n < 3 { return polygon }
        if n == 4 { return SurfaceGeometry.orderedCorners(polygon) }
        if n == 3 { return SurfaceGeometry.orderedCorners(parallelogram(polygon[0], polygon[1], polygon[2])) }

        func edgeLen(_ i: Int) -> Double {
            let a = polygon[i], b = polygon[(i + 1) % n]
            let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            return (dx * dx + dy * dy).squareRoot()
        }

        // Best window of 3 consecutive edges → 4 vertices.
        var best3 = 0, best3Len = -1.0
        for i in 0..<n {
            let t = edgeLen(i) + edgeLen((i + 1) % n) + edgeLen((i + 2) % n)
            if t > best3Len { best3Len = t; best3 = i }
        }
        let q3 = [polygon[best3], polygon[(best3 + 1) % n], polygon[(best3 + 2) % n], polygon[(best3 + 3) % n]]

        // Best window of 2 consecutive edges → 3 vertices → parallelogram.
        var best2 = 0, best2Len = -1.0
        for i in 0..<n {
            let t = edgeLen(i) + edgeLen((i + 1) % n)
            if t > best2Len { best2Len = t; best2 = i }
        }
        let q2 = parallelogram(polygon[best2], polygon[(best2 + 1) % n], polygon[(best2 + 2) % n])

        let i3 = iou(q3, polygon), i2 = iou(q2, polygon)
        let (bestQuad, bestIoU) = i3 >= i2 ? (q3, i3) : (q2, i2)
        if bestIoU >= 0.70 { return SurfaceGeometry.orderedCorners(bestQuad) }

        let fb = SurfaceGeometry.enclosingQuad(SurfaceGeometry.convexHull(polygon))
        return SurfaceGeometry.orderedCorners(fb.count == 4 ? fb : bestQuad)
    }

    /// Fourth parallelogram corner D = A + C − B for the corner A-B-C.
    static func parallelogram(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> [CGPoint] {
        [a, b, c, CGPoint(x: a.x + c.x - b.x, y: a.y + c.y - b.y)]
    }

    /// Sampled intersection-over-union of two polygons.
    static func iou(_ a: [CGPoint], _ b: [CGPoint], samples: Int = 48) -> Double {
        let pts = a + b
        guard let first = pts.first else { return 0 }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in pts { minX = min(minX, p.x); minY = min(minY, p.y); maxX = max(maxX, p.x); maxY = max(maxY, p.y) }
        if maxX <= minX || maxY <= minY { return 0 }
        var inter = 0, uni = 0
        for i in 0..<samples {
            for j in 0..<samples {
                let x = minX + (maxX - minX) * (CGFloat(i) + 0.5) / CGFloat(samples)
                let y = minY + (maxY - minY) * (CGFloat(j) + 0.5) / CGFloat(samples)
                let p = CGPoint(x: x, y: y)
                let ina = SurfaceGeometry.contains(p, in: a), inb = SurfaceGeometry.contains(p, in: b)
                if ina && inb { inter += 1 }
                if ina || inb { uni += 1 }
            }
        }
        return uni > 0 ? Double(inter) / Double(uni) : 0
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PolygonToQuadTests`
Expected: PASS (5 tests). If `testFivePointDominatedByThreeEdgesRecoversRectangle` picks `q2` over `q3`, both should still yield high IoU; if the fallback triggers unexpectedly, lower the 0.70 gate slightly. If `testBlobFallsBackToEnclosingQuad` area is below the octagon, `enclosingQuad` returned a non-enclosing shape — verify hull orientation.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS — ~168 tests, 0 failures (6 skipped).

- [ ] **Step 6: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/PolygonToQuad.swift Tests/LumoraTests/PolygonToQuadTests.swift
git commit -m "feat(detect): PolygonToQuad.convert (longest-edges parallelogram + fallback)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Make Quad toggle in the review sheet (app)

**Files:**
- Modify: `Sources/Lumora/Views/SurfaceDetectionReviewView.swift`

**Interfaces:**
- `ReviewItem` gains `originalCorners: [CGPoint]` and `isQuadified: Bool`; `var systemImage` becomes mutable so the icon updates.
- A per-item **Make Quad** button appears in the strip for items whose original outline is not a quad; toggling converts/restores via `PolygonToQuad.convert`.

- [ ] **Step 1: Extend `ReviewItem` + init**

In `SurfaceDetectionReviewView.swift`, change the struct:

```swift
    private struct ReviewItem: Identifiable {
        let id = UUID()
        var corners: [CGPoint]        // normalized, top-left origin
        var originalCorners: [CGPoint] // detected outline, for revert
        var keep: Bool
        let label: String
        var systemImage: String
        var isQuadified = false
    }
```

In `init(image:surfaces:...)`, set `originalCorners`:

```swift
        _items = State(initialValue: surfaces.map { s in
            ReviewItem(corners: s.polygon, originalCorners: s.polygon, keep: true,
                       label: "\(Int(s.confidence * 100))%",
                       systemImage: s.isQuad ? "rectangle.dashed" : "hexagon")
        })
```

In the **Add Surface** button action (the manual centered rect), set `originalCorners` too:

```swift
                    items.append(ReviewItem(corners: Self.centeredRect(),
                                            originalCorners: Self.centeredRect(), keep: true,
                                            label: "Manual",
                                            systemImage: "plus.rectangle.on.rectangle"))
```

- [ ] **Step 2: Add the toggle to the item strip**

Replace the strip's `ForEach` body (the `Toggle(isOn: keepBinding(i)) { … }` block) with an HStack that adds the Make Quad button for non-quad items:

```swift
                        ForEach(items.indices, id: \.self) { i in
                            HStack(spacing: 4) {
                                Toggle(isOn: keepBinding(i)) {
                                    Label("\(i + 1) · \(items[i].label)", systemImage: items[i].systemImage)
                                }
                                .toggleStyle(.button)
                                .tint(palette[i % palette.count])

                                if items[i].originalCorners.count != 4 {
                                    Button { toggleQuad(i) } label: {
                                        Image(systemName: items[i].isQuadified ? "arrow.uturn.backward" : "square.on.square.dashed")
                                    }
                                    .buttonStyle(.borderless)
                                    .help(items[i].isQuadified ? "Revert to polygon" : "Make quad")
                                }
                            }
                        }
```

- [ ] **Step 3: Add `toggleQuad`**

Add near `keepBinding`:

```swift
    private func toggleQuad(_ i: Int) {
        if items[i].isQuadified {
            items[i].corners = items[i].originalCorners
            items[i].isQuadified = false
            items[i].systemImage = "hexagon"
        } else {
            items[i].corners = PolygonToQuad.convert(items[i].originalCorners)
            items[i].isQuadified = true
            items[i].systemImage = "rectangle.dashed"
        }
    }
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 5: Manual verification**

Build/launch the packaged app (`./scripts/make_app.sh`, `open dist/Lumora.app`). **Detect Surfaces** → pick a `room-images` JPEG → in the review sheet, find a polygon surface (hexagon icon), click its **Make Quad** button → the outline snaps to 4 draggable corners along the surface's dominant edges; the revert (↩) button restores the polygon. Keep it and **Add** → it becomes an editable quad surface on the canvas. Confirm quads (already 4 corners) show no Make Quad button.

- [ ] **Step 6: Commit**

```bash
git add Sources/Lumora/Views/SurfaceDetectionReviewView.swift
git commit -m "feat: per-surface Make Quad toggle in the detection review sheet

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- Per-surface reversible Make Quad toggle, only for polygons → Task 2. ✅
- Longest-adjacent-edges parallelogram (3-edge → 4 vertices; 2-edge → A+C−B) → Task 1. ✅
- Min-area enclosing-quad fallback → Task 1 (`enclosingQuad(convexHull(...))`). ✅
- Added 4-corner item → quad surface (existing count-based inference) → unchanged `addDetectedSurfaces`. ✅
- Unit tests + build + manual review-sheet check → Tasks 1–2. ✅

**Placeholder scan:** No TBD/TODO; complete code in every step; notes are concrete tuning/verification guidance. ✅

**Type consistency:** `PolygonToQuad.convert([CGPoint]) -> [CGPoint]` (T1) is called by `toggleQuad` (T2) on `ReviewItem.originalCorners`; output feeds the existing `corners`/handles/`onAdd` path unchanged. Fitness uses the local `iou`, not `overlapOverSmaller`. ✅

**Scope check:** Geometry helper + one review-view control. No detection, model, or save-format change. ✅
```

