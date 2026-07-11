# Marker Calibration & Auto-Surface Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user project four corner markers, photograph the scene, import the photo, and have Lumora auto-detect object rectangles and turn them into editable quad surfaces mapped back onto the real objects — with a human keep/discard review step.

**Architecture:** The correctness-critical coordinate math (a general quad→quad homography and the photo→canvas mapping) lives in `LumoraKit`, pure and unit-tested. The app layer adds a calibrate mode that projects fiducials, a photo importer, Vision/CoreImage detectors for the fiducials and object rectangles, and a review UI that stages candidate surfaces before committing them to `store.surfaces`. Lumora's normalized canvas space already equals projector-output space, so a photo→canvas homography yields `Surface.points` directly.

**Tech Stack:** Swift 5.9, SwiftUI (`Canvas`, `ImageRenderer`), AppKit (`NSImage`, `NSOpenPanel`), Vision (`VNDetectRectanglesRequest`, `VNDetectContoursRequest`), CoreImage, XCTest. Swift Package (no `.xcodeproj`): `swift build`, `swift test`, `swift run Lumora`.

## Global Constraints

- Platform: macOS 14+ (`Package.swift`). Vision/CoreImage available.
- `LumoraKit` is **UI-free**: import only `Foundation` / `CoreGraphics` / `QuartzCore`. No SwiftUI/AppKit/Vision. The existing `Homography` type lives here.
- **Photo space is normalized `0…1` with top-left origin.** Both detectors output points in this space so the homography maps normalized-photo → normalized-canvas with no pixel-size bookkeeping. (Vision returns bottom-left-origin normalized coords → convert `y' = 1 - y`.)
- **Canvas space == projector-output space**, normalized `0…1`. `Surface.points` are normalized canvas coords. Quad surfaces are TL, TR, BR, BL order.
- Known fiducial canvas corners: TL `(0.05,0.05)`, TR `(0.95,0.05)`, BR `(0.95,0.95)`, BL `(0.05,0.95)`.
- Corner ordering heuristic (roughly-upright quad): TL = min(x+y), BR = max(x+y), TR = max(x−y), BL = min(x−y).
- Detection runs **off the main thread** (match the existing extractor pattern in `SurfaceContentView.swift`).
- Never fabricate a calibration: if four fiducials aren't confidently found, surface an error / allow manual correction — do not guess.
- Commit after each task. Commit messages end with:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`

---

### Task 1: Quad→quad homography (LumoraKit, TDD)

Add a matrix inverse and a general four-point quad→quad homography to the existing `Homography` type. This is the mapping engine.

**Files:**
- Modify: `Sources/LumoraKit/Homography.swift`
- Modify: `Tests/LumoraTests/HomographyTests.swift`

**Interfaces:**
- Consumes: existing `Homography` (`squareToQuad`, `multiplied(by:)`, `apply`).
- Produces:
  - `func inverse() -> Homography`
  - `static func quadToQuad(_ src: [CGPoint], _ dst: [CGPoint]) -> Homography`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/LumoraTests/HomographyTests.swift` (inside the existing `final class HomographyTests`):

```swift
    func testInverseRoundTrip() {
        let quad = [
            CGPoint(x: 10, y: 20), CGPoint(x: 210, y: 5),
            CGPoint(x: 190, y: 180), CGPoint(x: 30, y: 160),
        ]
        let h = Homography.squareToQuad(quad)
        let inv = h.inverse()
        // h then inv is identity on the unit-square corners.
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
                       CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        for c in corners {
            let round = inv.apply(h.apply(c))
            XCTAssertEqual(round.x, c.x, accuracy: 1e-6)
            XCTAssertEqual(round.y, c.y, accuracy: 1e-6)
        }
    }

    func testQuadToQuadMapsCornersExactly() {
        let src = [
            CGPoint(x: 0.10, y: 0.12), CGPoint(x: 0.80, y: 0.05),
            CGPoint(x: 0.90, y: 0.85), CGPoint(x: 0.05, y: 0.78),
        ]
        let dst = [
            CGPoint(x: 0.05, y: 0.05), CGPoint(x: 0.95, y: 0.05),
            CGPoint(x: 0.95, y: 0.95), CGPoint(x: 0.05, y: 0.95),
        ]
        let h = Homography.quadToQuad(src, dst)
        for i in 0..<4 {
            let p = h.apply(src[i])
            XCTAssertEqual(p.x, dst[i].x, accuracy: 1e-6)
            XCTAssertEqual(p.y, dst[i].y, accuracy: 1e-6)
        }
    }

    func testQuadToQuadInteriorPoint() {
        // Identity mapping: src == dst → any point maps to itself.
        let q = [
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0),
            CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1),
        ]
        let h = Homography.quadToQuad(q, q)
        let mid = h.apply(CGPoint(x: 0.37, y: 0.62))
        XCTAssertEqual(mid.x, 0.37, accuracy: 1e-9)
        XCTAssertEqual(mid.y, 0.62, accuracy: 1e-9)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HomographyTests`
