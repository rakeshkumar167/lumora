# CodePen three.js Effects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port all 19 extracted CodePen three.js effects into Lumora as bundled, self-animating WebGL effects with no live mouse/scroll input and no on-screen text/chrome.

**Architecture:** Reuse the existing `WebEffectContent` (WKWebView) framework. Vendor a single shared `three@0.167` module build + only the addons each pen needs, loaded via a native importmap from `file://`. Pens authored for older three or for the script-tag global are adapted to 0.167. The 5 pens whose pointer *is* the effect are driven by a shared synthetic `autopilot.js`; the 7 parallax-only pens have their listeners removed. Two prebuilt-package pens are vendored as-is.

**Tech Stack:** Swift (LumoraKit + SwiftUI/WebKit app layer), three.js 0.167 (ES modules + addons), gsap@3, simplex-noise, anime.js, WKWebView.

**Spec:** `docs/superpowers/specs/2026-07-17-codepen-threejs-effects-design.md`

## Global Constraints

- **Single shared three version: `0.167`.** Every ES-module pen resolves `"three"` and `"three/addons/"` against the local vendored 0.167 build. Older pens are adapted to it.
- **No CDN at runtime.** All JS loads from `file://` under `Sources/Lumora/Web/`. Fetching libs from a CDN *during implementation* (to vendor them) is fine.
- **ESM loading uses a custom URL scheme, NOT file://.** Bundled effect pages are served over `lumora-effect://local/<name>.html` via a `WKURLSchemeHandler` (Task 1), giving pages a real origin so sibling-module `import` works with the WKWebView sandbox fully intact. Do NOT use `allowUniversalAccessFromFileURLs`/`allowFileAccessFromFileURLs` (user decision: keep the sandbox). The handler serves only files resolved within the bundled `Web/` directory (reject `..` traversal), with correct MIME types (`.js`/`.mjs` → `text/javascript`, `.html` → `text/html`). Both `WebEffectContent.swift` and `scripts/verify_web_effect.swift` load via this scheme. Runtime CDN-avoidance is enforced by the offline verify.
- **No live input.** Remove every `mousemove`/`pointermove`/`pointerdown`/`wheel`/`scroll`/`ScrollTrigger`/`OrbitControls`-drag path. Group-1 pens: remove listener (center the value, add `autoRotate`/auto-drift where it was the only motion). Group-2 pens: feed `autopilot.js` in place of real input.
- **No text/DOM chrome.** Each page reduces to `<head>` (charset, full-bleed CSS, importmap, vendored `<script>`s) + one `<canvas>` + the effect script. Remove all headings, captions, credit/attribution links, `dat.gui`, layout divs (`.scroll-space`, "Fire Scroll", Framer links), and the CodePen `stopExecutionOnTimeout` `<script>`.
- **No color config.** Every new `EffectKind` is `usesColor = false`, `usesAccent = false`, `supportsAudio = false`, `category = .webGL`.
- **Prefer transparent clear** (`WebGLRenderer({ alpha: true })`, clear alpha 0) where the effect reads over transparency; otherwise keep the pen's dark background.
- **Verify every page** with `swift scripts/verify_web_effect.swift <basename>` — it must render non-blank AND animate (frames differ over time).
- Source folders are listed in `../lumora-ref/codepen-tabs/index.json` (`folder` field). **Read the pen's `index.html` before porting it.**

---

## Shared Procedure A — Porting Recipe

Every effect task (Tasks 2–20) performs these steps to produce `Sources/Lumora/Web/<basename>.html`. The task's own notes give the source folder, three-version deltas, addons to vendor, and input treatment.

1. **Read** `<source-folder>/index.html` in full.
2. **Create** `Sources/Lumora/Web/<basename>.html` from the template below, keeping only the effect's own `<script>` body and its canvas.
3. **Head/boilerplate** — use exactly:

   ```html
   <!DOCTYPE html>
   <html>
   <head>
   <meta charset="utf-8">
   <title><Effect Title></title>
   <style>
     html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: transparent; overflow: hidden; }
     canvas { display: block; width: 100vw; height: 100vh; }
   </style>
   <script type="importmap">
   { "imports": {
       "three": "./lib/three/three.module.js",
       "three/addons/": "./lib/three/addons/"
   } }
   </script>
   </head>
   <body>
   <!-- effect script(s) here -->
   </body>
   </html>
   ```

