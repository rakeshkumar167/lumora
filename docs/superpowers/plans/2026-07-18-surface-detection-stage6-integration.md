# Surface Detection — Stage 6: App Integration (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the classical-CV pipeline into the app: a new `SurfaceDetector.detectSurfaces(in:) -> [DetectedSurface]` (contour pipeline + region-growing second source, no Vision), and adapt `ProjectStore.addDetectedSurfaces` + `SurfaceDetectionReviewView` + `WorkspaceView` so the **Detect Surfaces** button produces quads-or-polygons.

**Architecture:** `detectSurfaces` runs the Stage 1–5 pipeline (Canny → regions → validate → assemble) and, as a second candidate source, the existing region-growing plane pass (`segment` + `regionPlaneCandidates`) converted to `DetectedSurface`; the two are de-duplicated by bounding-box IoU and ranked. The **Vision rectangle pass is not used** by the new entry (the legacy `detect()` stays for its tests but the app no longer calls it). The review view already renders N-point polygons and drags N handles, so it needs only a type swap; `addDetectedSurfaces` infers `.quad` (4 corners) vs `.polygon`.

**Tech Stack:** Swift, XCTest, SwiftUI/AppKit. LumoraKit (detector) is unit-tested; app-module changes (`Sources/Lumora`) are build- + launch-verified (not in the test target).

## Global Constraints

- **Pure Swift only** in LumoraKit — no OpenCV/Vision/ML in the new path.
- `DetectedSurface` coordinates are normalized `[0,1]`, top-left — same convention as `DetectedQuad.corners`, so the review view and `Surface` consume them unchanged.
- **Do not break the legacy `detect()`** or its `SurfaceDetectorTests` (keep it as-is; the app just stops calling it).
- `.lumora` save format unchanged (detected surfaces become ordinary `Surface`s).
- LumoraKit tests must stay green (currently 160, 5 skipped) and grow; app module verified by `swift build` + packaged-app launch.

---

## File Structure

- `Sources/LumoraKit/SurfaceDetection/SurfaceDetector.swift` (modify) — add `detectSurfaces` + quad→surface conversion + IoU dedup.
- `Tests/LumoraTests/DetectSurfacesTests.swift` (create) — unit + opt-in real-photo overlay.
- `Sources/Lumora/ProjectStore.swift` (modify) — `addDetectedSurfaces` infers quad/polygon.
- `Sources/Lumora/Views/SurfaceDetectionReviewView.swift` (modify) — take `[DetectedSurface]`.
- `Sources/Lumora/Views/WorkspaceView.swift` (modify) — `[DetectedSurface]` state + call `detectSurfaces`.

---

### Task 1: `SurfaceDetector.detectSurfaces` (LumoraKit)

**Files:**
- Modify: `Sources/LumoraKit/SurfaceDetection/SurfaceDetector.swift`
- Test: `Tests/LumoraTests/DetectSurfacesTests.swift`