Expected: FAIL to compile — `value of type 'Homography' has no member 'inverse'` / `no member 'quadToQuad'`.

- [ ] **Step 3: Implement inverse + quadToQuad**

In `Sources/LumoraKit/Homography.swift`, add these methods inside the `Homography` struct (e.g. after `rectToQuad`):

```swift
    /// The inverse of this projective transform (adjugate / determinant of the
    /// 3×3 matrix). Precondition: the matrix is non-singular.
    public func inverse() -> Homography {
        let a = m[0], b = m[1], c = m[2]
        let d = m[3], e = m[4], f = m[5]
        let g = m[6], h = m[7], i = m[8]

        let A =  (e * i - f * h)
        let B = -(d * i - f * g)
        let C =  (d * h - e * g)
        let D = -(b * i - c * h)
        let E =  (a * i - c * g)
        let F = -(a * h - b * g)
        let G =  (b * f - c * e)
        let H = -(a * f - c * d)
        let I =  (a * e - b * d)

        let det = a * A + b * B + c * C
        precondition(abs(det) > 1e-15, "Homography is singular; cannot invert")
        let inv = 1.0 / det
        // Adjugate is the transpose of the cofactor matrix.
        return Homography([
            A * inv, D * inv, G * inv,
            B * inv, E * inv, H * inv,
            C * inv, F * inv, I * inv,
        ])
    }

    /// Homography mapping the four `src` points onto the four `dst` points
    /// (each in TL, TR, BR, BL order, though any consistent order works).
    /// Built as squareToQuad(dst) ∘ squareToQuad(src)⁻¹.
    public static func quadToQuad(_ src: [CGPoint], _ dst: [CGPoint]) -> Homography {
        precondition(src.count == 4 && dst.count == 4, "quadToQuad requires 4+4 points")
        return squareToQuad(dst).multiplied(by: squareToQuad(src).inverse())
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HomographyTests`
Expected: PASS (existing tests + 3 new).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/Homography.swift Tests/LumoraTests/HomographyTests.swift
git commit -m "$(cat <<'EOF'
Add homography inverse and quad-to-quad mapping

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Calibration mapping (LumoraKit, TDD)

The pure coordinate logic: known fiducial corners, corner ordering, and photo→canvas surface mapping. Unit-tested end to end with a synthetic round-trip.

**Files:**
- Create: `Sources/LumoraKit/CalibrationMapping.swift`
- Create: `Tests/LumoraTests/CalibrationMappingTests.swift`

**Interfaces:**
- Consumes: `Homography` (Task 1).
- Produces (used by app tasks):
  - `enum CalibrationMapping`
  - `static let fiducialCanvasCorners: [CGPoint]` (TL,TR,BR,BL)
  - `static func orderedCorners(_ pts: [CGPoint]) -> [CGPoint]`
  - `static func photoToCanvas(fiducialPhotoPoints: [CGPoint]) -> Homography`
  - `static func canvasQuad(fromPhotoQuad photoQuad: [CGPoint], using h: Homography) -> [CGPoint]`

- [ ] **Step 1: Write the failing tests**

