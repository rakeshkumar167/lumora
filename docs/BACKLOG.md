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
surface shape, and a new `edgeEffects` builder) added 2026-07-10, plus a
**Christmas Lights** set (new `.christmas` category + `christmasEffects` group)
added 2026-07-11: `christmasTree` (bundled tree image with twinkle glints
confined to an on-tree luminance+saturation+silhouette mask —
`ChristmasTreeAsset`), and four single sagging-strand string lights `chasingLights`,
`multiColorLights`, `twinklingLights`, `warmBulbs` (shared
`ChristmasLights.strands(in:)` geometry in LumoraKit; bulbs drawn as capped oval
mini-lights or round warm globes with glow + highlight; fixed festive palette /
warm amber; no user color config).
Total: **63 effects**.
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
- **Contour Trace** (`.contourTrace([URL], RGBAColor, Double, Bool)`) — Vision
  `VNDetectContoursRequest` contours, a single pen navigates edge-to-edge
  (nearest-neighbour walk), with polygon-simplify + dedup to tighten. Selectable
  color + trace speed. **Updated 2026-07-11:** now takes *multiple images* —
  each image's contour walk is concatenated and traced one after another,
  overlaying the previous and staying lit (build-up), then hold/fade/repeat; and
  a **Rainbow** option colors the trace by arc-length position across the whole
  walk in ~24 gradient bands (one spectrum pass, gentle drift) via the pure,
  unit-tested `ContourTrace` helper in LumoraKit. Params now live in a
  `ContourTraceConfig` struct with a user-editable **hold duration** (default
  30s, how long the finished trace stays before fade+repeat) and a **Keep on
  after trace** toggle (trace once, then stay on permanently). Compat caveat:
  projects saved before these changes that contain a Contour Trace surface won't
  reopen (the case payload shape changed; other media unaffected).

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

## Done recently (2026-07-12)

- **Effect roster changes** — removed `crtScanlines` and `moire`. Added
  **Game of Life** (`gameOfLife`, Ambient category): Conway's Life driven from
  the clock, ~20 seeded soups, rainbow hue advancing per generation, panel
  controls for speed (gen/s) and cell size; rules/seeding are pure LumoraKit
  (`GameOfLife`) and unit-tested. Tunings: metaballs de-pixelated (blur +
  alphaThreshold gooey), voronoi rebuilt as vector cells via half-plane
  clipping (crisp + cheap), kaleidoscope now a dense 12-fold rainbow mandala,
  equalizer bars randomized (layered per-bar frequencies + beat), fireworks
  gained a rare ~2× **mega** burst tier with detailed comet trails, and Falling
  Leaves uses a maple-leaf shape. Per-effect configs (marquee/christmas/GoL)
  are stored as optional structs on `Surface` with tolerant decode.
- **Auto surface detection** — a **Detect Surfaces** toolbar button imports a
  room photo and proposes large flat quad surfaces via a hybrid, plane-first
  detector: gradient-barrier region segmentation for walls/planes plus Vision
  `VNDetectRectanglesRequest` for objects (screens, doors, panels). Candidates
  are clamped to the frame, filtered by minimum area (the "skip small" knob),
  fill ratio, and rectangularity, then de-duplicated and ranked planes-first.
  A keep/discard review sheet (`SurfaceDetectionReviewView`) overlays the quads
  on the photo; kept quads become ordinary editable surfaces via
  `ProjectStore.addDetectedSurfaces`. Pure geometry + ranking live in
  `LumoraKit/SurfaceDetection/` (unit-tested); the detector is validated against
  the five bundled `Resources/surface-detection` samples. No backdrop, no
  fiducials, no homography. Spec/plan: `docs/superpowers/{specs,plans}/2026-07-12-auto-surface-detection*`.

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

## Superseded

- **Marker calibration & auto-surface detection (fiducial approach)** —
  **superseded** on 2026-07-12 by the shipped hybrid detector below. A research
  spike showed Vision rectangle detection only finds bordered objects and is
  blind to blank walls, so the fiducial/homography route was dropped in favor of
  a photo-import hybrid (region planes + Vision objects). Old docs kept for
  reference: `docs/superpowers/specs/2026-07-11-marker-calibration-auto-surfaces-design.md`,
  `docs/superpowers/plans/2026-07-11-marker-calibration-auto-surfaces.md`.

## Auto surface detection follow-ups

- **Plane-fit quality** — region segmentation still emits some loose/skewed
  wall+floor quads on near-uniform cream rooms (soft wall/floor seam). Review
  discards them, but a horizon/seam split or an inscribed-rectangle fit would
  raise auto quality. Thresholds live in `SurfaceDetector.Options`
  (`gradientBarrier`, `minFillRatio`, `minRectangularity`, `ranker`).

## Working preferences (for next session)

- Build incrementally in **verified sets of 2**; keep it compiling at each step.
- Prioritize a **quick runnable demo** (relaunch so it's visible).
- If fanning out to subagents: **complex → Opus, simpler → Sonnet**.
