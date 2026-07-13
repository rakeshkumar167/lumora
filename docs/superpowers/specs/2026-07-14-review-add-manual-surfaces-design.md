# Add manual surfaces on the surface-detection review screen

Date: 2026-07-14

## Problem

The Detect Surfaces review sheet (`SurfaceDetectionReviewView`) only lets the
user keep/discard and fine-tune the quads the detector proposed. If the detector
misses a wall, or finds nothing at all, there is no way to add a surface from
this screen — the user has to cancel and place one by hand on the canvas.

## Goal

Let the user add their own surfaces on the review screen, alongside the detected
ones, before committing them to the canvas.

## Design

### Interaction

- A **"+ Add Surface"** button in the sheet's bottom bar (beside Cancel).
- Clicking it appends a **default centered rectangle** (~40% of the photo,
  normalized corners in TL, TR, BR, BL order).
- The manual quad behaves exactly like a detected one: draggable corner handles,
  a keep/discard toggle in the horizontal strip, a palette color.
- It is labeled to read as user-added — a `plus.rectangle.on.rectangle` icon and
  the text **"Manual"** in place of the detected area percentage.
- The button is available **even when nothing was detected**, turning the
  "No surfaces detected" dead end into a usable starting point. The keep strip
  and the "Add N Surfaces" button appear whenever there is at least one item
  (detected or manual), not only when `quads` is non-empty.

### Refactor: single source of truth

Today three pieces of state are keyed against the immutable `quads`: the toggle
strip iterates `quads.indices`, while the canvas and handles iterate
`corners.indices`, with a parallel `keep` array. Appending items breaks that
coupling. Introduce one list the whole view drives off:

```swift
private struct ReviewItem: Identifiable {
    let id = UUID()
    var corners: [CGPoint]   // normalized, TL, TR, BR, BL
    var keep: Bool
    let label: String        // "62%" for detected, "Manual" for added
    let systemImage: String  // rectangle.dashed / tv / plus.rectangle.on.rectangle
}
@State private var items: [ReviewItem]
```

- `init` seeds `items` from `quads` (label = area %, icon by `source`).
- Canvas fill/stroke, corner handles, the toggle strip, and the "Add N" count all
  iterate `items`.
- Corner drags mutate `items[i].corners[j]`; toggles bind to `items[i].keep`.

### Unchanged interface

`onAdd` still emits `[[CGPoint]]` — the kept items' corners. So
`ProjectStore.addDetectedSurfaces` and `WorkspaceView` need no changes. Manual
and detected surfaces are indistinguishable once added (both become editable
quad surfaces with the grid default effect).

## Scope / non-goals

- **Quad only.** Matches the existing corner-drag editor. Polygon/ellipse
  editing continues to happen on the canvas after adding.
- **No draw/marquee placement mode** — the default rectangle plus corner drag is
  enough and reuses existing handles.

## Testing

Single SwiftUI view; no new pure logic to unit-test. Verify by building and
driving the app: open a room photo → Detect Surfaces → **+ Add Surface** →
drag its corners → **Add** → confirm the surface lands on the canvas. Also
confirm the button works from the "No surfaces detected" state.
