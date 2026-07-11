# Contour Trace — Rainbow & Multiple Images Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a rainbow (color-changing) trace option and multi-image build-up sequencing to the Contour Trace media type.

**Architecture:** The model case + a pure rainbow-band helper live in `LumoraKit` (unit-tested). `ContourTraceModel` concatenates each image's ordered contour walk; `ContourTraceContent` renders the sweep in one color or ~24 hue bands. The Properties panel gains an image list + rainbow toggle.

**Tech Stack:** Swift 5.9, SwiftUI (`Canvas`, `ImageRenderer`), AppKit (`NSOpenPanel`), Vision, XCTest.

## Global Constraints

- `LumoraKit` is UI-free: `Foundation`/`CoreGraphics` only.
- `MediaAssignment` keeps Swift's synthesized `Codable`; the new case shape is
  `contourTrace([URL], RGBAColor, Double, Bool)` = (images, penColor, speed, rainbow).
- Rainbow = one spectrum pass across the whole trace, quantized to
  `ContourTrace.rainbowBandCount = 24` bands, hue offset by `time * 0.03`.
- Multi-image: concatenate per-image walks in array order; all completed
  contours stay lit (build-up); `sweepDur = 6.0 * max(1, imageCount) / speed`.
- Keep the package compiling after every task.
- Commit after each task; messages end with:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`

---

### Task 1: Model case + rainbow-band helper (LumoraKit, TDD) + keep app compiling

**Files:**
- Modify: `Sources/LumoraKit/MediaAssignment.swift`
- Create: `Sources/LumoraKit/ContourTrace.swift`
- Create: `Tests/LumoraTests/ContourTraceTests.swift`
- Modify (compile fix, minimal): `Sources/Lumora/Views/SurfaceContentView.swift`, `Sources/Lumora/Views/PropertiesPanelView.swift`

**Interfaces produced:**
- `MediaAssignment.contourTrace([URL], RGBAColor, Double, Bool)`
- `enum ContourTrace { static let rainbowBandCount: Int; static func rainbowBand(length: CGFloat, total: CGFloat, phase: Double) -> Int }`

- [ ] **Step 1: Write failing tests** — `Tests/LumoraTests/ContourTraceTests.swift`:

```swift
import CoreGraphics
import Foundation
import XCTest
@testable import LumoraKit

final class ContourTraceTests: XCTestCase {
    func testContourTraceCodableRoundTrip() throws {
        let media = MediaAssignment.contourTrace(
            [URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/b.png")],
            .green, 1.5, true)
        let data = try JSONEncoder().encode(media)
        let back = try JSONDecoder().decode(MediaAssignment.self, from: data)
        XCTAssertEqual(media, back)
    }

    func testRainbowBandInRange() {
        for i in 0...100 {
            let b = ContourTrace.rainbowBand(length: CGFloat(i), total: 100, phase: 0)
            XCTAssertGreaterThanOrEqual(b, 0)
            XCTAssertLessThan(b, ContourTrace.rainbowBandCount)
        }
    }

    func testRainbowBandMonotonicAcrossOnePass() {
        let a = ContourTrace.rainbowBand(length: 0, total: 100, phase: 0)
        let mid = ContourTrace.rainbowBand(length: 50, total: 100, phase: 0)
        let end = ContourTrace.rainbowBand(length: 99, total: 100, phase: 0)
        XCTAssertEqual(a, 0)
        XCTAssertGreaterThan(mid, a)
        XCTAssertGreaterThan(end, mid)
    }

    func testRainbowBandWrapsWithPhase() {
        // A full phase of 1.0 wraps back to the same band as phase 0.
        let base = ContourTrace.rainbowBand(length: 25, total: 100, phase: 0)
        let wrapped = ContourTrace.rainbowBand(length: 25, total: 100, phase: 1.0)
        XCTAssertEqual(base, wrapped)
    }
}
```

- [ ] **Step 2: Run to verify fail** — `swift test --filter ContourTraceTests` → fails (member/case not found).

- [ ] **Step 3: Change the model case** in `Sources/LumoraKit/MediaAssignment.swift`:

```swift
    case contourTrace([URL], RGBAColor, Double, Bool)   // images, pen color, trace speed (×), rainbow
```
and the label:
```swift
        case .contourTrace(let urls, _, _, _):
            return "Contour Trace · \(urls.count == 1 ? (urls.first?.lastPathComponent ?? "") : "\(urls.count) images")"
```

- [ ] **Step 4: Create the helper** `Sources/LumoraKit/ContourTrace.swift`:

```swift
import CoreGraphics
import Foundation

/// Pure helpers for the Contour Trace effect's rainbow coloring.
public enum ContourTrace {
    /// Number of discrete hue bands across one spectrum pass.
    public static let rainbowBandCount = 24

