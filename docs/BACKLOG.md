# Lumora — Build Backlog

Requirements captured for future sessions.

## Effects — DONE ✅

All 20 previously-planned effects are now implemented (2026-07-06), plus a new
`grid` alignment effect used as the new-surface default, plus `prismFalls`
(continuous multi-colour spectrum waterfall) and `liquidSlosh` (confined-box
tank-slosh liquid) added 2026-07-06, plus 4 generative fractals
(`fractalTree`, `barnsleyFern`, `kochSnowflake`, `sierpinskiTriangle` — each a
~2-min generate→hold→vanish cycle re-seeded per cycle) added 2026-07-07,
plus 4 field effects ported from the lovable-projection-effects reference
(`voronoi`, `metaballs`, `hexGrid`, `flowField` — grouped in a new
`fieldEffects` builder) added 2026-07-09, plus 4 geometry effects from the same
reference (`lissajous`, `orbits`, `vectorGrid`, `particleMesh` — grouped in a
new `geometryEffects` builder) added 2026-07-10, plus 2 original ambient/illusion
effects (`livingTexture` glowing nebula flow-field ribbons, `depthBreaker`
trompe-l'œil perspective well with floating shapes + fake shadows — grouped in a
new `ambientEffects` builder; both use fixed cinematic palettes and blur-layer
glow) added 2026-07-10, plus `outlineGlow` (a running light that traces the
chosen surface's true outline — quad/polygon/ellipse — accumulating a glow then
breathing; introduced the `EffectOutline` plumbing so effects can read the
surface shape, and a new `edgeEffects` builder) added 2026-07-10.
Total: **58 effects**.
They follow the `EffectKind` (`LumoraKit`) + `EffectView`
(`Sources/Lumora/Views/SurfaceContentView.swift`) pattern: a `Canvas`/gradient
driven by `time`, warpable, with primary/accent color support via
`EffectKind.usesColor` / `usesAccent`.

Added effects: grid, halftoneDots, moire, truchet, concentricPolygons,
spirograph, fire, rain, lightning, bubbles, fallingLeaves, tvStatic,
crtScanlines, matrixRain, glitch, pixelDissolve, tunnel, pendulumWave,
dvdBounce, kaleidoscope, marqueeText. `marqueeText` scrolls the surface's name.

Possible polish later: these are visual approximations — `fire`, `glitch`,
`spirograph`, and `matrixRain` were kept deliberately cheap and could be
enriched. `kaleidoscope`/`fire` are the heaviest per-frame.

## Code-authored / external effects (explored 2026-07-06)

Two viable ways to add effects written in code beyond the built-in `EffectKind`
set. Both are feasible; not yet built.

- **JS / WebGL effect surfaces (`WKWebView`)** — add a `.web(URL)` media type
  backed by a `WKWebView` hosted via `NSViewRepresentable` (same pattern as
  `VideoContent`/`AVPlayerLayer`). Loads a local `.html` running HTML5 canvas /
  p5.js / three.js / WebGL / Shadertoy-style GLSL. Most literal "bake in JS".
  Caveat: warping a *live* web layer under `.projectionEffect` is unverified
  (same open question as video). Fallbacks: apply `CATransform3D` to the web
  view's layer directly, or `takeSnapshot` per frame and warp as an image
  (perfect warp but caps framerate). Needs transparent background; each web
  surface is a full browser instance (heavier than native effects).
- **Metal shader effects** — native GPU shaders via SwiftUI `.layerEffect` /
  `.colorEffect` (`ShaderLibrary`). Perfect warp (normal SwiftUI view),
  lightweight, Shadertoy-grade. Written in Metal Shading Language, not JS;
  GLSL/Shadertoy shaders port over fairly mechanically. Best route if the real
  goal is shader-style visuals rather than JS specifically.

## Image-trace media types — DONE ✅ (2026-07-07)

