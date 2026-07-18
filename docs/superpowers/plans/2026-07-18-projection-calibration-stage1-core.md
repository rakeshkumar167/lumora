# Projection Calibration — Stage 1: Marker Detection + Rectify (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The pure-Swift calibration core: shared pattern constants, a detector that finds four projected magenta corner markers in an uploaded photo, and a perspective rectifier that warps the photo to the projector rectangle.

**Architecture:** `CalibrationPattern` (shared constants) + `CalibrationMarkerDetector` (hue+brightness mask → connected-component blobs → 4 corner extremes) + `PerspectiveRectifier` (CoreImage `CIPerspectiveCorrection`) under `Sources/LumoraKit/SurfaceDetection/`. Reuses `ImagePreprocessor.rgb` and `ConnectedComponents`.

**Tech Stack:** Swift, XCTest, CoreGraphics, CoreImage. Target: `LumoraKit`; tests: `LumoraTests`.

## Global Constraints

- **Pure Swift** in LumoraKit; CoreImage for the perspective warp is allowed (system framework, no third-party dep).
- Coordinates: detector returns normalized `[0,1]` top-left corners ordered TL,TR,BR,BL.
- **CoreImage uses a bottom-left origin** — the rectifier must y-flip; guard with an asymmetric-fixture test (per the raster-flip lesson from earlier stages).
- `PerspectiveRectifier` derives the output aspect from the corner quad (no explicit aspect argument — the markers are the projector rectangle, so the rectified aspect already matches it).
- All new types `public`; `swift test` stays green (currently 168) and grows.

---

## File Structure

- `Sources/LumoraKit/SurfaceDetection/CalibrationPattern.swift` (create) — shared constants.
- `Sources/LumoraKit/SurfaceDetection/CalibrationMarkerDetector.swift` (create).
- `Sources/LumoraKit/SurfaceDetection/PerspectiveRectifier.swift` (create).
- `Tests/LumoraTests/CalibrationMarkerDetectorTests.swift` (create)
- `Tests/LumoraTests/PerspectiveRectifierTests.swift` (create)

---

### Task 1: `CalibrationPattern` + `CalibrationMarkerDetector`

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CalibrationPattern.swift`
- Create: `Sources/LumoraKit/SurfaceDetection/CalibrationMarkerDetector.swift`
- Test: `Tests/LumoraTests/CalibrationMarkerDetectorTests.swift`

**Interfaces:**
- Produces:
  - `enum CalibrationPattern { static let markerColor: RGBAColor; static let markerInsetFraction: Double; static let markerRadiusFraction: Double; static let boundaryInsetFraction: Double }` — shared by the projected view (Stage 2) and the detector.
  - `enum CalibrationMarkerDetector { struct Options { var workingWidth: Int; var minLuma: Double; var minBlobAreaFraction: Double }; static func detectCorners(in image: CGImage, options: Options = .init()) -> [CGPoint]? }` — returns 4 normalized corners ordered TL,TR,BR,BL, or `nil` if fewer than 4 magenta blobs are found.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/CalibrationMarkerDetectorTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class CalibrationMarkerDetectorTests: XCTestCase {
    /// A scene (mid-gray + a bright white distractor rectangle) with four magenta
    /// discs at the given normalized centers.
    private func sceneWithMarkers(_ centers: [(Double, Double)], w: Int = 400, h: Int = 300) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.4, green: 0.42, blue: 0.4, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Bright white distractor — would fool a brightness-only detector.
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1)); ctx.fill(CGRect(x: Double(w) * 0.45, y: Double(h) * 0.45, width: 40, height: 30))
        let m = CalibrationPattern.markerColor
        ctx.setFillColor(CGColor(red: m.r, green: m.g, blue: m.b, alpha: 1))
        let r = Double(min(w, h)) * CalibrationPattern.markerRadiusFraction
        for (nx, ny) in centers {
            // CGContext y-up; place discs so top-left-origin normalized maps correctly.
            let cx = nx * Double(w), cy = (1 - ny) * Double(h)
            ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        }
        return ctx.makeImage()!
    }

    func testFindsFourCornersOrdered() {
        let img = sceneWithMarkers([(0.1, 0.1), (0.9, 0.1), (0.9, 0.9), (0.1, 0.9)])
        let corners = CalibrationMarkerDetector.detectCorners(in: img)
        XCTAssertNotNil(corners)
        guard let c = corners else { return }
        XCTAssertEqual(c.count, 4)
        XCTAssertEqual(Double(c[0].x), 0.1, accuracy: 0.05); XCTAssertEqual(Double(c[0].y), 0.1, accuracy: 0.05) // TL
        XCTAssertEqual(Double(c[1].x), 0.9, accuracy: 0.05); XCTAssertEqual(Double(c[1].y), 0.1, accuracy: 0.05) // TR
        XCTAssertEqual(Double(c[2].x), 0.9, accuracy: 0.05); XCTAssertEqual(Double(c[2].y), 0.9, accuracy: 0.05) // BR
        XCTAssertEqual(Double(c[3].x), 0.1, accuracy: 0.05); XCTAssertEqual(Double(c[3].y), 0.9, accuracy: 0.05) // BL
    }

    func testPerspectiveMarkersStillOrderedCorrectly() {
        // Trapezoid (near corners pulled in at the top) — still TL,TR,BR,BL.
        let img = sceneWithMarkers([(0.25, 0.15), (0.75, 0.15), (0.92, 0.85), (0.08, 0.85)])
        let c = CalibrationMarkerDetector.detectCorners(in: img)
        XCTAssertNotNil(c)
        guard let c = c else { return }
        XCTAssertLessThan(Double(c[0].x), 0.5); XCTAssertLessThan(Double(c[0].y), 0.5)   // TL upper-left
        XCTAssertGreaterThan(Double(c[2].x), 0.5); XCTAssertGreaterThan(Double(c[2].y), 0.5) // BR lower-right
    }

    func testReturnsNilWhenNoMarkers() {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        XCTAssertNil(CalibrationMarkerDetector.detectCorners(in: ctx.makeImage()!))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CalibrationMarkerDetectorTests`
