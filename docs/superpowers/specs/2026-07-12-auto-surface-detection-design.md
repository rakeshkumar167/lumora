# Auto Surface Detection — Design

**Date:** 2026-07-12
**Status:** Approved (design questions answered); supersedes the paused
fiducial-based "Marker calibration & auto-surface detection" approach.

## Goal

From an imported room photo, automatically propose the **large flat quad
surfaces** a projector could map onto — skipping small clutter — and let the
user keep/discard each before it becomes an editable canvas surface.

## Why the previous approach was dropped

The paused plan projected corner fiducials, photographed the scene, and ran
Vision rectangle detection mapped through a photo→canvas homography. A research
spike (2026-07-12) on five real room photos showed the core detection was the
weak link, independent of the fiducial plumbing:

- **Vision `VNDetectRectanglesRequest`** returns pixel-tight quads at confidence
  1.00 — but only for *bordered objects* (TV screens, doors, cabinet panels).
  It is structurally blind to blank walls, which have no four interior edges.
- Blank walls are usually the **largest and most useful** projection surface.

So detection needs a second technique for planes, and the fiducial/homography
machinery is unnecessary for the chosen flow (photo is not shown as a backdrop;
quads map directly by normalized coordinates).

## Chosen approach — hybrid, plane-first

Run on a downscaled copy of the photo; both passes emit candidate quads:

1. **Planes (primary).** Coarse color quantization → region growing with a
   **gradient barrier** (growth cannot cross a strong luminance edge, e.g. the
   wall/floor seam — this is what prevents the greedy "swallow the whole frame"
   blob the spike exposed) → connected components → convex hull → reduce to the
   four strongest corners → reject fits whose region **fill ratio** is low.
2. **Objects (secondary).** `VNDetectRectanglesRequest` tuned for large, skewed
   quads (low `minimumSize` floor we then re-filter, wide aspect tolerance, high
   `quadratureTolerance`).
3. **Filter → merge → rank.** Drop candidates below a **minimum area fraction**
   (this is the "skip small surfaces" knob), suppress nested/overlapping
   duplicates (a candidate whose centroid lies inside a larger kept quad is
   dropped), rank by area with **planes weighted ahead of objects**, cap to N.

The spike confirmed this fixes the over-merge (a 74%-of-frame blob became a
clean 64% wall quad) and that residual **fragmentation / corner skew** on
edge-cluttered walls is the ceiling of single-photo auto-detection — which the
editable review step absorbs.

## User flow

1. **"Detect Surfaces"** button in the workspace toolbar.
2. `NSOpenPanel` → user picks a room photo (JPEG/PNG/HEIC).
3. Detector runs; a **review sheet** shows the photo with each detected quad
   drawn, numbered, colored by source, labeled with its area %, each with a
   keep/discard toggle (all kept by default).
4. **"Add N surfaces"** commits kept quads. Each becomes a standard `.quad`
   `Surface` (draggable corners, all existing editing applies). **No photo
   backdrop** — quads land on the normal blank canvas.

Photo space and canvas space are both normalized 0–1, so a detected quad's
normalized corners map straight onto `Surface.points` (identity). No homography.

## Components & boundaries

**`LumoraKit/SurfaceDetection/` — pure geometry & ranking (unit-tested).**
No AppKit/Vision. This is where TDD lives.

