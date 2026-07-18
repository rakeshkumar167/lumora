# Projection Calibration — Stage 2: App Wiring (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the Stage-1 calibration core into the app: a projected calibration pattern, a `calibrating` flag, and a Detect Surfaces flow that projects the pattern, takes the uploaded photo, finds the markers, rectifies, then detects — with a no-markers fallback.

**Architecture:** `CalibrationPatternView` (glow boundary + magenta corner markers) shown by `ProjectionRootView` when `store.calibrating`; `WorkspaceView.detectSurfaces` orchestrates project → upload → `CalibrationMarkerDetector` → `PerspectiveRectifier` → `SurfaceDetector.detectSurfaces` → review. App module (not unit-tested) — verified by build, an offscreen render of the pattern, an offscreen end-to-end demo (markers composited on a real photo), and a manual launch.

**Tech Stack:** SwiftUI/AppKit, LumoraKit. Verified by `swift build` + `swift test` (LumoraKit demo) + packaged-app launch.

## Global Constraints

- Reuse Stage-1 `CalibrationPattern`, `CalibrationMarkerDetector`, `PerspectiveRectifier`.
- The review sheet must show the **processed** image (rectified when calibration succeeded, else the original) so normalized surfaces overlay correctly.
- No detection-algorithm or `.lumora` change.
- LumoraKit tests stay green (currently 174).

---

## File Structure

- `Sources/Lumora/ProjectStore.swift` (modify) — `@Published var calibrating`.
- `Sources/Lumora/Views/CalibrationPatternView.swift` (create) — projected pattern.
- `Sources/Lumora/Views/ProjectionView.swift` (modify) — show pattern when calibrating.
- `Sources/Lumora/Views/WorkspaceView.swift` (modify) — new detect flow + fallback alert.
- `Tests/LumoraTests/CalibrationEndToEndTests.swift` (create) — opt-in offscreen demo.

---

### Task 1: `calibrating` flag + `CalibrationPatternView` + projection wiring

**Files:**
- Modify: `Sources/Lumora/ProjectStore.swift`
- Create: `Sources/Lumora/Views/CalibrationPatternView.swift`
- Modify: `Sources/Lumora/Views/ProjectionView.swift`

**Interfaces:**
- `ProjectStore.calibrating: Bool` (published, default false).
- `CalibrationPatternView` — fills its container; black background, glowing magenta inset boundary, four filled magenta corner markers (geometry from `CalibrationPattern`).
- `ProjectionRootView` renders `CalibrationPatternView` (unscaled, full window) when `store.calibrating`, else the existing surfaces.

- [ ] **Step 1: Add the flag**

In `ProjectStore.swift`, next to `@Published var projecting`:

```swift
    /// True while the projector is showing the surface-detection calibration
    /// pattern (a boundary + corner markers) instead of scene content.
    @Published var calibrating: Bool = false
```

- [ ] **Step 2: Create `CalibrationPatternView`**

Create `Sources/Lumora/Views/CalibrationPatternView.swift`:

```swift
import LumoraKit
import SwiftUI

/// The projected calibration pattern: a glowing magenta boundary + four filled
/// magenta corner markers on black. Fills the projector output so the markers
/// sit at the projection's corners.
struct CalibrationPatternView: View {
    private var magenta: Color {
        Color(red: CalibrationPattern.markerColor.r,
              green: CalibrationPattern.markerColor.g,
              blue: CalibrationPattern.markerColor.b)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let minDim = min(w, h)
            let bInset = minDim * CalibrationPattern.boundaryInsetFraction
            let mInset = minDim * CalibrationPattern.markerInsetFraction
            let r = minDim * CalibrationPattern.markerRadiusFraction
            let corners = [CGPoint(x: mInset, y: mInset),
                           CGPoint(x: w - mInset, y: mInset),
                           CGPoint(x: w - mInset, y: h - mInset),
                           CGPoint(x: mInset, y: h - mInset)]
            ZStack {
                Color.black
                RoundedRectangle(cornerRadius: 4)
                    .stroke(magenta, lineWidth: max(3, minDim * 0.006))
                    .padding(bInset)
                    .shadow(color: magenta, radius: 14)
                    .shadow(color: magenta, radius: 6)
                ForEach(corners.indices, id: \.self) { i in
                    Circle()
                        .fill(magenta)
                        .frame(width: 2 * r, height: 2 * r)
                        .position(corners[i])
                        .shadow(color: magenta, radius: 12)
                }
            }
            .frame(width: w, height: h)
        }
        .ignoresSafeArea()
    }
}
```

- [ ] **Step 3: Show it in `ProjectionRootView`**

In `ProjectionView.swift`, replace the inner `ZStack { Color.black; TimelineView… }` content so the pattern takes over when calibrating:

```swift
            ZStack {
                Color.black
                if store.calibrating {
                    CalibrationPatternView()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    TimelineView(.animation) { timeline in
                        // …existing body unchanged…
                    }
                }
            }
```