Expected: FAIL — `CalibrationPattern` / `CalibrationMarkerDetector` not found.

- [ ] **Step 3: Implement `CalibrationPattern`**

Create `Sources/LumoraKit/SurfaceDetection/CalibrationPattern.swift`:

```swift
import Foundation

/// Shared geometry/color for the projected calibration pattern — used by both
/// the projected SwiftUI view (app) and the marker detector so they agree.
public enum CalibrationPattern {
    /// Magenta — a saturated hue rarely present in rooms.
    public static let markerColor = RGBAColor(r: 0.92, g: 0.20, b: 0.62)
    /// Corner-marker center inset from each edge, as a fraction of the frame.
    public static let markerInsetFraction: Double = 0.08
    /// Marker disc radius, as a fraction of the smaller frame dimension.
    public static let markerRadiusFraction: Double = 0.045
    /// Glow-boundary inset from the edges, as a fraction of the frame.
    public static let boundaryInsetFraction: Double = 0.04
}
```

- [ ] **Step 4: Implement `CalibrationMarkerDetector`**

Create `Sources/LumoraKit/SurfaceDetection/CalibrationMarkerDetector.swift`:

```swift
import CoreGraphics
import Foundation

/// Locate the four projected magenta corner markers in an uploaded photo.
public enum CalibrationMarkerDetector {
    public struct Options {
        public var workingWidth: Int
        public var minLuma: Double
        public var minBlobAreaFraction: Double
        public init(workingWidth: Int = 900, minLuma: Double = 0.2, minBlobAreaFraction: Double = 0.0002) {
            self.workingWidth = workingWidth
            self.minLuma = minLuma
            self.minBlobAreaFraction = minBlobAreaFraction
        }
    }

    public static func detectCorners(in image: CGImage, options: Options = .init()) -> [CGPoint]? {
        let rgb = ImagePreprocessor.rgb(from: image, maxDimension: options.workingWidth)
        let w = rgb.width, h = rgb.height

        // Magenta mask: R and B high, clearly above G (rejects white/gray/green/red/blue).
        var mask = [Bool](repeating: false, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let c = rgb.color(at: x, y)
                let luma = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
                if c.r > 0.4, c.b > 0.25, (c.r + c.b - 2 * c.g) > 0.3, luma > options.minLuma {
                    mask[y * w + x] = true
                }
            }
        }

        let field = ConnectedComponents.label(mask, width: w, height: h)
        if field.count < 4 { return nil }

        // Per-label centroid + area.
        var sx = [Double](repeating: 0, count: field.count + 1)
        var sy = [Double](repeating: 0, count: field.count + 1)
        var cnt = [Int](repeating: 0, count: field.count + 1)
        for y in 0..<h {
            for x in 0..<w {
                let l = field.labels[y * w + x]
                if l > 0 { sx[l] += Double(x); sy[l] += Double(y); cnt[l] += 1 }
            }
        }
        let minArea = Double(w * h) * options.minBlobAreaFraction
        var centers: [CGPoint] = []
        for l in 1...field.count where Double(cnt[l]) >= minArea {
            centers.append(CGPoint(x: sx[l] / Double(cnt[l]), y: sy[l] / Double(cnt[l])))
        }
        if centers.count < 4 { return nil }

        // Corner blobs by extremes (top-left origin).
        func pick(_ key: (CGPoint) -> Double, _ maximize: Bool) -> CGPoint {
            maximize ? centers.max { key($0) < key($1) }! : centers.min { key($0) < key($1) }!
        }
        let tl = pick({ Double($0.x + $0.y) }, false)
        let br = pick({ Double($0.x + $0.y) }, true)
        let tr = pick({ Double($0.x - $0.y) }, true)
        let bl = pick({ Double($0.x - $0.y) }, false)

        let ordered = [tl, tr, br, bl]
        // Require four distinct corner blobs.
        if Set(ordered.map { "\($0.x),\($0.y)" }).count < 4 { return nil }

        return ordered.map { CGPoint(x: $0.x / CGFloat(w), y: $0.y / CGFloat(h)) }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter CalibrationMarkerDetectorTests`