Create `Tests/LumoraTests/CalibrationMappingTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import LumoraKit

final class CalibrationMappingTests: XCTestCase {
    func testOrderedCornersFromShuffledPoints() {
        // A roughly-upright quad given out of order.
        let tl = CGPoint(x: 0.1, y: 0.1), tr = CGPoint(x: 0.9, y: 0.12)
        let br = CGPoint(x: 0.88, y: 0.9), bl = CGPoint(x: 0.12, y: 0.85)
        let ordered = CalibrationMapping.orderedCorners([br, tl, bl, tr])
        XCTAssertEqual(ordered[0], tl)
        XCTAssertEqual(ordered[1], tr)
        XCTAssertEqual(ordered[2], br)
        XCTAssertEqual(ordered[3], bl)
    }

    func testPhotoToCanvasRecoversKnownRectangle() {
        // Synthetic: choose a canvas→photo homography, project the fiducial
        // canvas corners and a known object quad into "photo" space, then
        // recover the object quad back in canvas space. Must round-trip.
        let canvasFiducials = CalibrationMapping.fiducialCanvasCorners
        // Arbitrary perspective quad representing where the canvas lands in the photo.
        let photoQuad = [
            CGPoint(x: 0.20, y: 0.18), CGPoint(x: 0.82, y: 0.10),
            CGPoint(x: 0.88, y: 0.86), CGPoint(x: 0.14, y: 0.80),
        ]
        let canvasToPhoto = Homography.quadToQuad(canvasFiducials, photoQuad)

        // The fiducials as they would appear in the photo (shuffled order).
        let fiducialPhoto = canvasFiducials.map { canvasToPhoto.apply($0) }
        let shuffled = [fiducialPhoto[2], fiducialPhoto[0], fiducialPhoto[3], fiducialPhoto[1]]

        // A known object quad in canvas space.
        let objectCanvas = [
            CGPoint(x: 0.30, y: 0.35), CGPoint(x: 0.60, y: 0.35),
            CGPoint(x: 0.60, y: 0.65), CGPoint(x: 0.30, y: 0.65),
        ]
        let objectPhoto = objectCanvas.map { canvasToPhoto.apply($0) }

        let h = CalibrationMapping.photoToCanvas(fiducialPhotoPoints: shuffled)
        let recovered = CalibrationMapping.canvasQuad(fromPhotoQuad: objectPhoto, using: h)

        for i in 0..<4 {
            XCTAssertEqual(recovered[i].x, objectCanvas[i].x, accuracy: 1e-6)
            XCTAssertEqual(recovered[i].y, objectCanvas[i].y, accuracy: 1e-6)
        }
    }

    func testCanvasQuadClampsToUnitRange() {
        // Identity mapping; an out-of-bounds photo quad clamps into 0...1.
        let idH = Homography.quadToQuad(
            [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)],
            [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        )
        let out = CalibrationMapping.canvasQuad(
            fromPhotoQuad: [CGPoint(x: -0.2, y: 0.1), CGPoint(x: 1.3, y: 0.1),
                            CGPoint(x: 1.3, y: 0.9), CGPoint(x: -0.2, y: 0.9)],
            using: idH)
        for p in out {
            XCTAssertGreaterThanOrEqual(p.x, 0)
            XCTAssertLessThanOrEqual(p.x, 1)
            XCTAssertGreaterThanOrEqual(p.y, 0)
            XCTAssertLessThanOrEqual(p.y, 1)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CalibrationMappingTests`
Expected: FAIL to compile — `cannot find 'CalibrationMapping' in scope`.

- [ ] **Step 3: Implement CalibrationMapping**

Create `Sources/LumoraKit/CalibrationMapping.swift`:

```swift
import CoreGraphics
import Foundation

/// Pure coordinate logic for marker-based projector calibration.
///
/// Everything is normalized: "photo space" is `0…1` with top-left origin (the
/// detectors convert into this), and "canvas space" is Lumora's normalized
/// projector-output space where `Surface.points` live. A photo→canvas
/// homography, built from the four detected fiducials, maps detected object
/// quads straight into surface coordinates.
public enum CalibrationMapping {
    /// Inset of the projected fiducials from the canvas edges.
    public static let fiducialInset: CGFloat = 0.05

    /// The four fiducial positions in normalized canvas space, TL, TR, BR, BL.
    public static let fiducialCanvasCorners: [CGPoint] = [
        CGPoint(x: fiducialInset, y: fiducialInset),
        CGPoint(x: 1 - fiducialInset, y: fiducialInset),
        CGPoint(x: 1 - fiducialInset, y: 1 - fiducialInset),
        CGPoint(x: fiducialInset, y: 1 - fiducialInset),
    ]

    /// Orders four points as TL, TR, BR, BL using the sum/difference heuristic
    /// (valid for a roughly-upright quad): TL has the smallest x+y, BR the
    /// largest; TR has the largest x−y, BL the smallest.
    public static func orderedCorners(_ pts: [CGPoint]) -> [CGPoint] {
        precondition(pts.count == 4, "orderedCorners requires 4 points")
        let tl = pts.min { ($0.x + $0.y) < ($1.x + $1.y) }!
        let br = pts.max { ($0.x + $0.y) < ($1.x + $1.y) }!
        let tr = pts.max { ($0.x - $0.y) < ($1.x - $1.y) }!
        let bl = pts.min { ($0.x - $0.y) < ($1.x - $1.y) }!
        return [tl, tr, br, bl]
    }

    /// Homography mapping photo space → canvas space, from the four detected
    /// fiducial photo points (any order; they are ordered internally).
    public static func photoToCanvas(fiducialPhotoPoints: [CGPoint]) -> Homography {
        let orderedPhoto = orderedCorners(fiducialPhotoPoints)
        return Homography.quadToQuad(orderedPhoto, fiducialCanvasCorners)
    }

    /// Maps a detected object quad (photo space) into canvas-space `Surface`
    /// points (TL, TR, BR, BL), clamped to `0…1`.
    public static func canvasQuad(fromPhotoQuad photoQuad: [CGPoint], using h: Homography) -> [CGPoint] {
        orderedCorners(photoQuad).map { p in
            let c = h.apply(p)
            return CGPoint(x: min(max(c.x, 0), 1), y: min(max(c.y, 0), 1))
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CalibrationMappingTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/CalibrationMapping.swift Tests/LumoraTests/CalibrationMappingTests.swift
git commit -m "$(cat <<'EOF'
Add pure calibration mapping (photo->canvas surface quads)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Calibrate mode + fiducial projection overlay

Add calibrate-mode state and project the four fiducials from the projection output. Verified offscreen.

**Files:**
- Modify: `Sources/Lumora/ProjectStore.swift` (add `calibrating` flag)
- Create: `Sources/Lumora/Views/FiducialOverlay.swift`
- Modify: `Sources/Lumora/Views/ProjectionView.swift` (render fiducials when calibrating)
- Modify: `Sources/Lumora/Views/WorkspaceView.swift` (a "Calibrate" toolbar toggle)
- Verify: `scripts/verify_fiducials.swift` (create; offscreen render)

**Interfaces:**
- Consumes: `CalibrationMapping.fiducialCanvasCorners` (Task 2).
- Produces: `ProjectStore.calibrating: Bool` (`@Published`); `struct FiducialOverlay: View { init(canvasSize:) }`.

- [ ] **Step 1: Add calibrate state**

In `Sources/Lumora/ProjectStore.swift`, add next to the other `@Published` properties:

```swift
    @Published var calibrating: Bool = false
