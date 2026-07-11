# Marker Calibration & Auto-Surface Detection — Design / Requirements

**Date:** 2026-07-11
**Status:** Approved (brainstorm), ready for implementation plan

## Summary

A projector-calibration workflow that auto-creates projection surfaces from a
photo. Lumora projects four fiducial markers at known output positions; the user
photographs the scene and imports the photo; the app detects the fiducials to
compute a photo→projector mapping, detects the rectangular edges of physical
objects, and maps them through that mapping into editable **quad** surfaces. The
user reviews the candidates and keeps / discards / adjusts them before they enter
the project.

This turns manual corner-dragging of every surface into a "project markers →
snap a photo → auto-map" flow, and along the way delivers the backlogged
**room-photo import** (the calibration photo becomes the editor backdrop).

## Goals

- Project a known four-corner marker pattern from Lumora's projection output.
- Import a photo of the projected scene and detect those four markers.
- Compute a homography from photo-pixel space to Lumora's normalized canvas
  (= projector output) space.
- Detect rectangular physical objects in the photo and map them into canvas
  space as candidate quad surfaces.
- Present candidates for human review (keep / discard / adjust) before committing
  them as real surfaces.
- Use the imported photo as the editor backdrop.

## Non-goals (MVP scope / YAGNI)

- Multi-plane calibration (a single homography assumes one dominant flat plane).
- Live webcam capture (the photo is an imported image file).
- Non-rectangular object detection (contours/polygons) — rectangles → quads only.
- Coded/QR fiducials, checkerboards, or grids — four plain high-contrast corner
  fiducials only.
- Lens-distortion correction, sub-pixel refinement, bundle adjustment.
- Persisting the calibration itself (only the resulting surfaces + backdrop are
  saved, via the existing `.lumora` document).

## Key concept: the coordinate chain

Lumora's **normalized canvas space (0…1) is the projector-output space** —
`ProjectionRootView` merely scales canvas→display, and `Surface.points` are
normalized canvas coordinates. Therefore a shape detected in the photo, once
mapped photo→canvas, yields surface points that project **back onto the real
object**. The whole feature hinges on one homography:

```
photo pixels ──H──▶ normalized canvas (== projector output) ──▶ Surface.points
```

`H` is built from four correspondences: the four fiducials' detected photo-pixel
positions ↦ their known normalized canvas positions.

## The workflow (end to end)

1. **Calibrate mode.** Lumora renders four fiducials in the projection output at
   fixed normalized canvas corners (default 5% inset: TL `(0.05,0.05)`, TR
   `(0.95,0.05)`, BR `(0.95,0.95)`, BL `(0.05,0.95)`). They project onto the
   physical wall.
2. **Photograph.** User shoots the scene (wall + real objects + the four
   projected fiducials) with a phone, roughly upright.
3. **Import.** User imports the photo via a file picker (reusing the existing
   image-import panel pattern).
4. **Detect fiducials.** Find four fiducial blobs in the photo; order them
   TL/TR/BR/BL by position → four photo-pixel points `P_i`.
5. **Compute `H`.** Solve the photo→canvas homography from `P_i ↦ C_i` (the four
   known normalized canvas corners).
6. **Detect objects.** Run `VNDetectRectanglesRequest` on the photo → candidate
   rectangles, each a four-corner quad in photo-pixel space.
7. **Map.** Transform each candidate's four corners through `H` into normalized
   canvas coords → a candidate quad surface.
8. **Review & commit.** Show candidates overlaid on the photo; user toggles
   keep/discard per candidate and may nudge corners; committing adds the kept
   candidates to `store.surfaces` (default media, e.g. `grid`) where normal
   corner-drag editing applies. The photo becomes the editor backdrop.

## Architecture & components

### LumoraKit (pure, unit-tested)

- **General 4-point quad→quad homography.** The core currently provides
  `rect→quad`. Add a point-correspondence homography that maps an arbitrary
  source quad to an arbitrary destination quad. Implement as a composition
  `(rect→destQuad) ∘ (rect→srcQuad)⁻¹` (reusing the existing rect→quad solve plus
  a matrix inverse) or a direct DLT — whichever is cleaner in the existing
  `Homography` type. Must expose:
  - build from four source points + four destination points,
  - `apply(_ point:) -> CGPoint`.
  This is the correctness-critical piece and is tested independently of any UI.

