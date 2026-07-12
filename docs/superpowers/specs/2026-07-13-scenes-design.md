# Scenes — Design

**Date:** 2026-07-13
**Status:** Approved.

## Goal

Turn a project from one flat composition into an ordered list of **scenes**.
Each scene has its own surfaces, light lines, and a play duration. The
projection output auto-advances through scenes by their durations and loops back
to the first when it reaches the end. The editor edits one selected scene at a
time.

## Model (LumoraKit)

```swift
public struct Scene: Identifiable, Equatable, Codable {
    public var id: UUID
    public var name: String
    public var surfaces: [Surface]
    public var lightLines: [LightLine]
    public var duration: TimeInterval   // seconds this scene plays; default 15
}
```

`Project` becomes scene-based, with backward-compatible decode:

```swift
public struct Project: Codable, Equatable {
    public var scenes: [Scene]
}
```
- Decode: if `scenes` is present, use it. Otherwise read legacy `surfaces` /
  `lightLines` and wrap them in a single `Scene(name: "Scene 1", …)`. This keeps
  old `.lumora` files loading.
- Encode: synthesized (writes `scenes`).

Pure timeline helper (unit-tested):

```swift
public enum SceneTimeline {
    /// Index of the scene playing at `elapsed` seconds into a looping sequence
    /// with the given per-scene durations. Returns 0 for empty/degenerate input.
    public static func index(at elapsed: Double, durations: [Double]) -> Int
}
```
- Clamps each duration to a small positive minimum so a 0-duration scene can't
  stall the loop. Wraps via `elapsed mod Σdurations`.

## ProjectStore

- `@Published var scenes: [Scene]` and `@Published var activeSceneIndex: Int`.
- `surfaces` and `lightLines` become **computed proxies** into
  `scenes[activeSceneIndex]` (get/set), so every existing surface/line method,
  binding, and view keeps working — they now operate on the active scene.
  Bounds-guarded (clamp `activeSceneIndex`).
- Selection (`selectedID`, `selectedLineID`) stays store-level; switching the
  active scene resets selection to that scene's first surface (or nil).
- Scene ops:
  - `addScene()` — append an empty scene, make it active.
  - `deleteScene(_ index:)` — remove; never go below one scene; fix active index.
  - `selectScene(_ index:)` — set active, reset selection.
  - `moveScene(from:to:)` — reorder.
  - `renameScene(_ index:, _ name:)`, `setSceneDuration(_ index:, _ seconds:)`.
- `makeProject()` → `Project(scenes: scenes)`. `load(_:)` → `scenes =
  project.scenes` (guaranteed ≥1 by decode), `activeSceneIndex = 0`.
- `sample()` seeds a single scene from the existing demo surfaces.

## Editor UI

- The canvas renders the **active** scene (unchanged `RoomCanvasView`, which
  reads `store.surfacesInDrawOrder` / `store.lightLines` — now the active
  scene's).
- New **bottom scene strip** (`SceneStripView`), full width under the canvas
  column: one selectable chip per scene showing name + duration; an inline
  duration stepper/field on the selected chip; **＋** to add; delete; reorder
  (left/right arrows on the selected chip); and a **Preview** play/pause that
  advances `activeSceneIndex` on a timer to preview the sequence in the editor.

## Projection

- `ProjectionView` derives the playing scene from elapsed time. On appear it
  records a start reference; each frame it computes
  `SceneTimeline.index(at: t - start, durations: sceneDurations)` and renders
  that scene's `surfacesInDrawOrder` + visible light lines. Loops forever.
- Effects continue to animate on the global monotonic clock (continuous across
  scene switches — no reset needed).

## Edge cases

- Always ≥1 scene. Deleting the active/last-but-one fixes the active index.
- Duration clamped to a sensible minimum (e.g. 1s) in the timeline helper.
- Single scene → projection just shows it (trivial loop).

## Testing

- `Project` decodes a legacy flat file into one scene; round-trips a
  multi-scene project.
- `Scene` codable round-trip.
- `SceneTimeline.index(at:)`: within-scene, exact boundaries, wrap past the end,
  empty list → 0, single scene, and a zero-duration scene doesn't stall.

## Out of scope (YAGNI)

- Cross-scene transitions/fades (hard cut for now).
- Per-scene backdrop photos (shared room image).
- Timeline scrubbing UI beyond the chip strip.