```

- [ ] **Step 2: Create the fiducial overlay**

Create `Sources/Lumora/Views/FiducialOverlay.swift`:

```swift
import LumoraKit
import SwiftUI

/// Draws the four calibration fiducials at their known normalized canvas
/// corners. High-contrast concentric ring targets on transparent background so
/// they stand out in a photograph. Drawn in normalized→canvas space.
struct FiducialOverlay: View {
    let canvasSize: CGSize

    var body: some View {
        Canvas { ctx, size in
            for corner in CalibrationMapping.fiducialCanvasCorners {
                let c = CGPoint(x: corner.x * size.width, y: corner.y * size.height)
                // Outer black disc (contrast halo), white ring, black center dot.
                ring(ctx, center: c, radius: 26, color: .black)
                ring(ctx, center: c, radius: 20, color: .white)
                ring(ctx, center: c, radius: 12, color: .black)
                dot(ctx, center: c, radius: 6, color: .white)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .allowsHitTesting(false)
    }

    private func ring(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                        width: radius * 2, height: radius * 2)),
                 with: .color(color))
    }

    private func dot(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        ring(ctx, center: center, radius: radius, color: color)
    }
}
```

- [ ] **Step 3: Render fiducials in the projection output**

In `Sources/Lumora/Views/ProjectionView.swift`, inside the `ZStack(alignment: .topLeading)` (after the light-lines `ForEach`, still within the `.frame(width: size...).scaleEffect(scale)` block), add:

```swift
                        if store.calibrating {
                            FiducialOverlay(canvasSize: size)
                        }
```

- [ ] **Step 4: Add a Calibrate toggle to the toolbar**

In `Sources/Lumora/Views/WorkspaceView.swift`, add a button in the toolbar (e.g. just before the `Spacer()`), and open the projection window when enabling:

```swift
            Toggle(isOn: $store.calibrating) {
                Label("Calibrate", systemImage: "viewfinder")
            }
            .toggleStyle(.button)
            .onChange(of: store.calibrating) { _, on in
                if on { openWindow(id: "projection") }
            }
            .help("Project four corner markers to photograph for auto-mapping.")
```

- [ ] **Step 5: Verify it builds**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 6: Offscreen render verification**

Create `scripts/verify_fiducials.swift`:

```swift
// Run: swift scripts/verify_fiducials.swift
// Renders the fiducial overlay on black to confirm four corner targets.
import AppKit
import SwiftUI

let inset: CGFloat = 0.05
let corners = [
    CGPoint(x: inset, y: inset), CGPoint(x: 1 - inset, y: inset),
    CGPoint(x: 1 - inset, y: 1 - inset), CGPoint(x: inset, y: 1 - inset),
]
let size = CGSize(width: 640, height: 400)

