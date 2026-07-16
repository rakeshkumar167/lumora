# Port 19 CodePen three.js effects into Lumora

**Date:** 2026-07-17
**Status:** Approved (design), pending implementation plan

## Goal

Port all 19 extracted CodePen three.js effects in `../lumora-ref/codepen-tabs/`
into Lumora as bundled WebGL effects, reusing the existing `WebEffectContent`
(WKWebView) framework. Remove all mouse-/scroll-driven *interactive* rendering:
effects must self-animate as ambient motion with no live input. Strip all
text/DOM chrome so each effect is a clean, full-bleed canvas.

## Non-goals

- No new native rendering mechanism — extend the existing Web layer only.
- No global-clock or audio bridge (those remain the backlog items from
  `2026-07-16-webgl-wkwebview-design.md`).
- No user color/accent config for these effects (`usesColor`/`usesAccent` =
  false, matching the existing web effects).

## Key decisions (confirmed with user)

1. **One shared modern three**, pinned to **three 0.167** — the highest version
   any pen needs, so every ES-module pen's addons resolve against it. Pens
   authored for older versions are adapted to 0.167.
2. **Auto-drive** all 5 pointer-*is*-the-effect pens (Group 2) via a synthetic
   motion source; simply remove the listener (centered / autoRotate) for the 7
   parallax-only pens (Group 1).
3. **Strip all text/DOM chrome** from every pen (titles, credit/attribution
   links, `dat.gui`, scroll labels, Framer links, the CodePen
   `stopExecutionOnTimeout` shim).
4. **Prebuilt-package pens** (Liquid Effect, Tubes Cursor) bundle their own
   three and are vendored as-is — they do not use the shared build.

## Architecture

All work lives under `Sources/Lumora/Web/` plus small registration edits in
`LumoraKit/EffectKind.swift`, `Views/WebEffectContent.swift`, and
`Views/SurfaceContentView.swift`. No change to how `WKWebView` is hosted or
perspective-warped.

### Shared vendored three (0.167)

- Vendored at `Web/lib/three/three.module.js` and `Web/lib/three/addons/…`
  (only the addons actually used, listed per-effect below).
- Each page declares a native **importmap** so `import * as THREE from 'three'`
  and `import … from 'three/addons/…'` resolve to the local files:

  ```html
  <script type="importmap">
  { "imports": {
      "three": "./lib/three/three.module.js",
      "three/addons/": "./lib/three/addons/"
  } }
  </script>
  ```

  WebKit supports importmaps natively, so the `es-module-shims` shim used by
  some pens is dropped.
- **Dev-time vendoring only.** Fetching three/addons from a CDN during
  implementation is fine; the runtime app must load everything from `file://`
  (no CDN), matching the existing framework's rule.

### Global-`THREE` pens

Water (r77), the 4 shubniggurath pens (r88), Space Globe (r121), Zooming
Spiral + Morphing Ball (r128) were authored against a script-tag global. Each
is wrapped with a module preamble that exposes the shared module as the global:

```html
<script type="module">
  import * as THREE from 'three';
  window.THREE = THREE;
  // …addon globals if needed, e.g. window.OrbitControls = …
</script>
```

then their (adapted) body script runs. Per-version API deltas are fixed
per-effect: e.g. `THREE.Geometry` → `BufferGeometry`, `THREE.Math` →
`THREE.MathUtils`, removed helpers like `AxisHelper`, and examples-globals such
as `THREE.EffectComposer` → explicit addon imports assigned onto `THREE`/window.

### Non-three dependencies

Vendored locally as needed:
- `gsap@3` — Morphing Ball, On-Scroll Fire.
- `simplex-noise` — Space Globe (2.4-era API), Particle-Animation (newer API).
- `anime.js` — Particle-Animation.

Dropped entirely:
- `dat.gui` — ShockWave's tweak panel (effect kept, panel removed).
- `jQuery` — Water shader (~3 calls inlined to vanilla JS).
- CodePen `stopExecutionOnTimeout` shim — all pens.

### Background / transparency

Prefer a transparent renderer clear (`alpha: true`, clear alpha 0) where the
effect reads correctly over transparency, matching the existing web effects.
Where a pen depends on its dark backdrop for additive glow, keep that dark
background — all 19 are light-on-dark, so a projector shows only the bright
parts either way.

### Auto-drive helper

`Web/lib/autopilot.js` — a shared module that synthesizes, from
`performance.now()`, an ambient input signal:
- a slowly-wandering normalized pointer `{x, y}` in `[-1, 1]` following a slow
  Lissajous/curl path, and
- a looping `progress` in `[0, 1]` (for scroll-driven pens).

Group-2 pens import it and read `pointer`/`progress` in place of real
mouse/scroll events. The path is slow and smooth so motion reads as intentional
ambient animation, not a jittering cursor.

