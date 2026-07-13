# Projector Calibration (Colored-Marker Homography) — Design / Requirements

**Date:** 2026-07-13
**Status:** Approved (brainstorm), ready for implementation plan
**Model note:** To be resumed with Opus. Start from "Implementation notes for the
resuming session" at the bottom.

## Summary

Add a **Calibrate** workflow that aligns auto-detected surfaces to the
projector's output space. Lumora projects a colored alignment frame from the
projector; the user photographs the scene (with the frame visible) and uploads
the photo; the app finds the four colored corners, computes a photo→projector
homography, runs the existing surface detector, and maps the (optionally
hand-adjusted) detected quads through that homography so each surface lands
**back on the real object** when projected.

This is the calibration half of the older
[`2026-07-11-marker-calibration-auto-surfaces-design.md`](2026-07-11-marker-calibration-auto-surfaces-design.md).
That spec's detection + review half is **already implemented** — `SurfaceDetector`
(`Sources/LumoraKit/SurfaceDetection/`), the `SurfaceDetectionReviewView` sheet,
and its draggable corner handles all exist and ship today. This spec refines and
supersedes the *calibration* portion of that document, with three concrete
decisions the older spec left open (see below). Where the two disagree, this
document governs.

## What's already built (do not rebuild)

- `SurfaceDetector.detect(in:) -> [DetectedQuad]` — two-pass region + Vision
  detector producing quads in **photo top-left normalized** coordinates.
- `SurfaceDetectionReviewView` — sheet overlaying detected quads on the uploaded
  photo, per-quad keep/discard toggles, and **draggable corner handles**
  (`corners: [[CGPoint]]` state, edited in photo space, returned via `onAdd`).
- `WorkspaceView.detectSurfaces()` — file panel → off-main detection →
  presents the review sheet → `store.addDetectedSurfaces(corners)`.
- `ProjectStore.addDetectedSurfaces(_ quads: [[CGPoint]])` — appends one quad
  `Surface` per corner set; corners are **normalized canvas (== projector
  output) coordinates**.
- `ProjectionRootView` (`Sources/Lumora/Views/ProjectionView.swift`) — fullscreen
  projector output; scales `store.canvasSize` to the projector display; prefers a
  non-main `NSScreen`.

## Decisions made in this brainstorm (differ from the 2026-07-11 spec)

1. **Calibration goal = align to projector space** (true homography), not a
   framing aid.
2. **Target scene = whole room, multiple surfaces in one shot.** A single
   homography is accepted as an approximation for off-plane surfaces; the
   already-shipped drag-handles are the fine-tuning step.
3. **Corner detection = four saturated colored markers** (red TL, green TR,
   blue BR, yellow BL), detected by **hue + saturation** (not brightness), so a
   bright white wall does not interfere and each corner's identity is
   unambiguous. (The old spec used generic high-contrast blobs ordered by
   position.)
4. **Homography is applied at the commit step, not at detection.** Detection and
   the review overlay stay in photo space (so quads sit correctly on the photo);
   the transform maps corners into canvas space only when surfaces are added.
   Plain *Detect Surfaces* is unchanged — it uses an identity transform.

## Coordinate chain

```
photo pixels (normalized TL) ──H──▶ normalized canvas (== projector output) ──▶ Surface.points
```

`H` is built from four correspondences: the detected photo-normalized marker
centroids `P_i` ↦ their known normalized canvas positions `C_i`. Detected
surface corners (already photo-normalized, TL/TR/BR/BL) map through `H` into
canvas coordinates that project back onto the real object.

## Workflow (end to end)

1. **Click Calibrate** (toolbar button next to *Detect Surfaces*).
2. **Guided popup** appears (`CalibrationGuideView`), state 1: explains the flow;
   **Project Frame** button.
3. **Project Frame** → `store.calibrationActive = true`; open/reuse the
   projection window, which now shows the calibration pattern (§ Pattern).
   Popup advances to state 2: *"Photograph the whole scene including all four
   colored corners, then upload it."* → **Upload Photo** button.