### Lumora (app)

- **`CalibrationController`** (an `ObservableObject` or state on `ProjectStore`):
  drives the mode — toggles fiducial projection, holds the imported photo, the
  computed `H`, the detected candidates, and their keep/discard state; commits
  kept candidates into `store.surfaces`.
- **Fiducial projection overlay:** rendered inside `ProjectionRootView` (and
  optionally previewed in the editor) when calibrate mode is active — four
  high-contrast markers drawn at the known normalized canvas corners.
- **`FiducialDetector`:** Vision/CoreImage detection of the four markers in the
  photo, returning ordered photo-pixel points. Runs off the main thread (same
  pattern as the existing `CIEdges`/contour extractors in
  `SurfaceContentView.swift`).
- **`RectangleDetector`:** wraps `VNDetectRectanglesRequest` (tunable min-size,
  aspect, quadrature tolerance, max count); returns candidate quads in
  photo-pixel space. Off the main thread.
- **Calibration review UI:** a panel/sheet listing candidates with keep toggles,
  overlaid on the imported photo with adjustable corners; a "Create Surfaces"
  action to commit. Reuses the existing handle-drag editing once committed.
- **Backdrop:** set `ProjectStore.roomImage` to the imported photo so the editor
  canvas shows real context (delivers the backlogged room-photo import).

## Fiducial detection approach

Fiducials are simple, large, high-contrast marks (e.g. filled circles or
concentric ring targets) at the four known canvas corners. Detection: threshold
the imported photo, find the four strongest marker blobs (brightness/shape),
take their centroids, and order them by position into TL/TR/BR/BL. Because there
are exactly four at the extreme corners, positional ordering is reliable for a
roughly-upright shot. (Assumption: the photo is not rotated ≥45°; documented as a
constraint.) If four fiducials are not confidently found, surface a clear error
and let the user re-import — never fabricate a calibration.

## Review & edit UX

- Candidates are **staged**, not immediately added — a bad detection never
  clutters the project.
- Each candidate: keep/discard toggle, shown as an outlined quad over the photo.
- Kept candidates commit to `store.surfaces` with a default effect/media; from
  there the existing Arrow-tool corner handles and properties panel edit them
  normally.
- The user can re-run detection with different rectangle-detector parameters if
  results are poor.

## Assumptions & constraints

- **Single flat plane.** One homography assumes detected objects are ~coplanar
  with the plane the fiducials landed on. Off-plane objects map approximately.
- **Camera = imported image file**, not live capture.
- **One photo, dual use:** the calibration photo (fiducials faint at the corners)
  also serves as the editor backdrop; no separate clean shot in MVP.
- **Roughly-upright photo** for reliable fiducial ordering.
- Detection reliability (lighting, contrast, rectangle noise) is the main risk;
  it is deliberately mitigated by the human review step rather than by chasing
  perfect automatic detection.

## Testing & verification

- **LumoraKit:** unit tests for the quad→quad homography — known correspondences
  round-trip (source corners land on destination corners exactly, including a
  perspective quad); a photo-point maps to the expected canvas point; inverse
  consistency.
- **Detection (app):** verified offscreen on a sample photo — render the detected
  fiducials and candidate-quad overlays to a PNG via `ImageRenderer` and inspect,
  per the established offscreen-verification approach. No live GUI needed to prove
  the pipeline; the interactive review step gets a manual pass.
- **Coordinate round-trip sanity:** a synthetic test where known canvas quads are
  projected to a synthetic "photo" via a chosen homography, then recovered — the
  recovered surfaces should match the originals within tolerance.

## Open questions / future extensions

- Multi-plane / multi-marker calibration for non-coplanar scenes.
- Contour/polygon detection for non-rectangular objects.
- Coded fiducials (QR via `VNDetectBarcodesRequest`) for rotation-proof, more
  numerous correspondences and higher accuracy.
- Live webcam capture and an in-app "shoot now" step.
- Persisting the calibration homography in the `.lumora` document for re-use.