(Keep the existing `TimelineView` block verbatim inside the `else`.)

- [ ] **Step 4: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 5: Offscreen-render the pattern to eyeball it**

Create a throwaway check (delete after) — render `CalibrationPatternView` at 800×450 via `ImageRenderer` and view it:

```bash
cat > /tmp/pattern_preview.swift <<'SWIFT'
// (run as a standalone SwiftUI snippet is impractical; instead verify in-app)
SWIFT
```

Since `CalibrationPatternView` is in the app module, verify it in the running app in Task 3 instead. For now confirm the build only.

- [ ] **Step 6: Commit**

```bash
git add Sources/Lumora/ProjectStore.swift Sources/Lumora/Views/CalibrationPatternView.swift Sources/Lumora/Views/ProjectionView.swift
git commit -m "feat: calibrating flag + projected CalibrationPatternView

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Detect Surfaces calibration flow (`WorkspaceView`)

**Files:**
- Modify: `Sources/Lumora/Views/WorkspaceView.swift`

**Interfaces:**
- `detectSurfaces()` rewritten: set `store.calibrating`, ensure projection is open, prompt for the photo, detect markers → rectify → `detectSurfaces`, present the review sheet on the processed image, clear `calibrating`, and warn + fall back to the raw photo when markers aren't found.

- [ ] **Step 1: Add fallback-warning state**

Add near the other `@State`s in `WorkspaceView`:

```swift
    @State private var showCalibrationWarning = false
```

- [ ] **Step 2: Rewrite `detectSurfaces()`**

Replace the existing `detectSurfaces()` with:

```swift
    /// Project the calibration pattern, take an uploaded photo, rectify it to the
    /// projected boundary, then detect surfaces (falling back to the raw photo if
    /// the four markers aren't found).
    private func detectSurfaces() {
        store.calibrating = true
        let startedProjection = !store.projecting
        if startedProjection { openWindow(id: "projection") }

        let panel = NSOpenPanel()
        panel.message = "A magenta boundary is now projected. Photograph the scene with all four corner markers visible, then choose that photo."
        panel.prompt = "Detect"
        panel.allowedContentTypes = [.jpeg, .png, .heic, .image]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url,
              let nsImage = NSImage(contentsOf: url),
              let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            store.calibrating = false
            if startedProjection { dismissWindow(id: "projection") }
            return
        }

        detecting = true
        Task {
            let corners = CalibrationMarkerDetector.detectCorners(in: cg)
            let processed: CGImage
            let calibrated: Bool
            if let corners, let rect = PerspectiveRectifier.rectify(cg, corners: corners) {
                processed = rect; calibrated = true
            } else {
                processed = cg; calibrated = false
            }
            let detected = SurfaceDetector.detectSurfaces(in: processed)
            let processedImage = NSImage(cgImage: processed,
                                         size: NSSize(width: processed.width, height: processed.height))
            await MainActor.run {
                store.calibrating = false
                if startedProjection { dismissWindow(id: "projection") }
                reviewImage = processedImage
                reviewSurfaces = detected
                detecting = false
                if calibrated { showReview = true } else { showCalibrationWarning = true }
            }
        }
    }