Two image-input media types added alongside `.image`/`.video`:
- **Laser Trace** (`.laserTrace(URL, RGBAColor, Double)`) — `CIEdges` edge
  points, a laser bar sweeps bottom→top revealing edges that persist, then
  hold/fade/repeat. Selectable color + trace speed (0.05×–4×).
- **Contour Trace** (`.contourTrace(URL, RGBAColor, Double)`) — Vision
  `VNDetectContoursRequest` contours, a single pen navigates edge-to-edge
  (nearest-neighbour walk), with polygon-simplify + dedup to tighten. Selectable
  color + trace speed.

Both are stateless `Canvas` views (`LaserTraceContent`/`ContourTraceContent`)
with edge extraction cached off-thread. Vision/CoreImage use bottom-left origin —
y is flipped to top-left. Open follow-up: **skeletonization (thinning)** for
true single-line centrelines (thick strokes still trace as boundary loops).

## Other pending features

- **Per-surface playback settings** — loop toggle, mute/volume, speed, fill mode
  (stretch / aspect-fill / aspect-fit). Straightforward panel work.
- **Projector-native output** — render projection at the projector's native
  resolution to remove aspect-fit letterboxing (precise 1:1 alignment).
- **Room photo import** — replace the blank neutral canvas backdrop with a
  captured/imported photo.
- **Video warp verification / shared player** — confirm `AVPlayerLayer` warps
  correctly under `.projectionEffect`; if not, apply `CATransform3D` to the
  player layer directly. Editor + projection currently spin up separate players
  (can drift); spec wants a shared player.
- **Save/Open polish** — currently Save always prompts for a location (no
  "current document" tracking / no ⌘S overwrite, no recent-files, no room image
  persisted — only surfaces are saved). Consider a real document model.
- **Design doc rename** — `docs/superpowers/specs/2026-07-05-spatialcanvas-design.md`
  still uses the old "SpatialCanvas" name.

## Done recently (2026-07-06)

- **Polygon (N-point) + ellipse surfaces** — `SurfaceShape` (quad / polygon /
  ellipse). Quads keep the homography warp; polygon/ellipse media fills the
  bounding box and is clipped to the outline. Shape picker + polygon Sides
  stepper (3–12) in the properties panel; N draggable vertices + whole-shape
  move on the canvas. Backward-compatible `.lumora` decoding (defaults to quad).
- **Surface rotation** — `Surface.rotation` (radians, about the shape center).
  Quads fold rotation into the homography (media rotates); polygon/ellipse
  rotate the clipped media as a unit. Canvas rotation knob (Arrow mode) + a
  Rotation slider/Reset in the panel; vertex drags are un-rotated back to base
  space so editing still works while rotated. Backward-compatible decoding.
- **Project Save/Open** — `.lumora` JSON of all surfaces via toolbar (⌘S / ⌘O).
- **Surface rename** — inline in the sidebar (double-click name or right-click →
  Rename), in addition to the properties-panel Name field.
- **Grid default** — new surfaces spawn with the `grid` alignment effect.
- **20 new effects** (see above).

## Paused — ready to build on request

- **Marker calibration & auto-surface detection** — project four corner
  fiducials, photograph the scene, import the photo, auto-detect object
  rectangles via Vision, map them through a photo→canvas homography into
  editable quad surfaces with a keep/discard review step (also delivers
  room-photo-import backdrop). Spec + full implementation plan are written and
  approved; do NOT start until the user asks to resume.
  - Spec: `docs/superpowers/specs/2026-07-11-marker-calibration-auto-surfaces-design.md`
  - Plan: `docs/superpowers/plans/2026-07-11-marker-calibration-auto-surfaces.md`
    (5 TDD tasks; execute via subagent-driven-development on a feature branch).

## Working preferences (for next session)

- Build incrementally in **verified sets of 2**; keep it compiling at each step.
- Prioritize a **quick runnable demo** (relaunch so it's visible).
- If fanning out to subagents: **complex → Opus, simpler → Sonnet**.