    /// The hue band (0..<rainbowBandCount) for a point at `length` along a trace
    /// of total arc length `total`, with a wrapping `phase` offset (0…1). One
    /// spectrum pass spans the whole trace; phase drifts it over time.
    public static func rainbowBand(length: CGFloat, total: CGFloat, phase: Double) -> Int {
        guard total > 0 else { return 0 }
        let frac = Double(length / total) + phase
        let wrapped = frac - floor(frac)                     // 0…1
        let band = Int(wrapped * Double(rainbowBandCount))
        return min(max(band, 0), rainbowBandCount - 1)
    }

    /// Hue (0…1) at the center of a band, for `Color(hue:…)`.
    public static func hue(forBand band: Int) -> Double {
        (Double(band) + 0.5) / Double(rainbowBandCount)
    }
}
```

- [ ] **Step 5: Keep the app compiling (minimal).**
  In `SurfaceContentView.swift` update the dispatch (rendering upgraded in Task 2):
```swift
        case .contourTrace(let urls, let c, let speed, let rainbow):
            ContourTraceContent(urls: urls, color: c, speed: speed, rainbow: rainbow, time: time)
```
  Change `ContourTraceContent` to accept the new inputs (full behavior lands in
  Task 2 — for now, load all URLs and keep single-color rendering):
  - Replace its `let url: URL` with `let urls: [URL]`, add `let rainbow: Bool`.
  - Replace `.task(id: url) { model.load(url) }` with `.task(id: urls) { model.load(urls) }`.
  - Add `model.load(_ urls: [URL])` (Task 2 makes it concatenate; for now it may
    load `urls.first`). Simplest compile-safe stub: keep the existing single-URL
    `load` and call `if let u = urls.first { model.load(u) }`.

  In `PropertiesPanelView.swift`, update the destructuring so it compiles
  (full list UI in Task 3):
```swift
        case .contourTrace(let urls, let penColor, let speed, let rainbow):
            LabeledContent("Images", value: "\(urls.count)")
            Button("Choose Image…") { chooseContourImage(keeping: penColor) }
            if !rainbow {
                Text("Pen Color").font(.caption).foregroundStyle(.secondary)
                colorControls(current: penColor) { media = .contourTrace(urls, $0, speed, rainbow) }
            }
            Toggle("Rainbow", isOn: Binding(
                get: { rainbow },
                set: { media = .contourTrace(urls, penColor, speed, $0) }))
            Text("Trace Speed").font(.caption).foregroundStyle(.secondary)
            Slider(value: Binding(get: { speed }, set: { media = .contourTrace(urls, penColor, $0, rainbow) }), in: 0.05...4)
```
  and the two constructors:
```swift
        case .contourTrace: chooseContourImage()
```
```swift
    private func chooseContourImage(keeping color: RGBAColor = .green) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            media = .contourTrace([url], color, 1.0, false)
        }
    }
```

- [ ] **Step 6: Run tests + build** — `swift test --filter ContourTraceTests` passes; `swift build` succeeds.

- [ ] **Step 7: Commit** — `git commit -m "Add multi-image + rainbow contour-trace model and helper\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"`

---

### Task 2: Rendering — multi-image concatenation + rainbow bands

**Files:** `Sources/Lumora/Views/SurfaceContentView.swift`; verify script `scripts/verify_contour_rainbow.swift`.

- [ ] **Step 1: Multi-image load in `ContourTraceModel`.**
  Add:
```swift
    func load(_ urls: [URL]) {
        guard urls != loadedURLs else { return }
        loadedURLs = urls
        contours = []; totalLength = 0
        let work = urls
        DispatchQueue.global(qos: .userInitiated).async {
            var all: [ContourPolyline] = []
            for url in work {
                let cached = Self.cacheQueue.sync { Self.cache[url] }
                let c = cached ?? Self.extractContours(from: url)
                if cached == nil { Self.cacheQueue.sync { Self.cache[url] = c } }
                all.append(contentsOf: c)           // per-image walks, concatenated in order
            }
            DispatchQueue.main.async {
                if self.loadedURLs == work { self.apply(all) }
            }
        }
    }