Expected: PASS (3 tests). If a real marker's mask is empty, loosen the magenta inequality (`> 0.3` → `> 0.2`); if the white distractor leaks in, tighten it.

- [ ] **Step 6: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CalibrationPattern.swift \
        Sources/LumoraKit/SurfaceDetection/CalibrationMarkerDetector.swift \
        Tests/LumoraTests/CalibrationMarkerDetectorTests.swift
git commit -m "feat(detect): calibration marker detector (magenta corner blobs)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `PerspectiveRectifier`

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/PerspectiveRectifier.swift`
- Test: `Tests/LumoraTests/PerspectiveRectifierTests.swift`

**Interfaces:**
- Produces: `enum PerspectiveRectifier { static func rectify(_ image: CGImage, corners: [CGPoint]) -> CGImage? }` — `corners` normalized `[0,1]` top-left, TL,TR,BR,BL; warps so those corners become a rectangle via `CIPerspectiveCorrection`; `nil` if `corners.count != 4` or rendering fails.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/PerspectiveRectifierTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class PerspectiveRectifierTests: XCTestCase {
    /// Top-left quadrant red, rest black — asymmetric, catches flips.
    private func asymmetric(_ w: Int = 120, _ h: Int = 100) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        // Top-left quadrant (top-left origin) → CGContext y-up bottom is y=0, so top half is y in [h/2, h].
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: h / 2, width: w / 2, height: h / 2))
        return ctx.makeImage()!
    }

    func testFullFrameCornersPreserveOrientation() {
        let img = asymmetric()
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        let out = PerspectiveRectifier.rectify(img, corners: corners)
        XCTAssertNotNil(out)
        guard let out = out else { return }
        XCTAssertGreaterThan(out.width, 0); XCTAssertGreaterThan(out.height, 0)
        // Sample the rectified image: top-left stays red, bottom-right stays black.
        let rgb = ImagePreprocessor.rgb(from: out, maxDimension: 200)
        let tl = rgb.color(at: rgb.width / 8, rgb.height / 8)
        let br = rgb.color(at: rgb.width * 7 / 8, rgb.height * 7 / 8)
        XCTAssertGreaterThan(tl.r, 0.6); XCTAssertLessThan(tl.g, 0.3)   // red, not flipped
        XCTAssertLessThan(br.r, 0.3)                                    // black corner
    }

    func testWrongCornerCountReturnsNil() {
        XCTAssertNil(PerspectiveRectifier.rectify(asymmetric(), corners: [CGPoint(x: 0, y: 0)]))
    }

    func testRectifiesInnerQuadToFullFrame() {
        // Corners of an inner sub-rectangle → output is roughly that crop, upright.
        let img = asymmetric(200, 200)
        let corners = [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.6, y: 0.1),
                       CGPoint(x: 0.6, y: 0.6), CGPoint(x: 0.1, y: 0.6)]
        let out = PerspectiveRectifier.rectify(img, corners: corners)
        XCTAssertNotNil(out)
        // The inner region spans the red/black boundary → output has both.
        if let out = out {
            let rgb = ImagePreprocessor.rgb(from: out, maxDimension: 200)
            let tl = rgb.color(at: rgb.width / 8, rgb.height / 8)
            XCTAssertGreaterThan(tl.r, 0.5, "inner top-left is inside the red quadrant")
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PerspectiveRectifierTests`
Expected: FAIL — `PerspectiveRectifier` not found.

