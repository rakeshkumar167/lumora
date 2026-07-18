# Copy surface outlines into a new scene

**Date:** 2026-07-18
**Status:** Approved (design), pending implementation plan

## Goal

When the user creates a new scene from the scene strip's `+` button, offer to
copy the surface outlines from the scene they were just working on. Choosing to
copy seeds the new scene with the same surfaces (same geometry), each rendering
the default `grid` alignment effect — so the user can re-map the same physical
layout in the new scene without redrawing every surface.

## Non-goals

- No change to the `.lumora` save format or the `Project`/`ProjectScene` data
  model.
- No cross-scene "linked" surfaces — copies are independent (fresh `id`s); later
  edits to one scene do not affect the other.
- No "don't ask again" preference; the prompt is lightweight and only appears
  when there is something to copy.

## Behavior

The `+` button in `SceneStripView` gates on the **currently active scene**
(the one the user is viewing when they press `+`):

- **Active scene has ≥1 surface** → show a confirmation prompt
  (`.confirmationDialog`) with three choices:
  - **Copy Outlines** (default) — add a new scene seeded with a copy of every
    surface from the active scene.
  - **Empty Scene** — add a blank new scene (today's behavior).
  - **Cancel** — add nothing.
- **Active scene is empty** → add a blank new scene silently, no prompt
  (unchanged from today).

### What a copied surface carries over

Each source surface is copied with:

- **Preserved:** `name`, `points`, `shape`, `rotation`, `opacity`, `zIndex`,
  `isVisible`.
- **Fresh:** a new `id` (copies are independent of the source).
- **Reset:** `media` becomes `.effect(.grid, .cyan, <dark bg>)` — the same grid
  default used by `ProjectStore.addSurface()`.
- **Dormant:** per-effect config structs (`marquee`, `christmasLights`,
  `gameOfLife`, `fallingLeaves`, `threeD`, `paintDrip`, `countdown`, etc.) are
  left as-is; they are ignored while the effect is `grid`.

Preserving `zIndex` keeps the same front-to-back draw order in the new scene.

## Architecture

Two files change. No new types.

### `ProjectStore.swift`

Change `addScene()` to:

```swift
func addScene(copyOutlinesFromActive: Bool = false) {
    var newScene = ProjectScene(name: "Scene \(scenes.count + 1)")
    if copyOutlinesFromActive, let source = activeScene {
        newScene.surfaces = source.surfaces.map { s in
            var copy = s
            copy.id = UUID()
            copy.media = .effect(.grid, .cyan, RGBAColor(r: 0.05, g: 0.06, b: 0.09))
            return copy
        }
    }
    scenes.append(newScene)
    selectScene(scenes.count - 1)
}
```

`activeScene` is read **before** `append`, so it still refers to the source
scene. The default argument value (`false`) keeps every existing caller
(`addScene()`) behaving exactly as before.

### `SceneStripView.swift`

- Add `@State private var showCopyPrompt = false`.
- The `+` button action:

  ```swift
  Button {
      if store.activeScene?.surfaces.isEmpty == false {
          showCopyPrompt = true
      } else {
          store.addScene()
      }
  } label: { Image(systemName: "plus")... }
  ```

- Attach a confirmation dialog:

  ```swift
  .confirmationDialog(
      "Copy surface outlines from this scene into the new one?",
      isPresented: $showCopyPrompt,
      titleVisibility: .visible
  ) {
      Button("Copy Outlines") { store.addScene(copyOutlinesFromActive: true) }
      Button("Empty Scene") { store.addScene() }
      Button("Cancel", role: .cancel) {}
  }
  ```

## Verification

- `swift build` succeeds; `swift test` still passes (no logic touched by tests
  changes behavior; the new default arg is additive).
- Manual demo on the packaged `.app`:
  1. Draw one or two surfaces in Scene 1.
  2. Press `+` → confirm the prompt appears.
  3. Choose **Copy Outlines** → the new scene shows the same outline(s), each
     rendering the grid effect; confirm the copies are independent (move one,
     the source is unchanged).
  4. Press `+` again and choose **Empty Scene** → blank scene, no copies.
  5. From an empty scene, press `+` → new scene added with no prompt.

## Risks

- Minimal. The only behavioral surface is the new confirmation branch; the store
  change is additive with a safe default. Leftover dormant per-effect configs on
  copies are harmless under `grid` and would only matter if the user later
  switches a copied surface to that specific effect — acceptable.
