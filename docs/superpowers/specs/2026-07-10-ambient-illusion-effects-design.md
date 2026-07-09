# Two ambient/illusion effects: Living Texture + Depth Breaker

**Date:** 2026-07-10
**Status:** Approved design, ready for implementation
**Follows:** the two reference-port sets (55 effects total)

## Goal

Add two original, more cinematic effects (not straight reference ports):

- **Living Texture** — glowing nebula/silk ribbons flowing through an organic
  noise field. Ambient, no sharp cuts.
- **Depth Breaker** — a trompe-l'œil "hole in the wall": a 1-point-perspective
  well with floating shapes casting fake shadows on the inner walls.

Both use **fixed cinematic palettes** (ignore the surface color pickers) and are
**stateless** (all animation from `time`).

## Architecture (same 3 touchpoints)

1. **`EffectKind`** (`Sources/LumoraKit/EffectKind.swift`) — append `livingTexture`
   and `depthBreaker` after `particleMesh`. Both added to the `usesColor`
   false-list; neither added to `usesAccent` (both default false). `displayName`:
   "Living Texture", "Depth Breaker".
2. **`EffectView.body`** dispatch — new arm `case .livingTexture, .depthBreaker: ambientEffects`.
3. **New `ambientEffects` ViewBuilder** in `SurfaceContentView.swift`, alongside
   `fieldEffects`/`geometryEffects`, each case a `Canvas { ctx, size in draw…(ctx:size:) }`
   calling a private helper. Split any helper that trips the Swift type-checker
   into sub-functions (as prior sets did).

## New Canvas techniques (not yet used in this file, but standard SwiftUI)

- **Blur filter layer** for glow / soft shadow:
  `ctx.drawLayer { var l = $0; l.addFilter(.blur(radius: r)); l.stroke(...) }`
  (the closure receives an inout-style child context; use its `addFilter`).
- **Additive blend** for glow accumulation: set `layer.blendMode = .plusLighter`
  on the glow layer.
Both are `GraphicsContext` APIs. If a specific call shape doesn't compile, fall
back to layered semi-transparent strokes without blur (still reads as glow via
`.plusLighter`), but prefer real blur.

## Living Texture (`livingTexture`)

Fixed palette: background deep violet-black (~`#08000f`); ribbon colors cycle
through magenta (`#ff2d95`) → cyan (`#22e0ff`) → violet (`#8a2be2`).

- **Flow field (fBm curl):** angle at point (x,y) and time t =
  `θ = (sin(x·0.004 + t·0.3) + sin(y·0.005 − t·0.23) + 0.5·sin((x+y)·0.003 + t·0.4)) · π`.
  Smooth, organic, multi-octave. (Cheap fBm-ish; no true Perlin needed.)
- **Ribbons:** ~50 ribbons. Ribbon k seeded from index hashes
  (`fract(sin(k·multiplier)·43758.5)`) for start x/y and a color-phase. Build a
  ~40-point polyline by integrating the field (`step ≈ 5pt`). Animate/recycle by
  offsetting the integration start by `fract(t·0.05 + seed)·(fieldPeriod)` so
  ribbons drift and continuously renew without state.
- **Draw:** fill background first. Then, inside a blur layer
  (`radius ≈ 6`, `blendMode = .plusLighter`), stroke each ribbon fat
  (`~7pt`, opacity ~0.35) for glow; then stroke a thin bright core (`~1.5pt`,
  opacity ~0.9) at full clarity. Round line caps/joins. Ribbon color = lerp
  across the palette by `fract(colorPhase + t·0.03)`. Overall ambient, soft.

## Depth Breaker (`depthBreaker`)

Fixed palette: near-black interior (`#05060a`), neon cyan/magenta grid + edges,
warm shape highlights.

- **Well geometry (1-point perspective):** vanishing point `vp` at surface
  center (optionally biased for forced perspective — keep at center for v1).
  Outer rect = full surface bounds inset slightly. Inner (back-wall) rect =
  outer scaled ~0.42 toward `vp`. Four trapezoids (top/bottom/left/right) connect
  outer→inner = receding walls. Fill each wall with a depth gradient (front edge
  brighter → back edge near-black). Draw a neon grid: concentric rectangles
  interpolated outer→inner (depth rings) + lines from outer corners to inner
  corners, cyan, faint.
- **Floating shapes:** 3 shapes with 3D coord `(sx, sy, z)` where `sx,sy` are
  −1…1 within the well cross-section and `z` 0 (front) … 1 (back). Project:
  `depthScale = 1 − z·0.55`; `p = lerp(vp, wellPointAt(sx,sy), depthScale)` mapped
  so nearer shapes are larger and closer to the outer rect. Drift: `sx,sy,z` via
  `sin/cos(t·speed + phase)` per shape.
  - 2 **spheres**: radial-gradient disc (bright warm/neon core → edge), radius ∝
    depthScale.
  - 1 **torus**: a tilted ring — stroke an ellipse (wide, short) with a thick
    neon line, plus a thinner inner ellipse for the hole; radius ∝ depthScale.
- **Fake shadows:** for each shape, draw first (behind shapes) a **blurred dark
  ellipse** on the back-wall plane at the shape's `(sx,sy)` projected to `z=1`,
  offset by a fixed light direction (e.g. down-right), opacity ∝ how close the
  shape is to the back wall. Blur layer, `radius ≈ 8`.
- **Draw order:** background/walls → wall grid → shadows → shapes sorted back-to-front by z.

## Testing / verification

`swift build` clean after each effect. Assign each to a surface in the running
app; confirm smooth ambient motion, visible glow (Living Texture), and a
readable 3D well with shadows (Depth Breaker). No regressions. Demo the set.

## Out of scope

- Respecting surface color/accent (deliberately fixed palettes).
- Forced-perspective VP calibration UI (VP stays centered in v1).
- Remaining reference effects (Grid Warp, Water Ripple, Type Beat, Waveform,
  Checker Warp, Feedback Zoom).
