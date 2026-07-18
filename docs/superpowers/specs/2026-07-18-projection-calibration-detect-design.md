# Projected-boundary calibration for Detect Surfaces

**Date:** 2026-07-18
**Status:** Approved (design), pending implementation plan

## Goal

Make auto-detected surfaces align to the projector's actual output. When the user
clicks **Detect Surfaces**, the app projects a glowing boundary + four corner
markers onto the scene. The user photographs the scene (external camera) and
uploads the photo; the app finds the four projected markers, **perspective-
rectifies** the photo to the projector's rectangle, and runs surface detection on
the rectified image. Detected surfaces are therefore in **projector space** and
line up 1:1 with what the projector illuminates.

## Key decisions (confirmed with user)

1. **Perspective-rectify** the uploaded photo (homography via CoreImage
   `CIPerspectiveCorrection`), not a plain crop — corrects photos taken at an
   angle so detection runs in true projector space.
2. **Auto-show the calibration pattern** when Detect Surfaces is clicked
   (starting projection on the second display if not already running).
3. **Bright colored corner markers** — project four filled **magenta** markers
   (a saturated hue rarely present in rooms) plus the glow boundary; detect them
   by hue + brightness so scene highlights (windows, lamps) don't fool it.
4. Rectify to the **projector's aspect ratio**.
5. **Graceful fallback:** if four markers aren't found, warn and detect on the
   raw (un-rectified) photo — today's behavior.

## Flow

1. **Detect Surfaces** → enter calibration mode: `ProjectionRootView` shows the
   calibration pattern (glow boundary + 4 magenta corner markers on black),
   starting projection if needed. An editor prompt instructs: *"Photograph the
   scene with all four magenta corner markers visible, then choose the photo."*
2. User photographs the scene and picks the photo (existing `NSOpenPanel`).
3. `CalibrationMarkerDetector.detectCorners` locates the four markers.
4. If found → `PerspectiveRectifier.rectify` warps the photo to the projector
   aspect → run `SurfaceDetector.detectSurfaces` on the rectified image → review
   sheet shows surfaces on the rectified photo. If not found → alert, then detect
   on the raw photo.
5. On review done/cancel → exit calibration mode (restore normal projection).

## Components

### LumoraKit (pure, unit-tested)

- `CalibrationPattern` — shared constants: marker color (magenta
  `RGBAColor(r:0.92,g:0.20,b:0.62)`), marker radius fraction, boundary inset —
  used by both the projected view (app) and the detector so they agree.
- `CalibrationMarkerDetector.detectCorners(in image: CGImage, options:) -> [CGPoint]?`
  - Rasterize to a working-resolution RGB buffer (reuse `ImagePreprocessor.rgb`).
  - Mark pixels that are **magenta-ish and bright** (high R & B, low G, above a
    luminance floor) — tolerant threshold around `CalibrationPattern` color.
  - Connected-component the marked pixels (reuse `ConnectedComponents`), keep
    blobs above a minimum area, take each blob's centroid.
  - If ≥ 4 blobs: choose the four **corner** blobs by extremes
    (min x+y = TL, max x−y = TR, max x+y = BR, min x−y = BL); return normalized
    `[0,1]` corners ordered TL,TR,BR,BL. Else `nil`.
- `PerspectiveRectifier.rectify(_ image: CGImage, corners: [CGPoint], aspect: Double) -> CGImage?`
  - `corners` normalized `[0,1]` top-left, ordered TL,TR,BR,BL.
  - Output size: fit the projector `aspect` (e.g. width = image long side, height
    = width / aspect).
  - Use `CIFilter.perspectiveCorrection` with the four input points converted to
    CoreImage's **bottom-left** origin (y flipped) and pixel coordinates; render
    the `CIImage` back to a `CGImage`.

### App (build + manual verification)

- `ProjectStore.calibrating: Bool` (published) — drives the projection content.
- `CalibrationPatternView` — SwiftUI view: pure-black background, a glowing
  inset boundary rectangle (stroke + blur layer), and four filled magenta corner
  markers, geometry from `CalibrationPattern`. Fills the projector output.
- `ProjectionRootView` — when `store.calibrating`, render `CalibrationPatternView`
  instead of the composited surfaces.
- `WorkspaceView.detectSurfaces` — new flow: set `calibrating = true`; if not
  `store.projecting`, start projection; show the instruction; open the file
  panel; on pick run detect→rectify→detect-surfaces; present the review sheet
  with the (rectified) image; clear `calibrating` when the sheet closes. If the
  user cancels the file panel, clear `calibrating` and stop projection if we
  started it.

## Non-goals

- No in-app camera capture — the user photographs externally and uploads (matches
  the current upload flow).
- No change to the detection algorithm (`detectSurfaces`) or `.lumora` format.
- No multi-projector / multi-marker-ID calibration; a single rectangle boundary.
- No automatic re-detection on projector movement (one-shot calibration).

## Testing

- **LumoraKit unit tests:**
  - `CalibrationMarkerDetectorTests`: a synthetic image with four magenta discs
    near the corners (over a noisy/bright background) → returns four corners
    ordered TL,TR,BR,BL near the disc centers; a plain image → `nil`; discs
    off-square (perspective) still ordered correctly.
  - `PerspectiveRectifierTests`: an image with a known quad (four corner points)
    → rectified output has the expected dimensions/aspect; a synthetic scene with
    content inside the quad maps to the rectified frame corners (sample a couple
    of points).
- **App:** `swift build`; launch packaged app; click Detect Surfaces → confirm
  the projector (or, with one display, the projection window) shows the glow
  boundary + magenta corners; pick a photo that contains four magenta markers
  (a prepared test image) → confirm the review sheet shows the rectified photo
  with detected surfaces; confirm the no-marker fallback path warns and still
  detects.

## Risks

- **Marker vs scene color collision** — a magenta object in the room could be
  mistaken for a marker; mitigated by requiring four well-separated corner blobs
  and by the user reviewing results. Marker hue is configurable in
  `CalibrationPattern` if magenta proves poor.
- **CoreImage orientation** — `CIPerspectiveCorrection` uses bottom-left origin;
  the y-flip must be correct (guard with a rectifier unit test using an
  asymmetric fixture, per the raster flip lesson in prior stages).
- **One-display dev machines** — with no second screen the pattern shows in the
  projection window on the main display; acceptable for testing.
