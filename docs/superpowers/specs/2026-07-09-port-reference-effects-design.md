# Port 4 effects from lovable-projection-effects → Lumora

**Date:** 2026-07-09
**Status:** Approved design, ready for planning

## Goal

Port four generative effects from the reference React/canvas project
(`../lovable-projection-effects`, `src/routes/index.tsx`) into Lumora's SwiftUI
effect system. Delivered in two batches of two, matching the established
sets-of-2 rhythm, with a quick demo between batches.

- **Batch 1:** Voronoi Cells, Metaballs
- **Batch 2:** Hex Grid, Flow Field

Neon Life (Conway) was considered and **dropped** — it needs generational state,
which conflicts with Lumora's stateless (time-derived) effect convention.

## Existing architecture (unchanged)

Effects live in `Sources/Lumora/Views/SurfaceContentView.swift` and the model
enum in `Sources/LumoraKit/EffectKind.swift`. Adding an effect touches three
places:

1. **`EffectKind`** — new case + entries in `usesColor`, `usesAccent`, `displayName`.
   The picker (`PropertiesPanelView`) auto-populates from `EffectKind.allCases`,
   so no picker change is needed.
2. **`EffectView.body`** — add the new case to the category dispatch `switch`.
3. **A category ViewBuilder** — the renderer itself, a `Canvas { ctx, size in … }`
   driven by `time`.

**Convention to follow:** effects are *stateless* — all animation derives from
`time` (plus helpers `hash01`, `fract`). Renderers avoid per-pixel `ImageData`
loops (the JS technique) in favor of `Path`, `RadialGradient`, and coarse
filled rects, for SwiftUI `Canvas` performance.

## Changes

### EffectKind (append after `sierpinskiTriangle`)

New cases: `voronoi`, `metaballs`, `hexGrid`, `flowField`.

| case | displayName | usesColor | usesAccent |
|------|-------------|-----------|------------|
| `voronoi` | "Voronoi Cells" | false | false |
| `metaballs` | "Metaballs" | true | true |
| `hexGrid` | "Hex Grid" | true | true |
| `flowField` | "Flow Field" | false | false |

Rationale: Voronoi and Flow Field are rainbow/HSL-driven in the reference and
read best that way (like Aurora / Starfield Warp, which also use neither color);
Metaballs and Hex Grid map cleanly onto a `color` foreground + `accent`
background.

### EffectView dispatch + new category

Add a new `@ViewBuilder private var fieldEffects` grouping all four, and a case
in `EffectView.body`:

```swift
case .voronoi, .metaballs, .hexGrid, .flowField:
    fieldEffects
```

### Renderers (adapted to Lumora's style)

**Voronoi Cells** — coarse grid of filled rects (~12pt cells). ~20 sites drift
via `sin/cos(time·k + i)`. Each cell takes the hue of its nearest site; edge
darkening derived from `sqrt(2nd-nearest) − sqrt(nearest)`. Colors from HSL
(`Color(hue:saturation:brightness:)`), hue animated with `time`. Ref lines
361–419.

**Metaballs** — coarse scalar field on a grid (~10pt cells). 6 balls drift on
Lissajous paths (ref lines 909–915). For each cell, `sum += r²/(d²+1)`; if
`sum > 1` fill with `color` brightened by `sum`, else fill with `accent`
background. Ref lines 900–943.

**Hex Grid** — honeycomb of hex `Path`s, `size ≈ 34pt`, `hw = √3·size`,
`hh = 1.5·size`, odd rows offset by `hw/2`. Per-hex radial wave
`sin(dist·0.02 − time·3)` scales each hex and lerps `accent`→`color`
(brightness/scale pulse). Ref lines 865–897.

**Flow Field** — ~500 particles, each seeded deterministically from its index
via `hash01`. Position integrated over a fixed number of steps through the field
`ang = sin(x·0.005 + time·0.4)·π + cos(y·0.005 − time·0.3)·π`, drawn as a short
polyline streak. Particle "age" cycles via `fract(time·speed + seed)` to fade
in/out and reset — reproducing the JS flowing-streams look without persistent
state. HSL hue per particle animated with `time`. Ref lines 456–489.

## Testing / verification

No unit tests exist for effect rendering (they're visual `Canvas` closures).
Verification is the existing manual path: build the app, assign each new effect
to a surface, and confirm it animates. Batch demo per the sets-of-2 workflow.

Success criteria:
- Project builds (`swift build`) with the four new cases.
- Each new effect appears in the effect picker and animates smoothly.
- No regressions to existing effects.

## Out of scope

- Neon Life / cellular automata (dropped).
- The other ~10 unported reference effects (Grid Warp, Particle Mesh, Lissajous,
  Orbits, Water Ripple, Type Beat, Vector Grid, Feedback, Waveform, Checker
  Warp) — candidates for future sets.
- Any change to the picker UI, sample content, or persistence format.