4. **Module vs global:**
   - ES-module pen → keep `<script type="module">` and its `import … from 'three'` / `'three/addons/…'` lines (importmap resolves them). Remove `es-module-shims`.
   - Global-`THREE` pen (script-tag) → wrap its body in `<script type="module">`, prepend:
     ```js
     import * as THREE from 'three';
     window.THREE = THREE;
     ```
     and for any examples-globals it uses (e.g. `OrbitControls`, `EffectComposer`), add the matching addon import and assign onto `window`/`THREE` (e.g. `import { OrbitControls } from 'three/addons/controls/OrbitControls.js'; window.OrbitControls = OrbitControls;`).
5. **API deltas** — fix removed/renamed APIs for the pen's original version (common: `THREE.Geometry`→`THREE.BufferGeometry`, `THREE.Math`→`THREE.MathUtils`, `THREE.AxisHelper` removed, `Face3`/`geometry.vertices` gone, `.flatShading` now a material flag). Fix until it renders.
6. **Strip chrome** — delete all non-canvas DOM and the `stopExecutionOnTimeout` script.
7. **Input treatment** — apply the per-task treatment (remove listener / `autoRotate` / `autopilot`).
8. **Transparent clear** — set `renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true })` and `renderer.setClearColor(0x000000, 0)` unless the task says keep the dark bg.
9. **Vendor addons** — for each `three/addons/…` the page imports, ensure the file exists under `Web/lib/three/addons/…` (see Task 1's vendoring step; add any missing addon by copying from the 0.167 distribution — resolve its relative imports to sibling addon files).
10. **Verify:** `swift scripts/verify_web_effect.swift <basename>` → expect `PASS` (non-blank + animates).

## Shared Procedure B — Registration Recipe

For each effect, register it in Swift (all edits are additive to existing switch/case lists):

1. `Sources/LumoraKit/EffectKind.swift`
   - Add `case <caseName>` in the web block (after line 97, alongside `webFlow`).
   - Add `.<caseName>` to the `usesColor` false-list (line ~112, the `.webPlasma, .webParticles3D, .webFlow:` case).
   - Add `case .<caseName>: return "<Display Title>"` in `displayName` (near line 238).
   - Add `.<caseName>` to the `.webGL` category case (line ~279).
2. `Sources/Lumora/Views/WebEffectContent.swift`
   - Add `case .<caseName>: return "<basename>"` in `WebEffect.resource(for:)`.
3. `Sources/Lumora/Views/SurfaceContentView.swift`
   - Add `.<caseName>` to the web routing case (line ~1142, `case .webPlasma, .webParticles3D, .webFlow:`).
4. Build: `swift build` → expect success (exhaustive-switch errors mean a spot was missed).

---

### Task 1: Framework foundation — shared three, addons, autopilot, template

**Files:**
- Create: `Sources/Lumora/Web/lib/three/three.module.js`
- Create: `Sources/Lumora/Web/lib/three/addons/` (populated as effects need them)
- Create: `Sources/Lumora/Web/lib/autopilot.js`
- Create: `Sources/Lumora/Web/_smoketest.html`
- Reference: `scripts/verify_web_effect.swift`

**Interfaces:**
- Produces: importmap keys `"three"` → `./lib/three/three.module.js`, `"three/addons/"` → `./lib/three/addons/`; global module `autopilot.js` exporting `{ pointer, progress, update() }`.

- [ ] **Step 1: Vendor three 0.167 (module build)**

Download the module build and place it locally (dev-time CDN fetch is allowed):

```bash
mkdir -p Sources/Lumora/Web/lib/three/addons
curl -L -o Sources/Lumora/Web/lib/three/three.module.js \
  https://cdn.jsdelivr.net/npm/three@0.167.0/build/three.module.js
```

Expected: file is ~1.2 MB, starts with a license comment / ES-module exports.

- [ ] **Step 2: Add the autopilot helper**

Create `Sources/Lumora/Web/lib/autopilot.js`:

```js
// Synthetic ambient input for effects whose pointer/scroll IS the effect.
// Replaces live mouse/scroll with a slow, smooth wandering signal derived
// from performance.now(), so ported CodePen effects self-animate.
const state = {
  // Normalized pointer in [-1, 1] (screen-centered).
  pointer: { x: 0, y: 0 },
  // Normalized pointer in [0, 1] (top-left origin), for pens that expect that.
  pointer01: { x: 0.5, y: 0.5 },
  // Looping progress in [0, 1] for scroll-driven pens.
  progress: 0,
};

function update(nowMs) {
  const t = (nowMs ?? performance.now()) / 1000;
  // Slow Lissajous wander — irrational frequency ratio so it never repeats.
  const x = Math.sin(t * 0.11) * 0.6 + Math.sin(t * 0.037) * 0.3;
  const y = Math.cos(t * 0.09) * 0.6 + Math.cos(t * 0.041) * 0.3;
  state.pointer.x = Math.max(-1, Math.min(1, x));
  state.pointer.y = Math.max(-1, Math.min(1, y));
  state.pointer01.x = state.pointer.x * 0.5 + 0.5;
  state.pointer01.y = state.pointer.y * 0.5 + 0.5;
  // 0→1 ramp over ~24s, then smooth loop.
  const phase = (t / 24) % 1;
  state.progress = 0.5 - 0.5 * Math.cos(phase * Math.PI * 2);
  return state;
}

export const pointer = state.pointer;
export const pointer01 = state.pointer01;
export function getProgress() { return state.progress; }
export { update, state };
export default state;
```

- [ ] **Step 3: Create a smoke-test page proving the importmap + shared three**

Create `Sources/Lumora/Web/_smoketest.html`:

```html
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Smoke Test</title>
<style>
  html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: transparent; overflow: hidden; }
  canvas { display: block; width: 100vw; height: 100vh; }
</style>
<script type="importmap">
{ "imports": {
    "three": "./lib/three/three.module.js",
    "three/addons/": "./lib/three/addons/"
} }
</script>
</head>
<body>
<script type="module">
import * as THREE from 'three';
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(60, 1, 0.1, 100);
camera.position.z = 4;
const renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true });
renderer.setClearColor(0x000000, 0);
document.body.appendChild(renderer.domElement);
const mesh = new THREE.Mesh(
  new THREE.IcosahedronGeometry(1, 1),
  new THREE.MeshBasicMaterial({ color: 0x40e0d0, wireframe: true })
);
scene.add(mesh);
function resize() {
  const w = window.innerWidth, h = window.innerHeight;
  renderer.setPixelRatio(window.devicePixelRatio || 1);
  renderer.setSize(w, h);
  camera.aspect = w / h; camera.updateProjectionMatrix();
}
resize();
const start = performance.now();
(function loop() {
  const t = (performance.now() - start) / 1000;
  mesh.rotation.y = t * 0.8; mesh.rotation.x = t * 0.4;
  renderer.render(scene, camera);
  requestAnimationFrame(loop);
})();
</script>
</body>
</html>
```

- [ ] **Step 3b: Serve effect pages over a custom URL scheme (`lumora-effect://`)**

WKWebView denies sibling ES-module `import` from a `loadFileURL` page as cross-origin (blank render). Instead of weakening the sandbox, register a `WKURLSchemeHandler` that serves the bundled `Web/` directory over `lumora-effect://local/…`, and load `lumora-effect://local/<name>.html`. Requirements: resolve the URL path within the bundled `Web/` dir only (reject `..`), return correct MIME (`.js`/`.mjs` → `text/javascript`, `.html` → `text/html`), 404 for missing files. Apply in BOTH `Sources/Lumora/Views/WebEffectContent.swift` (production loader) and `scripts/verify_web_effect.swift` (may inline its own copy, since standalone scripts can't import the app module). Do NOT set any `allow*AccessFromFileURLs` flag.

- [ ] **Step 4: Verify the foundation renders**

Run: `swift scripts/verify_web_effect.swift _smoketest`
Expected: `PASS` — non-blank and animates. Then `swift build` must still succeed.

- [ ] **Step 5: Commit**

```bash
git add Sources/Lumora/Web/lib Sources/Lumora/Web/_smoketest.html
git commit -m "feat(web): shared three 0.167 + importmap + autopilot foundation"
```

---

### Task 2: Zooming Spiral (`webZoomingSpiral`)

**Files:**
- Create: `Sources/Lumora/Web/zoomingSpiral.html`
- Modify: `EffectKind.swift`, `WebEffectContent.swift`, `SurfaceContentView.swift`
- Source: `../lumora-ref/codepen-tabs/Nidal95_vEObXOz/index.html` (three r128 global)

**Interfaces:**
- Produces: `EffectKind.webZoomingSpiral`, resource `"zoomingSpiral"`.

- [ ] **Step 1:** Port per **Shared Procedure A**. Global-`THREE` pen (r128) → module preamble. No input to remove (no mouse). Transparent clear.
- [ ] **Step 2:** Verify: `swift scripts/verify_web_effect.swift zoomingSpiral` → `PASS`.
- [ ] **Step 3:** Register per **Shared Procedure B** with caseName `webZoomingSpiral`, display `"Zooming Spiral"`, basename `zoomingSpiral`. Build.
- [ ] **Step 4:** Commit: `git commit -am "feat(web): Zooming Spiral effect"`.

---

### Task 3: Space Globe (`webSpaceGlobe`)

**Files:**
- Create: `Sources/Lumora/Web/spaceGlobe.html`
- Modify: the three registration files
- Source: `../lumora-ref/codepen-tabs/isladjan_bGpjZwN/index.html` (three r121 global + OrbitControls + simplex-noise 2.4)

- [ ] **Step 1:** Vendor `simplex-noise` locally: `curl -L -o Sources/Lumora/Web/lib/simplex-noise.js https://cdn.jsdelivr.net/npm/simplex-noise@2.4.0/simplex-noise.js` and reference it via a plain `<script>` (it exposes `SimplexNoise` global) *before* the module script, or import it. Confirm the pen's `new SimplexNoise()` usage matches 2.4 API.
- [ ] **Step 2:** Port per **Shared Procedure A**. Global-r121 → module preamble. **Remove OrbitControls** (no drag); if the globe only rotated via controls, add `mesh.rotation.y += 0.002` per frame. Transparent clear.
- [ ] **Step 3:** Verify: `swift scripts/verify_web_effect.swift spaceGlobe` → `PASS`.
- [ ] **Step 4:** Register (`webSpaceGlobe`, `"Space Globe"`, `spaceGlobe`). Build.
- [ ] **Step 5:** Commit: `git commit -am "feat(web): Space Globe effect"`.

---

### Task 4: Water Shader (`webWaterShader`)

**Files:**
- Create: `Sources/Lumora/Web/waterShader.html`
- Source: `../lumora-ref/codepen-tabs/knoland_XKxrJb/index.html` (three **r77** global + jQuery)

- [ ] **Step 1:** Port per **Shared Procedure A**. Global-r77 → module preamble. Expect **significant API deltas** (r77→0.167): replace `THREE.AxisHelper` (remove it), any `THREE.Geometry`/`vertices`/`Face3` with `BufferGeometry`, `THREE.Math`→`THREE.MathUtils`. **Drop jQuery** — replace its ~3 calls (likely `$(window).resize`, `$(document).ready`, appending the canvas) with vanilla `window.addEventListener('resize', …)` / direct DOM.
- [ ] **Step 2:** Verify: `swift scripts/verify_web_effect.swift waterShader` → `PASS`. (If the shader relies on r77 built-in uniforms that changed, adjust the `ShaderMaterial` uniform declarations.)
- [ ] **Step 3:** Register (`webWaterShader`, `"Water Shader"`, `waterShader`). Build.
- [ ] **Step 4:** Commit: `git commit -am "feat(web): Water Shader effect"`.

---

### Task 5: Morphing Ball (`webMorphingBall`)

**Files:**
- Create: `Sources/Lumora/Web/morphingBall.html`
- Source: `../lumora-ref/codepen-tabs/daniel-hult_QWqvxvp/index.html` (three r128 global + gsap@3)

- [ ] **Step 1:** Vendor gsap: `curl -L -o Sources/Lumora/Web/lib/gsap.min.js https://cdn.jsdelivr.net/npm/gsap@3/dist/gsap.min.js`. Reference via `<script src="lib/gsap.min.js"></script>` (exposes `gsap` global) before the module script.
- [ ] **Step 2:** Port per **Shared Procedure A**. Global-r128 → module preamble. No mouse. gsap tweens drive the morph autonomously — keep them. Transparent clear.
- [ ] **Step 3:** Verify: `swift scripts/verify_web_effect.swift morphingBall` → `PASS`.
- [ ] **Step 4:** Register (`webMorphingBall`, `"Morphing Ball"`, `morphingBall`). Build.
- [ ] **Step 5:** Commit: `git commit -am "feat(web): Morphing Ball effect"`.

---

### Task 6: Snowfall (`webSnowfall`)

**Files:**
- Create: `Sources/Lumora/Web/snowfall.html`
- Source: `../lumora-ref/codepen-tabs/shubniggurath_WgJZJo/index.html` (three **r88** global)

- [ ] **Step 1:** Port per **Shared Procedure A**. Global-r88 → module preamble; fix r88→0.167 deltas. **Group 1:** delete the `pointermove`/`mouse.*` handler; where the snow parallax read `mouse.x/y`, replace with a slow constant drift (e.g. `const mouse = { x: Math.sin(t*0.05)*0.1, y: 0 }`).
- [ ] **Step 2:** Verify: `swift scripts/verify_web_effect.swift snowfall` → `PASS`.
- [ ] **Step 3:** Register (`webSnowfall`, `"Snowfall"`, `snowfall`). Build.
- [ ] **Step 4:** Commit: `git commit -am "feat(web): Snowfall effect"`.

---

### Task 7: Starfall (`webStarfall`)

**Files:**
- Create: `Sources/Lumora/Web/starfall.html`
- Source: `../lumora-ref/codepen-tabs/shubniggurath_QVrJjM/index.html` (three **r88** global; `u_mouse` uniform)

- [ ] **Step 1:** Port per **Shared Procedure A**. Global-r88 → module preamble. **Group 1:** delete the `pointermove`/`pointerdown`/`pointerup` handlers; keep `uniforms.u_mouse` but leave it centered (`value.x=0, y=0`) and never set the click flags (`z=0, w=0`). The starfall animates from `u_time` regardless.
- [ ] **Step 2:** Verify: `swift scripts/verify_web_effect.swift starfall` → `PASS`.
- [ ] **Step 3:** Register (`webStarfall`, `"Starfall"`, `starfall`). Build.
- [ ] **Step 4:** Commit: `git commit -am "feat(web): Starfall effect"`.

---

### Task 8: Coral Blooms (`webCoralBlooms`)

**Files:**
- Create: `Sources/Lumora/Web/coralBlooms.html`
- Source: `../lumora-ref/codepen-tabs/shubniggurath_vpNxWN/index.html` (three **r88** global; `onmousemove`)

- [ ] **Step 1:** Port per **Shared Procedure A**. Global-r88 → module preamble. **Group 1:** delete `onmousemove`; center the mouse-derived shader offset (constant `0.5, 0.5` or `0, 0` per the uniform's expected range).
- [ ] **Step 2:** Verify: `swift scripts/verify_web_effect.swift coralBlooms` → `PASS`.
- [ ] **Step 3:** Register (`webCoralBlooms`, `"Coral Blooms"`, `coralBlooms`). Build.
- [ ] **Step 4:** Commit: `git commit -am "feat(web): Coral Blooms effect"`.

---

### Task 9: Storm (`webStorm`)

**Files:**
- Create: `Sources/Lumora/Web/storm.html`
- Source: `../lumora-ref/codepen-tabs/shubniggurath_BVKgJK/index.html` (three **r88** global; `pointermove` + `scroll`)

- [ ] **Step 1:** Port per **Shared Procedure A**. Global-r88 → module preamble. **Group 1:** delete both the `pointermove` and `scroll` handlers; center the mouse offset and pin any scroll-derived value to a constant (or a slow auto-ramp if the scene needs the camera to move — pick a fixed mid value).
- [ ] **Step 2:** Verify: `swift scripts/verify_web_effect.swift storm` → `PASS`.
- [ ] **Step 3:** Register (`webStorm`, `"Storm"`, `storm`). Build.
- [ ] **Step 4:** Commit: `git commit -am "feat(web): Storm effect"`.

---

### Task 10: Live Clouds (`webLiveClouds`)

**Files:**
- Create: `Sources/Lumora/Web/liveClouds.html`
- Source: `../lumora-ref/codepen-tabs/DenDionigi_GRbGLgy/index.html` (three 0.167 module + BufferGeometryUtils; `mousemove`)

- [ ] **Step 1:** Ensure `Web/lib/three/addons/utils/BufferGeometryUtils.js` exists (copy from the 0.167 dist; fix its internal `three` import to resolve via importmap — it already imports `'three'`). ES-module pen — keep imports.
- [ ] **Step 2:** Port per **Shared Procedure A**. **Group 1:** delete the `mousemove` handler; replace the mouse camera-parallax target with a slow auto-drift (`camera.position.x = Math.sin(t*0.05)*<amp>` matching the original amplitude).
- [ ] **Step 3:** Verify: `swift scripts/verify_web_effect.swift liveClouds` → `PASS`.
- [ ] **Step 4:** Register (`webLiveClouds`, `"Live Clouds"`, `liveClouds`). Build.
- [ ] **Step 5:** Commit: `git commit -am "feat(web): Live Clouds effect"`.

---

### Task 11: Disco Balls (`webDiscoBalls`)

**Files:**
- Create: `Sources/Lumora/Web/discoBalls.html`
- Source: `../lumora-ref/codepen-tabs/ksenia-k_ZEjJxWQ/index.html` (three 0.133 module + OrbitControls + BufferGeometryUtils)

- [ ] **Step 1:** Ensure addons `controls/OrbitControls.js` and `utils/BufferGeometryUtils.js` exist under `Web/lib/three/addons/`. ES-module pen — retarget imports to importmap.
- [ ] **Step 2:** Port per **Shared Procedure A**. **Group 1:** keep OrbitControls but set `controls.enableRotate = false; controls.autoRotate = true; controls.autoRotateSpeed = <slow>;` and call `controls.update()` each frame; do not attach it to real drag beyond that.
- [ ] **Step 3:** Verify: `swift scripts/verify_web_effect.swift discoBalls` → `PASS`.
- [ ] **Step 4:** Register (`webDiscoBalls`, `"Disco Balls"`, `discoBalls`). Build.
- [ ] **Step 5:** Commit: `git commit -am "feat(web): Disco Balls effect"`.

---

### Task 12: Black Hole (`webBlackHole`)

**Files:**
- Create: `Sources/Lumora/Web/blackHole.html`
- Source: `../lumora-ref/codepen-tabs/VoXelo_RNNXaQK/index.html` (three module + OrbitControls; pointer)

- [ ] **Step 1:** Ensure `controls/OrbitControls.js` addon exists. ES-module pen.
- [ ] **Step 2:** Port per **Shared Procedure A**. **Group 1:** delete the custom `pointer`/`pointerdown` handlers; set `controls.enableRotate = false; controls.autoRotate = true;` (+ `controls.update()` each frame). Keep the dark background (additive glow needs it) — do NOT force transparent clear if the effect dims; test both.
- [ ] **Step 3:** Verify: `swift scripts/verify_web_effect.swift blackHole` → `PASS`.
- [ ] **Step 4:** Register (`webBlackHole`, `"Black Hole"`, `blackHole`). Build.
- [ ] **Step 5:** Commit: `git commit -am "feat(web): Black Hole effect"`.

---

### Task 13: Particle Teapot (`webParticleTeapot`)

**Files:**
- Create: `Sources/Lumora/Web/particleTeapot.html`
- Source: `../lumora-ref/codepen-tabs/VoXelo_YPyQVNm/index.html` (three 0.162 module + many addons)

- [ ] **Step 1:** Vendor addons under `Web/lib/three/addons/`: `geometries/TeapotGeometry.js`, `postprocessing/EffectComposer.js`, `postprocessing/RenderPass.js`, `postprocessing/UnrealBloomPass.js`, `postprocessing/ShaderPass.js`, `postprocessing/FilmPass.js`, `shaders/RGBShiftShader.js`, `controls/OrbitControls.js`, plus any files THOSE import (e.g. `postprocessing/Pass.js`, `shaders/CopyShader.js`, `shaders/LuminosityHighPassShader.js`, `shaders/FilmShader.js`, `math/*`). Copy from the 0.167 dist; each addon imports `'three'` (importmap-resolved) and siblings via `'./…'` relative paths that must exist.
- [ ] **Step 2:** Port per **Shared Procedure A**. No mouse. If OrbitControls is present only for manual view, disable rotate + `autoRotate = true`. Keep dark bg if bloom needs it.
- [ ] **Step 3:** Verify: `swift scripts/verify_web_effect.swift particleTeapot` → `PASS`.
- [ ] **Step 4:** Register (`webParticleTeapot`, `"Particle Teapot"`, `particleTeapot`). Build.
- [ ] **Step 5:** Commit: `git commit -am "feat(web): Particle Teapot effect"`.

---

### Task 14: Particle-Animation (`webParticleAnim`)

**Files:**
- Create: `Sources/Lumora/Web/particleAnim.html`
- Source: `../lumora-ref/codepen-tabs/StarKnightt_XJmjZEN/index.html` (three 0.163 module + postprocessing + anime.js + simplex-noise; external `script.js`)

- [ ] **Step 1:** Check the source folder for a sibling `script.js` and **inline its contents** (the pen references `src="script.js"`). Vendor addons: `postprocessing/EffectComposer.js`, `RenderPass.js`, `UnrealBloomPass.js`, `controls/OrbitControls.js` (+ their deps). Vendor `anime.js` (`curl -L -o Sources/Lumora/Web/lib/anime.min.js https://cdn.jsdelivr.net/npm/animejs@3/lib/anime.min.js`) and `simplex-noise` (newer 4.x API: `curl -L -o Sources/Lumora/Web/lib/simplex-noise-4.mjs https://cdn.jsdelivr.net/npm/simplex-noise@4/dist/esm/simplex-noise.js`; add to importmap or import directly). Confirm whether the pen uses `createNoise3D/4D` (v4) vs `new SimplexNoise` (v2) and vendor the matching version.
- [ ] **Step 2:** Port per **Shared Procedure A**. No mouse. Keep anime.js timeline (autonomous).
- [ ] **Step 3:** Verify: `swift scripts/verify_web_effect.swift particleAnim` → `PASS`.
- [ ] **Step 4:** Register (`webParticleAnim`, `"Particle Animation"`, `particleAnim`). Build.
- [ ] **Step 5:** Commit: `git commit -am "feat(web): Particle Animation effect"`.

---

### Task 15: ShockWave (`webShockwave`)

**Files:**
- Create: `Sources/Lumora/Web/shockwave.html`
- Source: `../lumora-ref/codepen-tabs/vainsan_JoYGKoQ/index.html` (three 0.136 module + postprocessing + dat.gui; clientX/Y)

- [ ] **Step 1:** Vendor addons: `postprocessing/EffectComposer.js`, `RenderPass.js`, `ShaderPass.js`, `UnrealBloomPass.js`, `controls/OrbitControls.js` (+ deps). **Drop dat.gui entirely** (remove the import and every `gui.*` call; hardcode the values it configured).
- [ ] **Step 2:** Port per **Shared Procedure A**. **Group 2 (auto-drive):** import `autopilot.js`; each frame call `autopilot.update()` and feed the shockwave center from `autopilot.pointer01` (the shader expects a `[0,1]` `center`). Additionally auto-emit: retrigger the wave on a timer (e.g. reset wave time every ~3s) so ripples pulse continuously.
- [ ] **Step 3:** Verify: `swift scripts/verify_web_effect.swift shockwave` → `PASS`.
- [ ] **Step 4:** Register (`webShockwave`, `"Shockwave"`, `shockwave`). Build.
- [ ] **Step 5:** Commit: `git commit -am "feat(web): Shockwave effect"`.

---

### Task 16: Draw WebGL Flowers (`webFlowers`)

**Files:**
- Create: `Sources/Lumora/Web/flowers.html`
- Source: `../lumora-ref/codepen-tabs/ksenia-k_poOMpzx/index.html` (three 0.139 module; pointer-drawn)

- [ ] **Step 1:** Port per **Shared Procedure A**. ES-module pen. **Group 2 (auto-drive):** delete the `mousemove`/`touchmove` listeners that set `pointer.x/y` + `pointer.moved`; instead import `autopilot.js`, and each frame set `pointer.x = autopilot.pointer01.x; pointer.y = autopilot.pointer01.y; pointer.moved = true;` after `autopilot.update()`. Flowers now bloom along the synthetic wandering path.
- [ ] **Step 2:** Verify: `swift scripts/verify_web_effect.swift flowers` → `PASS` (must show blooms appearing over time).
- [ ] **Step 3:** Register (`webFlowers`, `"Draw Flowers"`, `flowers`). Build.
- [ ] **Step 4:** Commit: `git commit -am "feat(web): Draw Flowers effect"`.

---

### Task 17: On-Scroll Fire (`webFire`)

**Files:**
- Create: `Sources/Lumora/Web/fire.html`
- Source: `../lumora-ref/codepen-tabs/ksenia-k_wvEMqNR/index.html` (three 0.133 module + gsap ScrollTrigger)

- [ ] **Step 1:** Port per **Shared Procedure A**. ES-module pen. **Remove** the `.scroll-space` div, the "Fire Scroll" text, `ScrollTrigger` import/registration, and the `scrollTrigger:{…}` tween. **Group 2 (auto-drive):** import `autopilot.js`; each frame set the fire's scroll-progress uniform/variable to `autopilot.getProgress()` (looping 0→1→0) after `autopilot.update()`.
- [ ] **Step 2:** Verify: `swift scripts/verify_web_effect.swift fire` → `PASS`.
- [ ] **Step 3:** Register (`webFire`, `"Fire"`, `fire`). Build.
- [ ] **Step 4:** Commit: `git commit -am "feat(web): Fire effect"`.

---

### Task 18: Pacman Concept (`webPacman`)

**Files:**
- Create: `Sources/Lumora/Web/pacman.html`
- Source: `../lumora-ref/codepen-tabs/radixzz_PRaRZB/index.html` (three module + EffectComposer globals; mouse-follow + gsap)

- [ ] **Step 1:** Vendor addons: `postprocessing/EffectComposer.js`, `RenderPass.js`, `ShaderPass.js` (+ deps). Vendor gsap if used (`lib/gsap.min.js` from Task 5). Note the pen uses `THREE.EffectComposer`/`THREE.Math` globals (r128-style) — assign the addon classes onto `THREE` in the preamble and replace `THREE.Math`→`THREE.MathUtils`.
- [ ] **Step 2:** Port per **Shared Procedure A**. **Group 2 (auto-drive):** delete the `mousemove` handler that sets `this.mouse.x/y`; each frame set `this.mouse.x = autopilot.pointer.x; this.mouse.y = autopilot.pointer.y;` after `autopilot.update()`.
- [ ] **Step 3:** Verify: `swift scripts/verify_web_effect.swift pacman` → `PASS`.
- [ ] **Step 4:** Register (`webPacman`, `"Pacman"`, `pacman`). Build.
- [ ] **Step 5:** Commit: `git commit -am "feat(web): Pacman effect"`.

---

### Task 19: Liquid Effect (`webLiquid`) — prebuilt package

**Files:**
- Create: `Sources/Lumora/Web/liquid.html`, `Sources/Lumora/Web/lib/liquid1.min.js`
- Source: `../lumora-ref/codepen-tabs/soju22_myVWBGa/index.html` (imports `threejs-components@0.0.27/build/backgrounds/liquid1.min.js`)

- [ ] **Step 1:** Vendor the prebuilt bundle as-is (it bundles its own three): `curl -L -o Sources/Lumora/Web/lib/liquid1.min.js https://cdn.jsdelivr.net/npm/threejs-components@0.0.27/build/backgrounds/liquid1.min.js`. **Do NOT** route it through the shared importmap — it's self-contained.
- [ ] **Step 2:** Create `liquid.html` importing `./lib/liquid1.min.js` as a module and initializing it on a full-bleed canvas exactly like the source, minus chrome. If the bundle expects a CDN sub-import at runtime and fails offline, **flag it and drop this effect** (per spec risk note) — revert the task's files and skip registration.
- [ ] **Step 3:** Verify: `swift scripts/verify_web_effect.swift liquid` → `PASS`.
- [ ] **Step 4:** Register (`webLiquid`, `"Liquid"`, `liquid`). Build.
- [ ] **Step 5:** Commit: `git commit -am "feat(web): Liquid effect"`.

---

### Task 20: Tubes Cursor (`webTubes`) — prebuilt package + auto-drive

**Files:**
- Create: `Sources/Lumora/Web/tubes.html`, `Sources/Lumora/Web/lib/tubes1.min.js`
- Source: `../lumora-ref/codepen-tabs/soju22_qEbdVjK/index.html` (imports `threejs-components@0.0.19/build/cursors/tubes1.min.js`)

- [ ] **Step 1:** Vendor: `curl -L -o Sources/Lumora/Web/lib/tubes1.min.js https://cdn.jsdelivr.net/npm/threejs-components@0.0.19/build/cursors/tubes1.min.js`. Self-contained bundle.
- [ ] **Step 2:** Create `tubes.html` initializing `TubesCursor(canvas, {…})` from the source (minus the Framer/attribution links). **Group 2 (auto-drive):** the component tracks the real cursor; import `autopilot.js` and dispatch synthetic `pointermove` events on the canvas each frame from `autopilot.pointer01` mapped to pixel coords (`clientX = x*innerWidth`, `clientY = y*innerHeight`), OR call the component's public move API if it exposes one. If it can't be driven without a real cursor and fails offline, **flag and drop** per the spec risk note.
- [ ] **Step 3:** Verify: `swift scripts/verify_web_effect.swift tubes` → `PASS` (tubes must visibly move).
- [ ] **Step 4:** Register (`webTubes`, `"Tubes"`, `tubes`). Build.
- [ ] **Step 5:** Commit: `git commit -am "feat(web): Tubes effect"`.

---

### Task 21: Cleanup + backlog update

**Files:**
- Delete: `Sources/Lumora/Web/_smoketest.html`
- Modify: `docs/BACKLOG.md`

- [ ] **Step 1:** Remove the smoke-test page: `git rm Sources/Lumora/Web/_smoketest.html`.
- [ ] **Step 2:** Update `docs/BACKLOG.md`: note the 19 CodePen effects ported (or the subset, if any were dropped per Task 19/20 risk), and that the global-clock/audio bridge + off-screen pause backlog items now apply to these too.
- [ ] **Step 3:** Full build + spot-verify a sample: `swift build && swift scripts/verify_web_effect.swift zoomingSpiral && swift scripts/verify_web_effect.swift flowers`.
- [ ] **Step 4:** Commit: `git commit -am "chore(web): remove smoke test, update backlog for CodePen effects"`.

---

## Delivery cadence

Per standing preference, demo in **batches of 2** after these task pairs (launch the packaged `.app`, pick each effect, confirm it animates with no input and no chrome): (2,3) · (4,5) · (6,7) · (8,9) · (10,11) · (12,13) · (14,15) · (16,17) · (18) · (19,20). Task 1 (framework) is validated by its smoke-test verify, not a visual demo.

## Notes on verification

`scripts/verify_web_effect.swift <basename>` loads `Sources/Lumora/Web/<basename>.html` into an offscreen WKWebView and asserts the page renders non-blank and that two snapshots a beat apart differ (animation). It reads sibling `lib/` files via file-URL read access. A `PASS` is the gate for each effect task before registration.