```
  Add `private var loadedURLs: [URL] = []`. Keep the old single-URL `load` or
  remove it and update the caller. `extractContours` already returns an ordered
  walk (`orderAsWalk(dedupe(...))`), so concatenation preserves per-image order.

- [ ] **Step 2: Rainbow rendering in `ContourTraceContent`.**
  Replace the single-color stroke of `full`/`partial` with band-bucketed
  strokes when `rainbow` is true. Track cumulative arc length while building the
  drawn geometry; for each drawn segment, compute
  `ContourTrace.rainbowBand(length: cumLenAtSegmentMidpoint, total: total, phase: time * 0.03)`
  and append the segment to `bands[band]` (an array of `rainbowBandCount`
  `Path`s). Then, in a `drawLayer` blur pass and a core pass, stroke each
  non-empty band with `Color(hue: ContourTrace.hue(forBand: band), saturation: 0.95, brightness: 1)`.
  When `rainbow` is false, keep the existing two-path single-color stroke.
  Pen-tip color: `rainbow ? Color(hue: ContourTrace.hue(forBand: bandAtTip), …) : color.color`.
  Timing: `let sweepDur = 6.0 * Double(max(1, imageBoundaryCountUsedAsImageCount)) / max(speed, 0.02)`
  — since images are concatenated, use `sweepDur = 6.0 * max(1.0, ceil(total / perImageLenGuess))`
  is unreliable; instead pass the image count: add `let imageCount: Int` to the
  view (from `urls.count`) and use `sweepDur = 6.0 * Double(max(1, imageCount)) / max(speed, 0.02)`.

- [ ] **Step 3: Build** — `swift build` succeeds.

- [ ] **Step 4: Offscreen verify** — create `scripts/verify_contour_rainbow.swift`
  that renders two synthetic shapes (e.g. a circle image + a square image) as a
  concatenated contour trace with rainbow on, at a mid-sweep time, to
  `/tmp/contour_rainbow.png`. Confirm the gradient bands and that both shapes'
  outlines appear. (Standalone copy of the band math; the authoritative pieces
  are unit-tested.)

- [ ] **Step 5: Commit.**

---

### Task 3: Properties panel — image list + rainbow toggle

**Files:** `Sources/Lumora/Views/PropertiesPanelView.swift`.

- [ ] **Step 1: Replace the minimal editor** (from Task 1) with the full UI:
  - A per-image row: `ForEach(urls.indices, id: \.self)` showing
    `urls[i].lastPathComponent` + a trash button that removes index `i`
    (`media = .contourTrace(urls.removingIndex(i), …)`); disable the button when
    `urls.count <= 1`.
  - **Add Image…** button → `chooseContourImages(appendingTo: urls, …)` with
    `allowsMultipleSelection = true`, appending picked URLs.
  - **Rainbow** toggle (as in Task 1).
  - **Pen Color** swatches only when `!rainbow`.
  - **Trace Speed** slider.

```swift
    private func chooseContourImages(appendingTo urls: [URL], color: RGBAColor, speed: Double, rainbow: Bool) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif]
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            media = .contourTrace(urls + panel.urls, color, speed, rainbow)
        }
    }
```

- [ ] **Step 2: Build** — `swift build` succeeds.

- [ ] **Step 3: App smoke** — `swift run Lumora`, confirm launch (`pgrep`), quit.
  Operator-verify: add a Contour Trace, add a 2nd image, toggle Rainbow.

- [ ] **Step 4: Commit.**

---

### Task 4: Backlog + full test pass

**Files:** `docs/BACKLOG.md`.

- [ ] **Step 1:** Under the Contour Trace done section, note the rainbow option
  and multi-image build-up, and the compat caveat (old single-image contourTrace
  projects won't reopen).
- [ ] **Step 2:** `swift test` — full suite green.
- [ ] **Step 3: Commit.**

---

## Self-Review

- **Spec coverage:** model case (T1), rainbow helper + tests (T1), multi-image
  concat + rainbow render (T2), UI list + toggle (T3), backlog + caveat (T4).
- **Placeholders:** none.
- **Type consistency:** `contourTrace([URL], RGBAColor, Double, Bool)`,
  `ContourTrace.rainbowBand`/`hue(forBand:)`, `ContourTraceContent(urls:color:speed:rainbow:time:)`,
  `ContourTraceModel.load([URL])` used consistently across tasks.