**Interfaces:**
- Produces: `SurfaceDetector.detectSurfaces(in image: CGImage, options: Options = .init()) -> [DetectedSurface]` — runs the contour pipeline (`grayscale`→`CannyEdgeDetector`→`RegionSegmenter`→`PolygonValidator`→`SurfaceAssembler`) and the region-growing plane pass (converted to `DetectedSurface`), de-dups by bbox IoU (keep higher confidence), sorts largest-first, caps to `options.ranker.maxResults`.
- Internal helpers: `surfaceFromQuad(_ q: DetectedQuad, rgb: RGBImage) -> DetectedSurface`, `bboxIoU(_ a: CGRect, _ b: CGRect) -> Double`.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/DetectSurfacesTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class DetectSurfacesTests: XCTestCase {
    /// A synthetic room: gradient wall, a floor band, and a dark rectangular screen.
    private func syntheticRoom(_ w: Int = 800, _ h: Int = 600) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.80, green: 0.78, blue: 0.74, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.55, green: 0.53, blue: 0.50, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h / 4)) // floor band
        ctx.setFillColor(CGColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1))
        ctx.fill(CGRect(x: Double(w) * 0.35, y: Double(h) * 0.40, width: Double(w) * 0.35, height: Double(h) * 0.32)) // screen
        return ctx.makeImage()!
    }

    func testReturnsNormalizedSortedSurfaces() {
        let surfaces = SurfaceDetector.detectSurfaces(in: syntheticRoom())
        XCTAssertFalse(surfaces.isEmpty, "should detect at least one surface")
        // Largest first.
        for i in 1..<surfaces.count { XCTAssertGreaterThanOrEqual(surfaces[i - 1].area, surfaces[i].area) }
        // Normalized coordinates.
        for s in surfaces { for p in s.polygon {
            XCTAssertTrue((-0.01...1.01).contains(Double(p.x)))
            XCTAssertTrue((-0.01...1.01).contains(Double(p.y)))
        } }
    }

    func testRespectsMaxResults() {
        var opts = SurfaceDetector.Options()
        opts.ranker.maxResults = 3
        XCTAssertLessThanOrEqual(SurfaceDetector.detectSurfaces(in: syntheticRoom(), options: opts).count, 3)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DetectSurfacesTests`
Expected: FAIL — `detectSurfaces` not found.

- [ ] **Step 3: Implement**

Add to the `SurfaceDetector` enum in `SurfaceDetector.swift` (after `detect`):

```swift
    // MARK: - Classical-CV surface pipeline (Stage 1–5) + region-growing source

    /// Detect candidate surfaces as normalized quads-or-polygons using the
    /// pure-Swift contour pipeline plus the region-growing plane pass. No Vision.
    public static func detectSurfaces(in image: CGImage, options: Options = .init()) -> [DetectedSurface] {
        let dim = options.maxVisionWidth
        let gray = ImagePreprocessor.grayscale(from: image, maxDimension: dim)
        let rgb = ImagePreprocessor.rgb(from: image, maxDimension: dim)

        // Source 1: edge/contour pipeline.
        let edges = CannyEdgeDetector.detect(gray)
        let regions = RegionSegmenter.regions(from: edges)
        let valid = regions.filter {
            PolygonValidator.isValid($0.points, frameWidth: gray.width, frameHeight: gray.height)
        }
        var surfaces = SurfaceAssembler.assemble(valid.map { $0.points }, rgb: rgb,
                                                 config: .init(maxResults: options.ranker.maxResults * 2))

        // Source 2: region-growing plane pass (blank walls the edges miss).
        if let seg = segment(resized(image, maxDimension: options.maxVisionWidth), options: options) {
            for q in regionPlaneCandidates(seg, options: options) {
                surfaces.append(surfaceFromQuad(q, rgb: rgb))
            }
        }

        // De-duplicate overlapping candidates (keep higher confidence), rank, cap.
        surfaces.sort { $0.confidence > $1.confidence }
        var kept: [DetectedSurface] = []
        for s in surfaces where !kept.contains(where: { bboxIoU($0.boundingBox, s.boundingBox) > 0.5 }) {
            kept.append(s)
        }
        kept.sort { $0.area > $1.area }
        if kept.count > options.ranker.maxResults { kept = Array(kept.prefix(options.ranker.maxResults)) }
        return kept
    }

    static func surfaceFromQuad(_ q: DetectedQuad, rgb: RGBImage) -> DetectedSurface {
        let px = q.corners.map { CGPoint(x: $0.x * CGFloat(rgb.width), y: $0.y * CGFloat(rgb.height)) }
        let props = SurfaceAnalyzer.properties(of: px, in: rgb)
        let conf = ConfidenceScorer.score(px, frameWidth: rgb.width, frameHeight: rgb.height)
        let bb = props.boundingBox
        return DetectedSurface(
            polygon: q.corners, isQuad: true, area: q.areaFraction, perimeter: props.perimeter,
            aspectRatio: props.aspectRatio, orientation: props.orientation, confidence: conf,
            centroid: CGPoint(x: props.centroid.x / CGFloat(rgb.width), y: props.centroid.y / CGFloat(rgb.height)),
            boundingBox: CGRect(x: bb.minX / CGFloat(rgb.width), y: bb.minY / CGFloat(rgb.height),
                                width: bb.width / CGFloat(rgb.width), height: bb.height / CGFloat(rgb.height)),
            averageColor: props.averageColor)
    }

    static func bboxIoU(_ a: CGRect, _ b: CGRect) -> Double {
        let inter = a.intersection(b)
        if inter.isNull { return 0 }
        let i = Double(inter.width * inter.height)
        let u = Double(a.width * a.height + b.width * b.height) - i
        return u > 0 ? i / u : 0
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DetectSurfacesTests`
Expected: PASS (2 tests). If empty on the synthetic room, the screen rectangle should still segment — check `RegionSegmenter` default `dilateRadius` and that the region-growing pass contributes.

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS — ~162 tests, 0 failures (5 skipped).

- [ ] **Step 6: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/SurfaceDetector.swift Tests/LumoraTests/DetectSurfacesTests.swift
git commit -m "feat(detect): SurfaceDetector.detectSurfaces (contour + region-growing, no Vision)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `ProjectStore.addDetectedSurfaces` — quad-or-polygon (app)

**Files:**
- Modify: `Sources/Lumora/ProjectStore.swift:169-178`

**Interfaces:**
- Produces: `addDetectedSurfaces(_ polygons: [[CGPoint]])` — for each corner set, creates a `Surface` with `shape: .quad` when it has exactly 4 points, else `shape: .polygon`; grid default media; selects the first.

- [ ] **Step 1: Update the method**

Replace `addDetectedSurfaces` in `ProjectStore.swift`:

```swift
    /// Append one editable surface per detected corner set (normalized,
    /// top-left origin). Four corners → a homography quad; otherwise a polygon.
    func addDetectedSurfaces(_ polygons: [[CGPoint]]) {
        guard !polygons.isEmpty else { return }
        var firstID: Surface.ID?
        for pts in polygons where pts.count >= 3 {
            let shape: SurfaceShape = pts.count == 4 ? .quad : .polygon
            var s = Surface(name: "Surface \(surfaces.count + 1)", points: pts, shape: shape)
            s.media = .effect(.grid, .cyan, RGBAColor(r: 0.05, g: 0.06, b: 0.09))
            surfaces.append(s)
            if firstID == nil { firstID = s.id }
        }
        if let firstID { selectSurface(firstID) }
    }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add Sources/Lumora/ProjectStore.swift
git commit -m "feat: addDetectedSurfaces maps 4-corner->quad, else polygon

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Review view + WorkspaceView take `[DetectedSurface]` (app)

**Files:**
- Modify: `Sources/Lumora/Views/SurfaceDetectionReviewView.swift`
- Modify: `Sources/Lumora/Views/WorkspaceView.swift`

**Interfaces:**
- `SurfaceDetectionReviewView.init(image: NSImage, surfaces: [DetectedSurface], onAdd: ([[CGPoint]]) -> Void, onCancel: () -> Void)` — builds `ReviewItem`s from surfaces (label = confidence %, icon = quad vs polygon). Rendering/handles already N-point.
- `WorkspaceView`: `reviewSurfaces: [DetectedSurface]`; `detectSurfaces()` calls `SurfaceDetector.detectSurfaces`.

- [ ] **Step 1: Update the review view init**

In `SurfaceDetectionReviewView.swift`, replace the `quads` property + init:

```swift
    let image: NSImage
    let surfaces: [DetectedSurface]
    let onAdd: ([[CGPoint]]) -> Void
    let onCancel: () -> Void
```

```swift
    init(image: NSImage, surfaces: [DetectedSurface],
         onAdd: @escaping ([[CGPoint]]) -> Void, onCancel: @escaping () -> Void) {
        self.image = image
        self.surfaces = surfaces
        self.onAdd = onAdd
        self.onCancel = onCancel
        _items = State(initialValue: surfaces.map { s in
            ReviewItem(corners: s.polygon, keep: true,
                       label: "\(Int(s.confidence * 100))%",
                       systemImage: s.isQuad ? "rectangle.dashed" : "hexagon")
        })
    }
```

(No other change needed — `ReviewItem.corners` and all rendering/handle code already handle N points.)

- [ ] **Step 2: Update WorkspaceView state + detect call**

In `WorkspaceView.swift`:
- Replace `@State private var reviewQuads: [DetectedQuad] = []` with `@State private var reviewSurfaces: [DetectedSurface] = []`.
- In the `.sheet`, change `quads: reviewQuads` to `surfaces: reviewSurfaces`.
- In `detectSurfaces()`, replace `let quads = SurfaceDetector.detect(in: cg)` and `reviewQuads = quads` with:

```swift
            let detected = SurfaceDetector.detectSurfaces(in: cg)
```
and
```swift
                reviewSurfaces = detected
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: Build complete. (If `DetectedQuad` is now unreferenced in `WorkspaceView`, that's fine.)

- [ ] **Step 4: Commit**

```bash
git add Sources/Lumora/Views/SurfaceDetectionReviewView.swift Sources/Lumora/Views/WorkspaceView.swift
git commit -m "feat: Detect Surfaces uses classical-CV detectSurfaces (quads+polygons)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: End-to-end verification

**Files:**
- Test: `Tests/LumoraTests/DetectSurfacesTests.swift` (add opt-in real-photo overlay)

- [ ] **Step 1: Add an opt-in real-photo overlay for `detectSurfaces`**

Add imports (`import ImageIO`, `import UniformTypeIdentifiers`) and this test to `DetectSurfacesTests`:

```swift
    func testWritesDetectSurfacesDemoWhenRequested() throws {
        guard let folder = ProcessInfo.processInfo.environment["DETECTSURF_DIR"] else {
            throw XCTSkip("set DETECTSURF_DIR")
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        let fm = FileManager.default
        for name in try fm.contentsOfDirectory(atPath: folder).filter({ $0.lowercased().hasSuffix(".jpeg") }).sorted() {
            let path = (folder as NSString).appendingPathComponent(name)
            guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            let surfaces = SurfaceDetector.detectSurfaces(in: cg)
            let W = min(cg.width, 1200), H = Int(Double(W) * Double(cg.height) / Double(cg.width)), fH = CGFloat(H)
            let out = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            out.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
            out.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.4)); out.fill(CGRect(x: 0, y: 0, width: W, height: H))
            let palette = [CGColor(red: 0.2, green: 1, blue: 0.5, alpha: 1), CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 1),
                           CGColor(red: 0.4, green: 0.6, blue: 1, alpha: 1), CGColor(red: 1, green: 0.4, blue: 0.8, alpha: 1),
                           CGColor(red: 1, green: 0.9, blue: 0.3, alpha: 1), CGColor(red: 0.5, green: 1, blue: 1, alpha: 1)]
            for (i, s) in surfaces.enumerated() {
                let d = s.polygon.map { CGPoint(x: $0.x * CGFloat(W), y: fH - $0.y * CGFloat(H)) }
                guard let f = d.first else { continue }
                let c = palette[i % palette.count]
                out.setStrokeColor(c); out.setLineWidth(max(2, CGFloat(W) / 380)); out.setFillColor(c.copy(alpha: 0.16)!)
                out.move(to: f); for p in d.dropFirst() { out.addLine(to: p) }; out.closePath(); out.drawPath(using: .fillStroke)
            }
            let img = out.makeImage()!
            let outURL = URL(fileURLWithPath: (folder as NSString).appendingPathComponent("\((name as NSString).deletingPathExtension)_final.png"))
            let dest = CGImageDestinationCreateWithURL(outURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, img, nil); _ = CGImageDestinationFinalize(dest)
            print("FINAL \(name) surfaces=\(surfaces.count) -> \(outURL.lastPathComponent)")
        }
    }
```

- [ ] **Step 2: Automated end-to-end run**

Run: `DETECTSURF_DIR=/Users/zaks/Downloads/room-images swift test --filter DetectSurfacesTests/testWritesDetectSurfacesDemoWhenRequested`
Expected: PASS; prints per-image surface counts, writes `<name>_final.png`. Eyeball them — should match/beat the Stage-5 `_surfaces.png` (now with region-growing walls added, deduped).

- [ ] **Step 3: Build + launch the packaged app**

Run: `swift test` (full suite green) then `./scripts/make_app.sh` and `open dist/Lumora.app`; confirm the process runs (`pgrep -xl Lumora`). The app builds and launches with the new detector wired.

- [ ] **Step 4: Manual click-through (user or accessibility)**

In the running app: **Detect Surfaces** → accept the disclaimer → pick a `room-images` JPEG → confirm the review sheet shows detected surfaces (quads and polygons) overlaid on the photo, drag a corner, keep a few, **Add** → confirm they become editable surfaces on the canvas rendering the grid effect. (Synthetic clicks into the native file panel/sheet can't be driven headlessly — the automated overlay in Step 2 is the CI-safe proof; this step is the human confirmation.)

- [ ] **Step 5: Commit**

```bash
git add Tests/LumoraTests/DetectSurfacesTests.swift
git commit -m "test(detect): end-to-end detectSurfaces overlay (opt-in)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (Stage 6 slice of the design doc):**
- Wire pipeline into a detect entry point → Task 1 (`detectSurfaces`). ✅
- Drop Vision, keep region-growing as second source → Task 1 (no `objectCandidates`; `regionPlaneCandidates` converted + deduped). ✅
- `addDetectedSurfaces` accepts quad-or-polygon → Task 2. ✅
- Review sheet renders polygons + quads → Task 3 (already N-point; type swap + icon/label). ✅
- Detect Surfaces button uses the new detector → Task 3 (WorkspaceView). ✅
- Verification (unit + real-photo overlay + app launch + manual click-through) → Tasks 1, 4. ✅

**Placeholder scan:** No TBD/TODO; every code step complete; the manual click-through is an explicit human step (native file panel can't be automated), backed by the automated Step-2 overlay. ✅

**Type consistency:** `DetectedSurface` (Stage 5) is produced by `detectSurfaces` (T1), carried as `WorkspaceView.reviewSurfaces` (T3), rendered by `SurfaceDetectionReviewView(surfaces:)` (T3), and its kept `polygon`s flow through `onAdd: [[CGPoint]]` into `addDetectedSurfaces` (T2). `surfaceFromQuad`/`bboxIoU` are internal to T1. Normalized `[0,1]` top-left throughout. ✅

**Scope check:** Integration only — no new CV. Legacy `detect()` + Vision left intact but unused by the app (full removal is a follow-up cleanup). ✅
```