- [ ] **Step 3: Implement `PerspectiveRectifier`**

Create `Sources/LumoraKit/SurfaceDetection/PerspectiveRectifier.swift`:

```swift
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Perspective-rectify a photo so four corner points map to a rectangle, via
/// CoreImage's CIPerspectiveCorrection. The output aspect is derived from the
/// corner quad (which is the projector rectangle as captured).
public enum PerspectiveRectifier {
    public static func rectify(_ image: CGImage, corners: [CGPoint]) -> CGImage? {
        guard corners.count == 4 else { return nil }
        let ci = CIImage(cgImage: image)
        let W = CGFloat(image.width), H = CGFloat(image.height)
        // Normalized top-left → CoreImage pixel coords (bottom-left origin: flip y).
        func p(_ c: CGPoint) -> CGPoint { CGPoint(x: c.x * W, y: (1 - c.y) * H) }

        let f = CIFilter.perspectiveCorrection()
        f.inputImage = ci
        f.topLeft = p(corners[0])
        f.topRight = p(corners[1])
        f.bottomRight = p(corners[2])
        f.bottomLeft = p(corners[3])
        f.crop = true
        guard let output = f.outputImage else { return nil }

        let ctx = CIContext(options: nil)
        return ctx.createCGImage(output, from: output.extent)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PerspectiveRectifierTests`
Expected: PASS (3 tests). If orientation is inverted (top-left samples black), the y-flip is wrong — recheck `p()`. If `outputImage` is nil, drop `f.crop` (older SDKs).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS — ~174 tests, 0 failures (6 skipped).

- [ ] **Step 6: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/PerspectiveRectifier.swift \
        Tests/LumoraTests/PerspectiveRectifierTests.swift
git commit -m "feat(detect): PerspectiveRectifier (CIPerspectiveCorrection)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (Stage 1 slice):**
- Shared calibration constants → Task 1 (`CalibrationPattern`). ✅
- Marker detection by hue+brightness → connected components → 4 corner extremes → Task 1. ✅
- Perspective-rectify via CIPerspectiveCorrection, y-flipped → Task 2. ✅
- Aspect derived from the quad (no explicit aspect arg) → Task 2 (documented deviation from the spec's `aspect` parameter). ✅
- Deterministic, unit-tested with synthetic fixtures incl. an asymmetric flip guard → Tasks 1–2. ✅

**Placeholder scan:** No TBD/TODO; complete code in every step; notes are concrete tuning guidance. ✅

**Type consistency:** `CalibrationPattern.markerColor`/`markerRadiusFraction` used by the detector test and (Stage 2) the projected view. `CalibrationMarkerDetector.detectCorners -> [CGPoint]?` feeds `PerspectiveRectifier.rectify(_:corners:)`; both use normalized `[0,1]` top-left corners ordered TL,TR,BR,BL. Reuses `ImagePreprocessor.rgb`, `ConnectedComponents`. ✅

**Scope check:** Calibration core only. The projected `CalibrationPatternView`, `ProjectStore.calibrating`, and the `WorkspaceView` flow are Stage 2. ✅
```