```swift
public enum QuadSource: String, Codable { case plane, object }

public struct DetectedQuad: Equatable {
    public var corners: [CGPoint]   // normalized 0…1, top-left origin, ordered TL,TR,BR,BL
    public var areaFraction: Double // 0…1, share of the image
    public var source: QuadSource
    public init(corners: [CGPoint], areaFraction: Double, source: QuadSource)
}

public enum SurfaceGeometry {
    public static func polygonArea(_ pts: [CGPoint]) -> Double        // shoelace, absolute
    public static func centroid(_ pts: [CGPoint]) -> CGPoint
    public static func convexHull(_ pts: [CGPoint]) -> [CGPoint]      // Andrew monotone chain, CCW
    public static func reduceToQuad(_ poly: [CGPoint]) -> [CGPoint]   // greedy: drop min-area-loss vertex until 4
    public static func orderedCorners(_ quad: [CGPoint]) -> [CGPoint] // -> TL,TR,BR,BL by position
    public static func contains(_ pt: CGPoint, in poly: [CGPoint]) -> Bool
}

public enum SurfaceRanker {
    public struct Config {
        public var minAreaFraction: Double   // default 0.05 — the "skip small" knob
        public var maxResults: Int           // default 8
        public var planeBoost: Double        // ranking multiplier for .plane, default 1.35
        public init(minAreaFraction: Double = 0.05, maxResults: Int = 8, planeBoost: Double = 1.35)
    }
    // Filter by area, suppress nested/overlapping, rank (planes first), cap.
    public static func filterMergeRank(_ candidates: [DetectedQuad], config: Config) -> [DetectedQuad]
}
```

**`Lumora/Detection/SurfaceDetector.swift` — app target (image I/O + Vision).**
Not unit-tested (image-dependent); validated by an offscreen verify script on
the five bundled samples, the same pattern used elsewhere.

```swift
enum SurfaceDetector {
    struct Options { var workingWidth: Int = 380; var ranker = SurfaceRanker.Config() }
    // Full pipeline: downscale -> region planes + Vision rects -> ranker.
    static func detect(in image: CGImage, options: Options = .init()) -> [DetectedQuad]
    // Internal: regionPlaneCandidates(_:) and objectCandidates(_:) both return [DetectedQuad].
}
```

**`Lumora/Views/SurfaceDetectionReviewView.swift` — review sheet.** Shows the
`NSImage`, overlays quads via `Canvas`, per-quad keep toggle, Add/Cancel.

**`Lumora/ProjectStore.swift` — commit.**
```swift
func addDetectedSurfaces(_ quads: [[CGPoint]])   // append a .quad Surface per corner set, select the first
```

**`Lumora/Views/WorkspaceView.swift`** — new toolbar button + open-panel +
sheet presentation state.

## Coordinate handling

- Vision returns normalized **bottom-left** origin → convert to top-left
  (`y' = 1 − y`) so everything downstream matches `Surface` convention.
- Region pass already works in top-left image space.
- `orderedCorners` sorts the four points into TL, TR, BR, BL (by centroid
  quadrant) so warping is correct.

## Testing

**Unit tests (`Tests/LumoraTests/SurfaceDetectionTests.swift`), pure, synthetic:**
- `polygonArea` of a unit square = 1; of a known triangle = expected.
- `convexHull` of a point cloud returns the enclosing polygon; collinear points
  dropped.
- `reduceToQuad` of a hexagon/pentagon returns 4 corners preserving the largest
  area; of an already-4-point poly returns it unchanged.
- `orderedCorners` maps a scrambled quad to TL,TR,BR,BL.
- `contains` true/false cases.
- `SurfaceRanker.filterMergeRank`:
  - drops a quad below `minAreaFraction`;
  - suppresses a small quad whose centroid is inside a larger one;
  - orders a `.plane` ahead of a slightly larger `.object` (planeBoost);
  - caps at `maxResults`.

**Offscreen validation (`scripts/verify_surface_detection.swift`):** run
`SurfaceDetector.detect` on each bundled sample, overlay results, write PNGs to
inspect — acceptance is a human look, not an assertion.

## Out of scope (YAGNI)

- Photo-as-canvas backdrop (declined).
- Fiducials / camera↔projector homography.
- Curved/non-quad surface detection.
- Auto-assigning effects to detected surfaces (they get the default like any new
  surface).

## Backlog / docs updates

- Mark the paused "Marker calibration & auto-surface detection" item as
  superseded by this design.
- On completion, add a "Done" note describing the shipped detector.
