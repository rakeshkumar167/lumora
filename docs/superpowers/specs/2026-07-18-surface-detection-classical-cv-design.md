# Classical-CV Surface Detection Pipeline

**Date:** 2026-07-18
**Status:** Approved (design), pending implementation plan
**Supersedes as the detection method:** the current region-growing + Vision
detector in `Sources/LumoraKit/SurfaceDetection/`.
**Source input:** `docs/superpowers/specs/Surface_Detection_Pipeline_Swift_No_AI.md`
(user-provided raw spec; this document reconciles it with the actual codebase).

## Goal

Detect large visible planar surfaces in a room photograph as editable polygons,
using **only classical computer vision** — no OpenCV, no CoreML, no Vision object
recognition, no neural networks. The detector identifies planar regions bounded
by visible edges without attempting to recognize objects (wall, TV, door). The
user later edits, renames, and assigns content to each detected polygon using the
app's existing surface editing.

## Key decisions (confirmed with user)

1. **Pure-Swift classical CV.** No OpenCV dependency; implement the CV primitives
   (Canny, Hough, contour tracing, Douglas–Peucker) in Swift + Accelerate where
   useful. Keeps the package dependency-free, offline, deterministic, and
   testable — consistent with the rest of `LumoraKit`.
2. **macOS-native types.** `CGImage` in (not `UIImage`); `RGBAColor` (not
   `UIColor`). Output normalized to `[0,1]` so it maps to any display size.
3. **Scope = detection pipeline only.** Editing (vertex drag / insert / delete /
   move / rename) and rendering (the canvas + review overlay) already exist in
   the app and are reused. **Video tracking (optical flow) is out of scope** —
   a separate future spec.
4. **Output shape: quad-when-4-sided, else N-point polygon.** A region that
   approximates to 4 corners is emitted as a quad (maps to `SurfaceShape.quad`,
   keeping the homography keystone warp); anything else is an N-point polygon
   (maps to `SurfaceShape.polygon`, filling its bounding box and clipped to the
   outline, exactly like existing polygon surfaces).
5. **Three candidate sources feed one shared ranker:**
   - (primary) the **edge/contour pipeline** (Canny → contour → polygon),
   - the **line-intersection pipeline** (Hough → merge → intersections → quads),
   - the **region-growing plane pass** (kept from the current detector — the
     proven detector for blank/featureless walls that have few internal edges).
   **The Vision rectangle pass is dropped** (spec: classical CV only).
6. **Nested regions are detected** (a TV/window/mirror inside a wall becomes its
   own surface) via **contour hierarchy** — nested contours are kept separate and
   linked to their container, never merged into it.

## Non-goals

- No object/semantic labels (no "wall"/"TV"/"door" naming). Ordering is by size
  only.
- No video tracking / optical flow in this project.
- No new rendering layer — reuse the app's canvas and the existing
  `SurfaceDetectionReviewView` (adapted to draw polygons as well as quads).
- No OpenCV, CoreML, Vision object recognition, or any ML model.

## Architecture

All work lives in `Sources/LumoraKit/SurfaceDetection/`. Each component is a
small, single-responsibility, unit-tested unit. The public entry point stays
`SurfaceDetector`.

```
SurfaceDetector.detect(in: CGImage, options:) -> [DetectedSurface]
│
├── ImagePreprocessor      CGImage → grayscale Float buffer @ working res;
│                          Gaussian blur + edge-preserving (bilateral) smoothing
├── CannyEdgeDetector      Sobel gradient (magnitude + orientation) →
│                          non-max suppression → double-threshold hysteresis;
│                          thresholds auto-tuned from image statistics
├── HoughLineDetector      probabilistic Hough over the edge map → line segments;
│                          drop short; classify vertical/horizontal/diagonal
├── LineMerger             cluster near-parallel / close / overlapping segments
├── LineIntersector        intersect merged lines → candidate corners → quads
├── ContourTracer          Suzuki–Abe border following → contours WITH hierarchy
│                          (our findContours + RETR_TREE equivalent)
├── PolygonApproximator    Douglas–Peucker (approxPolyDP) contour → polygon
├── PolygonValidator       reject too-small / self-intersecting / off-frame /
│                          too-thin / too-irregular (configurable thresholds)
├── PolygonMerger          merge adjacent polygons (near-collinear shared edge +
│                          similar avg color); respect hierarchy (never merge
│                          a nested child into its parent)
├── SurfaceProperties      area, perimeter, centroid, bbox, aspect ratio,
│                          orientation, average color
├── ConfidenceScorer       0..1 from closure + edge strength + contour
│                          consistency + straightness
├── (region-growing pass)  kept from current detector — second candidate source
└── SurfaceRanker          (extend existing) largest-first sort + dedup/merge
                           across all sources
```

### Why both a line pipeline and a contour pipeline