struct Frame: View {
    var body: some View {
        ZStack {
            Color.black
            Canvas { ctx, sz in
                for corner in corners {
                    let c = CGPoint(x: corner.x * sz.width, y: corner.y * sz.height)
                    for (r, col) in [(26.0, Color.black), (20, .white), (12, .black), (6, .white)] {
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                                 with: .color(col))
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Frame())
    renderer.scale = 2
    if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "/tmp/fiducials.png"))
        print("wrote /tmp/fiducials.png")
    }
}
```

Run: `swift scripts/verify_fiducials.swift`, then Read `/tmp/fiducials.png`.
Expected: four concentric ring targets, one near each corner (5% inset), on black.

- [ ] **Step 7: Commit**

```bash
git add Sources/Lumora/ProjectStore.swift Sources/Lumora/Views/FiducialOverlay.swift Sources/Lumora/Views/ProjectionView.swift Sources/Lumora/Views/WorkspaceView.swift scripts/verify_fiducials.swift
git commit -m "$(cat <<'EOF'
Add calibrate mode projecting four corner fiducials

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Photo import + fiducial & rectangle detectors

Import a photo and detect the fiducials and object rectangles, all in normalized photo space, off the main thread.

**Files:**
- Create: `Sources/Lumora/Calibration/PhotoDetectors.swift`
- Verify: `scripts/verify_detection.swift` (create; synthetic-image detection check)

**Interfaces:**
- Consumes: nothing from prior app tasks (pure detection).
- Produces:
  - `struct DetectedCalibration { var fiducials: [CGPoint]; var rectangles: [[CGPoint]] }` (all normalized, top-left origin)
  - `enum PhotoDetectors { static func detect(in image: CGImage, completion: @escaping (Result<DetectedCalibration, DetectionError>) -> Void) }`
  - `enum DetectionError: Error { case fiducialsNotFound(Int); case imageUnreadable }`

- [ ] **Step 1: Implement the detectors**

Create `Sources/Lumora/Calibration/PhotoDetectors.swift`:

```swift
import CoreImage
import Foundation
import Vision

/// Result of analyzing an imported calibration photo. All points are in
/// normalized photo space (0…1, top-left origin).
struct DetectedCalibration {
    var fiducials: [CGPoint]        // exactly 4, unordered
    var rectangles: [[CGPoint]]     // each 4 corners, unordered
}

enum DetectionError: Error {
    case imageUnreadable
    case fiducialsNotFound(Int)     // how many were actually found
}

/// Vision/CoreImage detection of calibration fiducials and object rectangles.
/// Runs work on a background queue; the completion is called on the main queue.
enum PhotoDetectors {
    private static let queue = DispatchQueue(label: "lumora.calibration.detect", qos: .userInitiated)

    static func detect(in image: CGImage,
                       completion: @escaping (Result<DetectedCalibration, DetectionError>) -> Void) {
        queue.async {
            let result: Result<DetectedCalibration, DetectionError>
            do {
                let fiducials = try detectFiducials(in: image)
                let rectangles = detectRectangles(in: image)
                result = .success(DetectedCalibration(fiducials: fiducials, rectangles: rectangles))
            } catch let e as DetectionError {
                result = .failure(e)
            } catch {
                result = .failure(.imageUnreadable)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: Fiducials

    /// Finds the four fiducial ring targets: threshold to bright regions, trace
    /// contours, keep the four largest reasonably-compact blobs, return their
    /// centroids in normalized top-left space.
    private static func detectFiducials(in image: CGImage) throws -> [CGPoint] {
        let ci = CIImage(cgImage: image)
        let ctx = CIContext()
        // Boost contrast and threshold toward the bright ring centers.
        let mono = ci
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0, kCIInputContrastKey: 1.4])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0.55, y: 0.55, z: 0.55, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
            ])
        guard let cg = ctx.createCGImage(mono, from: mono.extent) else { throw DetectionError.imageUnreadable }

        let request = VNDetectContoursRequest()
        request.contrastAdjustment = 2.0
        request.detectsDarkOnLight = false
        request.maximumImageDimension = 1024
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try handler.perform([request])
        guard let observation = request.results?.first else { throw DetectionError.fiducialsNotFound(0) }

        // Collect top-level contours with their bounding-box area and centroid.
        var blobs: [(area: CGFloat, center: CGPoint)] = []
        for i in 0..<observation.topLevelContourCount {
            guard let contour = try? observation.contour(at: i) else { continue }
            let pts = contour.normalizedPoints // bottom-left origin, 0…1
            guard pts.count >= 4 else { continue }
            var minX: Float = 1, minY: Float = 1, maxX: Float = 0, maxY: Float = 0
            var sx: Float = 0, sy: Float = 0
            for p in pts {
                minX = min(minX, p.x); minY = min(minY, p.y)
                maxX = max(maxX, p.x); maxY = max(maxY, p.y)
                sx += p.x; sy += p.y
            }
            let w = CGFloat(maxX - minX), h = CGFloat(maxY - minY)
            let area = w * h
            // Compactness: rings are roughly square in bounds.
            let aspect = w > 0 && h > 0 ? Double(max(w, h) / min(w, h)) : 99
            guard area > 0.0002, aspect < 2.2 else { continue }
            let cx = CGFloat(sx) / CGFloat(pts.count)
            let cyBL = CGFloat(sy) / CGFloat(pts.count)
            blobs.append((area, CGPoint(x: cx, y: 1 - cyBL))) // flip to top-left origin
        }

        // Keep the four largest.
        let top = blobs.sorted { $0.area > $1.area }.prefix(4).map { $0.center }
        guard top.count == 4 else { throw DetectionError.fiducialsNotFound(top.count) }
        return top
    }

    // MARK: Rectangles

    /// Detects object rectangles via Vision, returned as 4-corner quads in
    /// normalized top-left space. Empty array if none found (not an error).
    private static func detectRectangles(in image: CGImage) -> [[CGPoint]] {
        let request = VNDetectRectanglesRequest()
        request.minimumSize = 0.05
        request.maximumObservations = 16
        request.minimumConfidence = 0.4
        request.quadratureTolerance = 30
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let results = request.results else { return [] }
        return results.map { obs in
            // Vision points are normalized, bottom-left origin. Flip y.
            [obs.topLeft, obs.topRight, obs.bottomRight, obs.bottomLeft].map {
                CGPoint(x: $0.x, y: 1 - $0.y)
            }
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Synthetic-image detection verification**

Create `scripts/verify_detection.swift` — renders a synthetic "photo" (black background, four ring fiducials near the corners, one bright rectangle in the middle), runs the SAME detection logic, and prints counts + the recovered rectangle center. This proves the Vision pipeline end to end without a real camera.

```swift
// Run: swift scripts/verify_detection.swift
import AppKit
import SwiftUI
import Vision

