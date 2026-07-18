# Convert detected polygon → quad in the review sheet

**Date:** 2026-07-18
**Status:** Approved (design), pending implementation plan

## Goal

In the auto-detect **review sheet** (`SurfaceDetectionReviewView`), let the user
turn a detected **polygon** surface into a **quad** with a per-surface, reversible
**Make Quad** toggle. Quads warp with true homography keystoning, so many users
will want to regularize a jagged detected polygon (e.g. a TV or wall with a
ragged edge) into a clean 4-corner quad before adding it.

## Key decisions (confirmed with user)

1. **Per-surface, reversible toggle** — each polygon (non-quad) reviewable item
   gets its own **Make Quad** control; toggling off restores the original
   polygon. Quads don't show the control.
2. **Quad construction = longest-adjacent-edges parallelogram**, with a
   **minimum-area enclosing quad** fallback for shapes the heuristic doesn't fit.
3. Review-time only — no model or `.lumora` save-format change. An added
   4-corner item already becomes a `.quad` surface via the existing count-based
   inference in `ProjectStore.addDetectedSurfaces`.

## Geometry — `PolygonToQuad.convert(_ polygon:) -> [CGPoint]`

Pure LumoraKit helper (in `Sources/LumoraKit/SurfaceDetection/`), unit-tested.
Input/output are normalized `[0,1]` top-left points; output is exactly 4 corners
ordered TL, TR, BR, BL (via `SurfaceGeometry.orderedCorners`).

Algorithm:

1. **Trivial sizes.** `count == 4` → return ordered as-is. `count == 3` →
   parallelogram-complete (see step 3) then order. `count < 3` → return input.
2. **Edge-based candidates** (the user's rule — keep the dominant real edges as
   the base so perspective/tilt is preserved):
   - **3 adjacent edges:** over all `i`, take the window of 3 consecutive edges
     `(e_i, e_{i+1}, e_{i+2})` with the greatest total length; its 4 vertices
     `[p_i, p_{i+1}, p_{i+2}, p_{i+3}]` form candidate `q3`.
   - **2 adjacent edges:** over all `i`, take the window of 2 consecutive edges
     with the greatest total length; its 3 vertices `A=p_i, B=p_{i+1}, C=p_{i+2}`
     complete to a parallelogram with **D = A + C − B**, giving candidate `q2`
     (the two chosen edges stay as the base).
   - Indices wrap around the closed ring.
3. **Pick the fit.** Score `q3` and `q2` by overlap with the original polygon
   (`SurfaceGeometry.overlapOverSmaller`). If the better of the two clears a fit
   threshold (**0.70**), use it. Otherwise fall back to
   `SurfaceGeometry.enclosingQuad(SurfaceGeometry.convexHull(polygon))` — the
   existing min-added-area enclosing quad (allows perspective trapezoids, not
   just an upright rectangle).
4. Return `SurfaceGeometry.orderedCorners(chosen)`.

Rationale for reusing `enclosingQuad`/`convexHull`: they are the same helpers the
region-growing pass already uses to reduce a hull to a quad, so the fallback
matches the app's existing notion of a "best quad" and needs no new min-area-rect
implementation.

## Review-sheet UX — `SurfaceDetectionReviewView`

- `ReviewItem` gains `originalCorners: [CGPoint]` (captured at init) and
  `isQuadified: Bool`.
- For an item whose original outline is **not** a quad (`originalCorners.count != 4`),
  the item's chip in the horizontal strip shows a small **Make Quad** toggle
  beside its keep toggle:
  - Toggle **on** → `corners = PolygonToQuad.convert(originalCorners)`,
    `isQuadified = true`. The four handles become draggable as usual; the on-canvas
    path/handles already render N points, so no drawing change.
  - Toggle **off** → `corners = originalCorners`, `isQuadified = false`.
- Manual "Add Surface" items and already-quad detected items don't show the
  toggle (they're quads).
- On **Add**, `onAdd` returns each kept item's current `corners`; a quadified item
  has 4 corners → `ProjectStore.addDetectedSurfaces` makes it a `.quad`.

## Non-goals

- No change to detection itself (`detectSurfaces` output unchanged).
- No global "convert all" button (per-surface only, per the decision).
- No new persisted fields; the toggle state lives only in the review sheet.

## Testing

- **Unit tests** (`PolygonToQuadTests`, LumoraKit):
  - An L-shaped 3-vertex input → parallelogram (4th point = A + C − B).
  - A 5-point polygon dominated by 3 long consecutive edges → those 4 vertices.
  - A blobby many-point polygon with no dominant adjacent edges → the enclosing-
    quad fallback (4 corners enclosing the shape, overlap high).
  - An already-4-point input → returned ordered, unchanged set of corners.
  - Output is always exactly 4 corners, ordered TL,TR,BR,BL.
- **App**: `swift build`; launch the packaged app; in the review sheet on a real
  `room-images` photo, toggle a polygon to a quad, confirm the outline snaps to 4
  draggable corners, toggle back restores the polygon, and Add creates a quad
  surface. (Native sheet interaction is the manual step; the geometry is covered
  by unit tests.)

## Risks

- **Heuristic picks a poor base on odd shapes** — mitigated by the overlap-fit
  gate falling back to the enclosing quad, and by the user being able to drag the
  4 corners afterward or toggle back to the polygon.