They are complementary candidate generators. The **contour** route yields closed
shapes directly (great for framed objects and well-bounded regions). The
**line-intersection** route reconstructs large wall quads from long boundary
lines even when no single closed contour traces the whole wall. Both emit
candidates into the shared ranker, which already merges/dedups overlapping
candidates. If, during implementation, contours alone prove sufficient on the
sample set, the line pipeline can be demoted to a secondary rescue pass — but it
ships in v1.

## Data model

Replace the internal `DetectedQuad` with a unified surface candidate:

```swift
public struct DetectedSurface: Identifiable, Equatable {
    public var id: UUID
    public var polygon: [CGPoint]     // normalized [0,1]; exactly 4 pts when isQuad
    public var isQuad: Bool           // true → map to .quad (+ homography warp)
    public var area: Double           // normalized polygon area (fraction of frame)
    public var perimeter: Double
    public var centroid: CGPoint
    public var boundingBox: CGRect
    public var aspectRatio: Double
    public var orientation: Double    // dominant edge angle, radians
    public var averageColor: RGBAColor
    public var confidence: Double      // 0..1
    public var parentID: UUID?         // nesting: inner region → its container
}
```

`SurfaceDetector.Options` keeps its existing knobs (`workingWidth`,
`gradientBarrier`, `minFillRatio`, `minRectangularity`, ranker config, …) and
gains the new pipeline's configurable thresholds (Canny auto-tune bias, Hough
min line length, Douglas–Peucker epsilon, polygon validation limits, merge
collinearity/color tolerances, confidence weights). All defaults live in
`Options.init` as today.

## Integration

- `ProjectStore.addDetectedSurfaces` is extended to accept `[DetectedSurface]`:
  `isQuad` → `Surface(shape: .quad)`; otherwise `Surface(shape: .polygon)` with
  the N points. Each gets the standard grid default media (unchanged).
- `SurfaceDetectionReviewView` is adapted to overlay polygons as well as quads
  (draw the polygon path for non-quad candidates). This is minimal glue; the
  keep/discard review flow is otherwise unchanged.
- No `.lumora` save-format change — detected surfaces become ordinary `Surface`s.

## Coordinates & performance

- The pipeline runs at a **reduced working resolution** (long side ~720px) for
  speed; every output coordinate is normalized `[0,1]`, so results map back onto
  any display or projection size.
- **Target: detection < 150 ms** on a 1920×1080 photo (spec goal). This is
  measured on a bundled sample during verification; if pure-Swift Canny + Hough +
  Suzuki–Abe misses it, the working resolution is reduced further (the dominant
  lever). Treated as a goal to measure and tune toward, not a hard gate that
  blocks shipping a correct detector.

## Verification

- **Component unit tests with synthetic fixtures** (in `Tests/LumoraTests/`):
  - Canny on a synthetic step-edge image → edge on the boundary.
  - Hough on an image with known lines → recovered angles/positions.
  - `ContourTracer` on a **nested-rectangle** fixture → outer + inner contour
    with correct parent/child hierarchy.
  - Douglas–Peucker on a noisy polyline → simplified vertex set.
  - `PolygonValidator` / `PolygonMerger` / `ConfidenceScorer` / properties each
    tested on hand-built inputs.
- **Integration** against the bundled `Resources/surface-detection` samples:
  assert plausible surface counts and that the largest few candidates are large
  regions; render an **offscreen `ImageRenderer` overlay** of detected polygons
  on each sample and eyeball it (per memory: offscreen ImageRenderer verify).
- **Performance**: measure and report `detect()` time on a 1920×1080 sample.
- `swift test` stays green (existing 100 tests + the new ones).

## Delivery plan (staged, incremental sets — each compiles + tests green)

1. `ImagePreprocessor` + `CannyEdgeDetector` (+ synthetic tests, overlay verify).
2. `HoughLineDetector` + `LineMerger` + `LineIntersector`.
3. `ContourTracer` (Suzuki–Abe with hierarchy) + `PolygonApproximator`
   (Douglas–Peucker).
4. `PolygonValidator` + `PolygonMerger` + nested-region handling.
5. `SurfaceProperties` + `ConfidenceScorer` + unify sources into
   `DetectedSurface`; extend `SurfaceRanker`.
6. Wire into `SurfaceDetector.detect()` (drop Vision, keep region-growing);
   adapt `ProjectStore.addDetectedSurfaces` + `SurfaceDetectionReviewView` to
   quads-or-polygons; run sample + performance verification.

## Risks

- **Pure-Swift performance** — Canny + Hough + Suzuki–Abe in Swift on 720p is
  achievable but tight against 150 ms; mitigated by Accelerate for the
  convolution-heavy stages and by lowering working resolution. Correctness ships
  first; perf is tuned in stage 6.
- **Suzuki–Abe hierarchy correctness** is the trickiest component; it gets its
  own dedicated nested-fixture tests before anything depends on it.
- **Blank-wall regression** — the dropped Vision pass never helped there anyway;
  region-growing (kept) remains the blank-wall detector, and wall boundaries
  still produce Hough lines. Sample verification guards against regressions.
- **Sample coverage** — the five bundled samples may not exercise nested regions
  well; add a synthetic nested fixture to the test set if the samples are thin.
```