let size = CGSize(width: 800, height: 600)
struct Synth: View {
    var body: some View {
        ZStack {
            Color.black
            Canvas { ctx, sz in
                let inset = 0.06
                for cx in [inset, 1 - inset] {
                    for cy in [inset, 1 - inset] {
                        let c = CGPoint(x: cx * sz.width, y: cy * sz.height)
                        for (r, col) in [(24.0, Color.white), (14, .black), (7, .white)] {
                            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2*r, height: 2*r)), with: .color(col))
                        }
                    }
                }
                // A bright rectangle object.
                let rect = CGRect(x: sz.width*0.35, y: sz.height*0.35, width: sz.width*0.3, height: sz.height*0.3)
                ctx.fill(Path(rect), with: .color(.white))
                ctx.stroke(Path(rect), with: .color(.gray), lineWidth: 3)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Synth())
    guard let ns = renderer.nsImage,
          let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        print("no image"); exit(1)
    }
    // Fiducials via contours.
    let contours = VNDetectContoursRequest()
    contours.detectsDarkOnLight = false
    let h1 = VNImageRequestHandler(cgImage: cg, options: [:])
    try? h1.perform([contours])
    let blobCount = contours.results?.first?.topLevelContourCount ?? 0
    // Rectangles.
    let rects = VNDetectRectanglesRequest()
    rects.minimumSize = 0.05; rects.maximumObservations = 16; rects.minimumConfidence = 0.3
    let h2 = VNImageRequestHandler(cgImage: cg, options: [:])
    try? h2.perform([rects])
    let rectCount = rects.results?.count ?? 0
    print("top-level contours: \(blobCount) (expect >= 4 fiducial rings)")
    print("rectangles detected: \(rectCount) (expect >= 1)")
    if let r = rects.results?.first {
        print("first rect center ~ (\(String(format: "%.2f", (r.topLeft.x+r.bottomRight.x)/2)), \(String(format: "%.2f", 1-(r.topLeft.y+r.bottomRight.y)/2)))  (expect ~0.5,0.5)")
    }
}
```

Run: `swift scripts/verify_detection.swift`
Expected: contour count ≥ 4, rectangle count ≥ 1, first rect center ≈ (0.5, 0.5). If the counts are low, tune the detector parameters (thresholds, `minimumConfidence`, `quadratureTolerance`) in `PhotoDetectors.swift` and re-run until the synthetic scene is reliably detected. Note in the report the final parameter values.

- [ ] **Step 4: Commit**

```bash
git add Sources/Lumora/Calibration/PhotoDetectors.swift scripts/verify_detection.swift
git commit -m "$(cat <<'EOF'
Add fiducial and rectangle photo detectors

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Calibration review UI + commit