4. **Upload Photo** → file panel (reuse `detectSurfaces()`'s panel) → load
   `CGImage`.
5. **Detect markers** → `CalibrationMarkerDetector.detect(in:)` → four
   photo-normalized corners `P_i`, or `nil`.
6. **Build `H`** = `Homography(from: P_i, to: C_i)`. If markers not found or `H`
   degenerate → error path (§ Error handling).
7. **Detect surfaces** → existing `SurfaceDetector.detect(in:)` on the same
   photo (off main thread).
8. **Review** → present the existing `SurfaceDetectionReviewView` over the photo
   (photo space, drag-handles) — unchanged.
9. **Commit** → in `onAdd`, map each returned corner through `H` → canvas coords
   → `store.addDetectedSurfaces`. Set `store.calibrationActive = false` (restore
   normal projection content).

## Pattern

`CalibrationPatternView` renders in canvas space (`store.canvasSize`), filling
the projector output:

- Black field.
- A thin bright framing outline just inside the edge (helps the user frame the
  shot; not used for detection).
- Four **filled saturated colored corner markers** at the known canvas corners,
  each a solid disc/square sized to a fraction of the canvas (large enough to
  survive downscaling in the photo). Colors + positions + size come from the
  shared `CalibrationPattern` constants.

Default corner insets: TL `(0.05, 0.05)`, TR `(0.95, 0.05)`, BR `(0.95, 0.95)`,
BL `(0.05, 0.95)` — matching the older spec so the markers sit at the extreme
corners without clipping.

## New units

### LumoraKit (pure, AppKit-free, unit-tested)

- **`Homography`**
  - `init?(from src: [CGPoint], to dst: [CGPoint])` — four-point projective
    solve (DLT / 8×8 linear system). Returns `nil` for degenerate input
    (collinear or coincident corners).
  - `func apply(_ p: CGPoint) -> CGPoint`.
  - If a `rect→quad` homography already exists in the core, a general
    point-correspondence solve can compose `(rect→dst) ∘ (rect→src)⁻¹`; a direct
    DLT is also fine. This is the correctness-critical piece — test in isolation.

- **`CalibrationPattern`** — shared constants read by both the renderer and the
  detector so they cannot drift:
  - the four corner colors (red/green/blue/yellow) as `RGBAColor` or components,
  - their four normalized canvas positions `C_i` (TL/TR/BR/BL order),
  - marker size (fraction of canvas), outline inset/width.

- **`CalibrationMarkerDetector`**
  - `static func detect(in image: CGImage, pattern: CalibrationPattern = .standard) -> [CGPoint]?`
    (expose a `CalibrationPattern.standard` instance carrying the default colors,
    positions, and sizes shared with the renderer).
  - Downscale to a working raster (reuse `SurfaceDetector`'s rasterization
    approach — note the CGBitmapContext top-left-row gotcha in
    [[lumora-effect-rendering-notes]]).
  - Convert to HSV/HSL. For each of the four target colors, score pixels by
    (high saturation) AND (hue near target), accumulate the highest-scoring
    connected blob, take its centroid. Return the four centroids in
    photo-normalized TL/TR/BR/BL order (order by target color, not by position).
  - Return `nil` if any color's best blob is below a confidence/size floor, or if
    the four points are collinear/degenerate. **Never fabricate a calibration.**

### Lumora (app)

- **`store.calibrationActive: Bool`** on `ProjectStore` (published).
- **`ProjectionRootView`** — branch on `store.calibrationActive`: show
  `CalibrationPatternView` when true, the normal composited content otherwise.
  Leaving calibration restores content automatically.
- **`CalibrationPatternView`** — renders `CalibrationPattern` in canvas space.
- **`CalibrationGuideView`** — the guided popup (sheet) with the three states in
  the workflow; holds no detection logic, just drives `calibrationActive` and the
  upload trigger via callbacks.
- **`WorkspaceView`** — new **Calibrate** toolbar button; owns the calibration
  state machine, the computed `Homography` (transient view state, not persisted),
  and wires `H` into the review sheet's `onAdd`. Factor the shared "pick photo →
  detect surfaces → review" tail so both *Detect Surfaces* (identity `H`) and
  *Calibrate* (computed `H`) reuse it.

## Error handling

- **Markers not found** (`detect` returns `nil`) or **degenerate `H`** → alert:
  *"Couldn't find all four colored corners — make sure the whole frame is visible
  and the room isn't too bright."* Buttons: **Retry** (re-open file panel) /
  **Continue without alignment** (identity `H`, i.e. current *Detect Surfaces*
  behavior).
- **No second display** → the pattern projects on the main display via the
  existing screen-pick logic; the guide text notes this so the user isn't
  surprised.
- Detection runs off the main thread (same `Task` pattern as `detectSurfaces()`).

## Testing & verification

- **`Homography` (unit):** identity correspondences → identity map; a known
  perspective quad → source corners land exactly on destination corners; a
  photo-point maps to the expected canvas point; inverse round-trip consistency;
  degenerate input → `nil`.
- **`CalibrationMarkerDetector` (unit):** synthetic image with four colored
  blobs arranged as a perspective-warped quad on a bright/neutral background →
  recovers the four centroids within tolerance and in correct color order;
  omit one color → `nil`; strongly colored decoy surface → still picks the
  marker blob (saturation/size floor).
- **Full-pipeline coordinate round-trip (unit):** choose a known `H`, project
  known canvas quads to a synthetic "photo" via `H⁻¹`, run detect + map back
  through `H`, assert recovered surfaces match originals within tolerance.
- **Visual (throwaway, then delete):** render `CalibrationPatternView` offscreen
  via `ImageRenderer` to confirm the pattern; and push a synthetic
  "photographed" perspective scene through the whole calibrate pipeline to an
  overlay PNG and inspect — per the established offscreen-verification approach
  ([[lumora-effect-rendering-notes]]). Use an **asymmetric** scene so a
  flip/mirror bug can't hide.

## Scope boundaries (YAGNI)

- One homography per calibration (accepted approximation for multi-surface).
- No lens-distortion correction, sub-pixel refinement, or multi-plane solve.
- No in-app/live camera capture — the user photographs with their own device and
  uploads a file, exactly as *Detect Surfaces* works today.
- No persisting the calibration homography in the `.lumora` document (only the
  resulting surfaces are saved, as today).
- Setting the uploaded photo as the editor backdrop (`ProjectStore.roomImage`) is
  **out of scope here** — it was a goal of the 2026-07-11 spec and can be a
  separate change; do not bundle it.
- Fine-tuning off-plane surfaces is the existing drag-handles, not new code.

## Implementation notes for the resuming session

- **Coordinate conventions to honor:** detector output and marker centroids are
  **photo top-left normalized**; `Surface.points` and `CalibrationPattern`
  positions are **canvas top-left normalized**; `ProjectionRootView` scales
  canvas→display. `H` maps photo-normalized → canvas-normalized. Keep the review
  overlay in photo space; apply `H` only in `onAdd`.
- **Files to touch:**
  - New (LumoraKit): `Sources/LumoraKit/Calibration/Homography.swift`,
    `CalibrationPattern.swift`, `CalibrationMarkerDetector.swift` (+ tests in
    `Tests/LumoraTests/`).
  - New (app): `Sources/Lumora/Views/CalibrationPatternView.swift`,
    `CalibrationGuideView.swift`.
  - Modify: `Sources/Lumora/ProjectStore.swift` (`calibrationActive`),
    `Sources/Lumora/Views/ProjectionView.swift` (mode branch),
    `Sources/Lumora/Views/WorkspaceView.swift` (Calibrate button + state machine +
    shared detect/review tail + `H` in `onAdd`).
- **Reuse, don't duplicate:** the file panel, off-main detection `Task`, and the
  `SurfaceDetectionReviewView` presentation already in `WorkspaceView`.
- **Check for an existing `Homography`/`rect→quad` type in LumoraKit first**
  (`Surface.displayQuadPoints`/warp may already carry one) and extend it rather
  than adding a parallel implementation.
- Follow the incremental, TDD, frequent-commit workflow; build with `swift build`
  and run `swift test` (whole suite currently green).