```

- [ ] **Step 3: Add the fallback alert**

Add to the view (next to the existing `.alert("Experimental feature", …)`):

```swift
        .alert("Calibration markers not found", isPresented: $showCalibrationWarning) {
            Button("Detect Anyway") { showReview = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Couldn't find the four projected markers in the photo. You can still detect surfaces on the original photo, but they may not align to the projection.")
        }
```

- [ ] **Step 4: Update the Detect Surfaces button tooltip**

Change the `.help(...)` on the Detect Surfaces button to reflect the new flow:

```swift
            .help("Projects a calibration boundary, then detects surfaces from a photo of the scene aligned to the projection.")
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: Build complete.

- [ ] **Step 6: Commit**

```bash
git add Sources/Lumora/Views/WorkspaceView.swift
git commit -m "feat: Detect Surfaces projects calibration boundary + rectifies photo

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: End-to-end verification

**Files:**
- Create: `Tests/LumoraTests/CalibrationEndToEndTests.swift`

**Interfaces:**
- Opt-in LumoraKit test that composites magenta markers onto a real room photo (simulating the projected+photographed scene), runs `detectCorners` → `rectify` → `detectSurfaces`, and writes overlays — proving the core pipeline the app calls.

- [ ] **Step 1: Add the opt-in end-to-end demo**

Create `Tests/LumoraTests/CalibrationEndToEndTests.swift`:

```swift
import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import LumoraKit

final class CalibrationEndToEndTests: XCTestCase {
    func testCalibrationPipelineOnRealPhoto() throws {
        guard let path = ProcessInfo.processInfo.environment["CAL_IMAGE"],
              let dir = ProcessInfo.processInfo.environment["CAL_DIR"] else { throw XCTSkip("env") }
        let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil)!
        let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)!

        // Simulate the photographed scene: paint magenta markers at an inset,
        // slightly trapezoidal quad (as a tilted photo would capture them).
        let W = min(cg.width, 1200), H = Int(Double(W) * Double(cg.height) / Double(cg.width))
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
        let m = CalibrationPattern.markerColor
        ctx.setFillColor(CGColor(red: m.r, green: m.g, blue: m.b, alpha: 1))
        let markers = [(0.12, 0.15), (0.88, 0.10), (0.92, 0.88), (0.08, 0.92)] // normalized top-left
        let r = Double(min(W, H)) * 0.03
        for (nx, ny) in markers {
            let cx = nx * Double(W), cy = (1 - ny) * Double(H) // to CG y-up
            ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        }
        let photo = ctx.makeImage()!

        let corners = CalibrationMarkerDetector.detectCorners(in: photo)
        XCTAssertNotNil(corners, "markers should be found")
        guard let corners, let rect = PerspectiveRectifier.rectify(photo, corners: corners) else { return }
        let surfaces = SurfaceDetector.detectSurfaces(in: rect)
        XCTAssertFalse(surfaces.isEmpty)

        // Write the rectified image with detected surfaces for eyeballing.
        let rw = rect.width, rh = rect.height, frh = CGFloat(rh)
        let out = CGContext(data: nil, width: rw, height: rh, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        out.draw(rect, in: CGRect(x: 0, y: 0, width: rw, height: rh))
        out.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)); out.fill(CGRect(x: 0, y: 0, width: rw, height: rh))
        let palette = [CGColor(red: 0.2, green: 1, blue: 0.5, alpha: 1), CGColor(red: 1, green: 0.6, blue: 0.2, alpha: 1),
                       CGColor(red: 0.4, green: 0.6, blue: 1, alpha: 1), CGColor(red: 1, green: 0.4, blue: 0.8, alpha: 1)]
        for (i, s) in surfaces.enumerated() {
            let d = s.polygon.map { CGPoint(x: $0.x * CGFloat(rw), y: frh - $0.y * CGFloat(rh)) }
            guard let f = d.first else { continue }
            let c = palette[i % palette.count]
            out.setStrokeColor(c); out.setLineWidth(3); out.setFillColor(c.copy(alpha: 0.16)!)
            out.move(to: f); for p in d.dropFirst() { out.addLine(to: p) }; out.closePath(); out.drawPath(using: .fillStroke)
        }
        let img = out.makeImage()!
        let url = URL(fileURLWithPath: dir).appendingPathComponent("calibration_result.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil); _ = CGImageDestinationFinalize(dest)
        print("CALIBRATION rectified \(rw)x\(rh) surfaces=\(surfaces.count) -> \(url.path)")
    }
}
```

- [ ] **Step 2: Run the end-to-end demo**

Run: `CAL_IMAGE=/Users/zaks/Downloads/room-images/IMG_5533.jpeg CAL_DIR=<scratchpad> swift test --filter CalibrationEndToEndTests`
Expected: PASS; prints the rectified size + surface count; writes `calibration_result.png`. Eyeball it — the photo should be de-keystoned to the marker rectangle and surfaces overlaid.

- [ ] **Step 3: Full suite + build**

Run: `swift test` (green) and `swift build` (app compiles).

- [ ] **Step 4: Launch the packaged app + manual check**

`./scripts/make_app.sh` and `open dist/Lumora.app`. Click **Detect Surfaces** → confirm the projection window shows the glowing magenta boundary + four corner markers on black, and the file panel prompts for the photo. Pick the `calibration_result` source or a real marker photo → confirm the review sheet shows the rectified image with detected surfaces. Cancelling the panel returns to the editor and stops projection if it was auto-started. (The physical photograph step is inherently manual.)

- [ ] **Step 5: Commit**

```bash
git add Tests/LumoraTests/CalibrationEndToEndTests.swift
git commit -m "test(detect): calibration end-to-end demo (opt-in)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (Stage 2 slice):**
- `calibrating` flag + projected pattern view → Task 1. ✅
- Auto-show pattern on Detect Surfaces, starting projection if needed → Task 2. ✅
- Upload → detect markers → rectify → detectSurfaces → review on the rectified image → Task 2. ✅
- No-markers fallback with a warning → Task 2 (alert). ✅
- Exit calibration on completion/cancel; stop projection if auto-started → Task 2. ✅
- Verification (build, offscreen end-to-end, launch) → Task 3. ✅

**Placeholder scan:** No TBD/TODO; complete code; Task 1 Step 5 defers the pattern eyeball to the in-app launch (Task 3), which is a concrete instruction, not a gap. ✅

**Type consistency:** `store.calibrating` drives `ProjectionRootView`; `CalibrationMarkerDetector.detectCorners -> [CGPoint]?` feeds `PerspectiveRectifier.rectify(_:corners:)` feeds `SurfaceDetector.detectSurfaces`; `reviewImage`/`reviewSurfaces` types unchanged. ✅

**Scope check:** App wiring only — reuses the Stage-1 core; no algorithm/model change. ✅
```