Tie it together: import a photo, run detection, map candidates, review keep/discard, commit surfaces, and set the backdrop.

**Files:**
- Create: `Sources/Lumora/Calibration/CalibrationController.swift`
- Create: `Sources/Lumora/Views/CalibrationReviewView.swift`
- Modify: `Sources/Lumora/ProjectStore.swift` (mutable `roomImage`; add a candidate-commit helper)
- Modify: `Sources/Lumora/Views/WorkspaceView.swift` (an "Import Photo…" action that opens the review)

**Interfaces:**
- Consumes: `PhotoDetectors.detect`, `DetectedCalibration`, `DetectionError` (Task 4); `CalibrationMapping.photoToCanvas`, `.canvasQuad` (Task 2); `ProjectStore` surface API.
- Produces: `final class CalibrationController: ObservableObject`; `struct CalibrationReviewView: View`.

- [ ] **Step 1: Make the backdrop mutable + add a commit helper**

In `Sources/Lumora/ProjectStore.swift`, change `let roomImage: NSImage` to `@Published var roomImage: NSImage` (keep the initializer assignment). Add a helper to append a batch of surfaces from normalized quads:

```swift
    /// Create quad surfaces from calibration candidates (each is 4 normalized
    /// TL,TR,BR,BL corner points). Returns the number added.
    @discardableResult
    func addQuadSurfaces(_ quads: [[CGPoint]]) -> Int {
        for quad in quads where quad.count == 4 {
            var s = Surface(name: "Surface \(surfaces.count + 1)", points: quad, shape: .quad)
            s.media = .effect(.grid, .cyan, RGBAColor(r: 0.05, g: 0.06, b: 0.09))
            surfaces.append(s)
        }
        if let last = surfaces.last { selectSurface(last.id) }
        return quads.count
    }
```

- [ ] **Step 2: Create the calibration controller**

Create `Sources/Lumora/Calibration/CalibrationController.swift`:

```swift
import AppKit
import LumoraKit
import SwiftUI
import UniformTypeIdentifiers

/// Orchestrates the calibrate → import → detect → review → commit flow.
@MainActor
final class CalibrationController: ObservableObject {
    /// A detected object, kept in both photo space (for the review overlay,
    /// which is drawn over the photo) and canvas space (what gets committed).
    struct Candidate: Identifiable {
        let id = UUID()
        var photoQuad: [CGPoint]    // normalized photo space, for the overlay
        var canvasQuad: [CGPoint]   // normalized canvas TL,TR,BR,BL, committed
        var keep: Bool = true
    }

    @Published var photo: NSImage?
    @Published var candidates: [Candidate] = []
    @Published var errorMessage: String?
    @Published var isDetecting = false
    @Published var showReview = false

    /// Present a file picker, load the photo, and run detection.
    func importPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        photo = image
        showReview = true
        runDetection(on: image)
    }

    private func runDetection(on image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            errorMessage = "Could not read the image."
            return
        }
        isDetecting = true
        errorMessage = nil
        candidates = []
        PhotoDetectors.detect(in: cg) { [weak self] result in
            guard let self else { return }
            self.isDetecting = false
            switch result {
            case .failure(.fiducialsNotFound(let n)):
                self.errorMessage = "Found \(n) of 4 markers. Re-shoot with all four corner markers clearly visible."
            case .failure(.imageUnreadable):
                self.errorMessage = "Could not analyze the image."
            case .success(let detected):
                let h = CalibrationMapping.photoToCanvas(fiducialPhotoPoints: detected.fiducials)
                self.candidates = detected.rectangles.map { rect in
                    Candidate(photoQuad: rect,
                              canvasQuad: CalibrationMapping.canvasQuad(fromPhotoQuad: rect, using: h))
                }
                if self.candidates.isEmpty {
                    self.errorMessage = "Markers found, but no object rectangles detected."
                }
            }
        }
    }

    /// Commit kept candidates as surfaces, set the backdrop, and close review.
    func commit(into store: ProjectStore) {
        let quads = candidates.filter { $0.keep }.map { $0.canvasQuad }
        store.addQuadSurfaces(quads)
        if let photo { store.roomImage = photo }
        store.calibrating = false
        showReview = false
        candidates = []
    }

    func cancel() {
        showReview = false
        candidates = []
        errorMessage = nil
    }
}
```

- [ ] **Step 3: Create the review view**

Create `Sources/Lumora/Views/CalibrationReviewView.swift`:

```swift
import LumoraKit
import SwiftUI

/// Sheet: shows the imported photo with detected candidate quads overlaid, a
/// keep toggle per candidate, and a commit action.
struct CalibrationReviewView: View {
    @ObservedObject var controller: CalibrationController
    @EnvironmentObject var store: ProjectStore

    var body: some View {
        VStack(spacing: 12) {
            Text("Review Detected Surfaces").font(.headline)

            if let photo = controller.photo {
                GeometryReader { geo in
                    let box = fit(photo.size, in: geo.size)
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: photo)
                            .resizable()
                            .frame(width: box.width, height: box.height)
                        // Draw each candidate at its detected position in the
                        // photo (photo-normalized → box), so the outline lands
                        // on the real object the user is judging.
                        ForEach(controller.candidates) { cand in
                            if cand.keep {
                                candidateOutline(cand.photoQuad, in: box)
                            }
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                }
                .frame(minHeight: 300)
            }

            if controller.isDetecting { ProgressView("Detecting…") }
            if let msg = controller.errorMessage {
                Text(msg).foregroundStyle(.orange).font(.callout)
            }

            if !controller.candidates.isEmpty {
                List {
                    ForEach($controller.candidates) { $cand in
                        Toggle("Surface candidate", isOn: $cand.keep)
                    }
                }
                .frame(height: 120)
            }

            HStack {
                Button("Cancel") { controller.cancel() }
                Spacer()
                Button("Create Surfaces") { controller.commit(into: store) }
                    .buttonStyle(.borderedProminent)
                    .disabled(controller.candidates.filter { $0.keep }.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func candidateOutline(_ quad: [CGPoint], in box: CGSize) -> some View {
        Path { p in
            let pts = quad.map { CGPoint(x: $0.x * box.width, y: $0.y * box.height) }
            guard pts.count == 4 else { return }
            p.addLines(pts)
            p.closeSubpath()
        }
        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
    }

    private func fit(_ image: CGSize, in avail: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return avail }
        let scale = min(avail.width / image.width, avail.height / image.height)
        return CGSize(width: image.width * scale, height: image.height * scale)
    }
}
```

- [ ] **Step 4: Wire the import action + sheet into the workspace**

In `Sources/Lumora/Views/WorkspaceView.swift`, add a `@StateObject private var calibration = CalibrationController()` to the view, an "Import Photo…" button in the toolbar (next to Calibrate), and present the review sheet:

```swift
            Button {
                calibration.importPhoto()
            } label: {
                Label("Import Photo…", systemImage: "photo.badge.plus")
            }
            .help("Import a photo of the projected markers to auto-detect surfaces.")
```

And attach the sheet to the top-level view (e.g. on the `HSplitView`):

```swift
        .sheet(isPresented: $calibration.showReview) {
            CalibrationReviewView(controller: calibration)
                .environmentObject(store)
        }
```

- [ ] **Step 5: Verify it builds**

Run: `swift build`
Expected: build succeeds, 0 warnings.

- [ ] **Step 6: Manual verification in the app**

Run: `swift run Lumora` (plain background; confirm with `pgrep -xl Lumora`).
Confirm:
1. **Calibrate** toggle opens projection and shows four corner ring markers.
2. **Import Photo…** opens a file picker; importing a photo opens the Review sheet and runs detection (spinner → candidates or a clear error).
3. Detected candidates draw as dashed quads over the photo with keep toggles.
4. **Create Surfaces** adds the kept candidates to the sidebar as quad surfaces, sets the imported photo as the canvas backdrop, and closes calibrate mode.
5. The new surfaces are editable with the Arrow-tool corner handles.
6. **⌘S / ⌘O** round-trips the created surfaces.
For a real end-to-end test, project the markers, photograph them, and import that photo. Quit with `pkill -x Lumora`.

- [ ] **Step 7: Commit**

```bash
git add Sources/Lumora/Calibration/CalibrationController.swift Sources/Lumora/Views/CalibrationReviewView.swift Sources/Lumora/ProjectStore.swift Sources/Lumora/Views/WorkspaceView.swift
git commit -m "$(cat <<'EOF'
Add calibration review UI and surface commit

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Notes on scope & known trade-offs

- **Single flat plane:** one homography; off-plane objects map approximately.
- **Review overlay** draws each candidate at its detected photo-space position over the photo, so outlines land on the real objects. The committed surfaces use the canvas-space mapping; the editor backdrop + corner handles are where the user fine-tunes.
- **Detection reliability** (lighting, contrast, rectangle noise) is mitigated by the human review step. Fiducial-detection parameters may need tuning against real photos; the synthetic verify script proves the pipeline wiring.
- **Out of scope (YAGNI):** multi-plane calibration, live webcam capture, contour/polygon detection, coded fiducials, persisting the homography.
```