### Chrome stripping

Every ported page reduces to: `<head>` (charset, minimal full-bleed CSS,
importmap, vendored `<script>`s) + a single canvas + the effect script. All
headings, captions, credit/attribution anchors, control panels, and layout
`<div>`s (e.g. `.scroll-space`, "Fire Scroll", Framer links) are removed.

## Effect catalog (19)

| # | Title | `EffectKind` | three source | Addons / libs | Interaction treatment |
|---|---|---|---|---|---|
| 1 | Zooming Spiral | `webZoomingSpiral` | r128 → shared | — | none |
| 2 | Space Globe | `webSpaceGlobe` | r121 → shared | OrbitControls (removed), simplex-noise | none |
| 3 | Water Shader | `webWaterShader` | r77 → shared | drop jQuery | none |
| 4 | Morphing Ball | `webMorphingBall` | r128 → shared | gsap | none |
| 5 | Snowfall | `webSnowfall` | r88 → shared | — | G1: remove → gentle auto-sway |
| 6 | Starfall | `webStarfall` | r88 → shared | — | G1: `u_mouse` centered, no click |
| 7 | Coral Blooms | `webCoralBlooms` | r88 → shared | — | G1: centered offset |
| 8 | Storm | `webStorm` | r88 → shared | — | G1: remove mouse + scroll |
| 9 | Live Clouds | `webLiveClouds` | shared | BufferGeometryUtils | G1: remove → slow auto-drift |
| 10 | Disco Balls | `webDiscoBalls` | shared | OrbitControls, BufferGeometryUtils | G1: `autoRotate` |
| 11 | Black Hole | `webBlackHole` | shared | OrbitControls | G1: `autoRotate` |
| 12 | Particle Teapot | `webParticleTeapot` | shared | TeapotGeometry, EffectComposer, RenderPass, UnrealBloomPass, ShaderPass, RGBShiftShader, FilmPass, OrbitControls | none |
| 13 | Particle-Animation | `webParticleAnim` | shared | EffectComposer, RenderPass, UnrealBloomPass, OrbitControls, anime.js, simplex-noise | none |
| 14 | ShockWave | `webShockwave` | shared | EffectComposer, RenderPass, ShaderPass, UnrealBloomPass, OrbitControls; drop dat.gui | **G2: auto-emit ripples** |
| 15 | Draw WebGL Flowers | `webFlowers` | shared | — | **G2: auto-drive pointer** |
| 16 | On-Scroll Fire | `webFire` | shared | gsap (+ScrollTrigger removed) | **G2: auto-loop scroll progress** |
| 17 | Pacman Concept | `webPacman` | shared | EffectComposer, RenderPass + shader passes | **G2: auto-drive path** |
| 18 | Liquid Effect | `webLiquid` | **prebuilt pkg** | `threejs-components` liquid1 (own three) | none |
| 19 | Tubes Cursor | `webTubes` | **prebuilt pkg** | `threejs-components` tubes1 (own three) | **G2: auto-drive cursor** |

Source folders map by `../lumora-ref/codepen-tabs/index.json` (`folder` field).

## Registration

For each of the 19:
- Add an `EffectKind` case (see table). All are `usesColor = false`,
  `usesAccent = false`, `category = .webGL`, `supportsAudio = false`.
- `displayName` = the pen title from the catalog.
- Map the case → its page base name in `WebEffect.resource(for:)`.
- Add the case to the `.webGL` branch in `SurfaceContentView` that routes to
  `webEffects`.

The "WebGL & Shaders" category grows from 3 to 22 effects. No category
reorganization in this spec.

## Verification

- Reuse `scripts/verify_web_effect.swift` + the offscreen `ImageRenderer`
  pattern (see memory: effect rendering notes). Each page must render a
  non-blank frame.
- Manual demo per batch: launch the packaged `.app`, select the effect,
  confirm it animates with no live input and no visible text/chrome.

## Delivery plan

Implement in **batches of 2** (standing preference: incremental sets of 2 +
quick demo), roughly in catalog order (simplest globals first, then the r88
set, then ES-module/postprocessing, then the auto-drive Group 2, then the two
prebuilt packages). The framework changes (shared three vendoring, importmap
convention, `autopilot.js`) land with the first batch.

## Risks

- **Per-version API adaptation** (r77/r88/r121 → 0.167) may cause subtle visual
  drift or require shader/material fixes per effect. Accepted trade-off for a
  lean app with one shared three.
- **Prebuilt packages** (#18, #19) are opaque bundles; if a bundle can't be
  vendored offline or resists the auto-drive cursor, that effect may be dropped
  — flag during its batch rather than blocking the rest.
- **Postprocessing-heavy pens** (#12–14, #17) pull many addons; verify bundle
  size stays reasonable and 60fps holds on the projection path.
