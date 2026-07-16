# WebGL / JS Effects via WKWebView — Design / Requirements

**Date:** 2026-07-16
**Status:** Implemented 2026-07-16 (framework + all 3 starter effects shipped;
warp spike passed — live `.projectionEffect` warps a `WKWebView`).

## Summary

A **curated built-in library** of JS/WebGL effects that render inside a
`WKWebView` and appear in the effect picker exactly like native effects. Three
starter effects prove the framework across all three content styles: a
self-contained **GLSL fragment shader**, a **three.js** 3D scene, and a
**p5.js** generative sketch. Effects perspective-warp onto their surface quad
like every other Lumora medium (a live-warp spike resolves the mechanism).

This adds a new rendering path (a `WKWebView` host) alongside the existing
SwiftUI `Canvas` effects, reusing the entire `EffectKind` / picker / persistence
/ Scenes machinery. No user authoring, no network, no remote URLs (curated
local resources only).

## Integration (Approach A — chosen)

Web effects are ordinary `EffectKind` cases in a new `EffectCategory.webGL`
(display name **"WebGL & Shaders"**), NOT a new `MediaAssignment` media type.
This makes them appear in the effect picker grouped like every other category,
persist through the existing `.effect(kind, primary, accent)` payload, and flow
through Scenes / save / open with zero new plumbing — matching the precedent set
by the Bioluminescent and Christmas effect sets.

- New cases: `webPlasma`, `webParticles3D`, `webFlow`.
- `usesColor` / `usesAccent` return **`false`** (fixed, self-contained pages;
  add to the `usesColor` false-list, neither `usesAccent` list — same as the
  Bioluminescent set).
- `supportsAudio` = `false` (default).
- `category` returns `.webGL`; `EffectCategory.webGL` added with its display
  name. The picker is data-driven off `EffectCategory.allCases`, so the category
  and its effects appear automatically.

## Architecture

```
EffectKind (.webPlasma / .webParticles3D / .webFlow)          ← LumoraKit/EffectKind.swift
   ├─ EffectCategory.webGL  "WebGL & Shaders"
   ├─ usesColor/usesAccent = false
   └─ resource name via a small mapping (see below)

EffectView.body  ← Sources/Lumora/Views/SurfaceContentView.swift
   └─ web-category kinds → WebEffectContent(resource: <name>)   (new dispatch arm)

WebEffectContent : NSViewRepresentable   ← new Sources/Lumora/Views/WebEffectContent.swift
   └─ owns a WKWebView, loads bundled Web/<name>.html, transparent background

Sources/Lumora/Web/                       ← .copy("Web") in Package.swift (separate
                                            top-level resource dir, NOT under Resources/,
                                            to avoid an overlapping rule with .process)
   ├─ plasma.html            (self-contained GLSL/WebGL, no library)
   ├─ particles3d.html       (uses lib/three.min.js)
   ├─ flow.html              (uses lib/p5.min.js)
   └─ lib/
        ├─ three.min.js      (vendored, no CDN)
        └─ p5.min.js         (vendored, no CDN)
```

One new component (`WebEffectContent`), one new enum category, one resource
folder. The `EffectKind → resource file name` mapping lives in the app layer
(next to `WebEffectContent`), not in `LumoraKit`, so the pure core stays free of
bundle/resource concerns.

## Component: `WebEffectContent`

Mirrors `VideoContent`'s `NSViewRepresentable` shape (which hosts an
`AVPlayerLayer`):

- Creates one `WKWebView` per surface instance (each surface is its own browser
  instance — heavier than a native `Canvas` effect; acceptable for the handful
  of surfaces a projection uses).
- **Transparent background** so effects overlay other surfaces: set
  `setValue(false, forKey: "drawsBackground")` on the `WKWebView`, and each page
  uses a transparent `html,body { background: transparent }`.
- Loads the bundled file with
  `webView.loadFileURL(htmlURL, allowingReadAccessTo: webDirURL)` where
  `webDirURL` is the bundled `Web` directory, so a page can read its sibling
  `lib/*.js` files.
- The page animates itself with its own `requestAnimationFrame` loop. Lumora's
  global effect clock is **not** bridged into the page in v1 (Scenes just mount
  / unmount the view). Syncing a `time`/`iTime` uniform to the Lumora clock is a
  documented future add (see Out of scope).
- `updateNSView` reloads only when the resource name changes (guarded like
  `VideoContent.load`'s `url != currentURL` check), so redraws/resizes don't
  reload the page.

## Warp handling (primary risk — spiked FIRST)

**RESOLVED (2026-07-16, `scripts/spike_web_warp.swift`): step 1 works.** A live
`WKWebView` running the WebGL plasma page, placed under a perspective
`.projectionEffect`, renders keystoned with true perspective at full framerate
(screenshot eyeballed) — the same path `VideoContent` uses. No `CATransform3D`
or per-frame snapshot fallback is needed; web effects warp exactly like
image/video surfaces via the existing `SurfaceContentView.quadBody`.

Original decision ladder (kept for the record):

1. **Live `.projectionEffect`** — the same path `VideoContent` uses (the parent
   `SurfaceContentView.quadBody` applies `ProjectionTransform(homography)`). Try
   first; if the web layer warps correctly on an angled quad, done — full
   framerate, no extra code.
2. **`CATransform3D`** on the web view's layer directly — if SwiftUI's
   `ProjectionTransform` doesn't apply to the `WKWebView`'s layer.
3. **`takeSnapshot` per frame → warp the image** — guaranteed-correct warp but
   caps framerate; last resort.

**Spike acceptance:** mount one bundled effect (the GLSL `webPlasma`) on a
surface, rotate/skew the quad, and eyeball that the rendered content warps to
the quad corners (matches how an image/video surface warps). Record the chosen
mechanism in the plan before proceeding. Polygon/ellipse surfaces use the
`clippedBody` path (bounding-box fill + clip, no perspective) exactly like other
media — no special handling needed.

## The three starter effects

Each is a fixed, self-animating page with no color config (YAGNI; matches the
fixed-palette precedent):

- **`webPlasma`** — self-contained animated GLSL fragment shader (plasma / flow
  field) rendered to a full-canvas WebGL quad. No external library. Also the
  warp-spike subject.
- **`webParticles3D`** — three.js scene: a rotating GPU particle field / point
  cloud with depth, richer than the native software-3D effects. Uses vendored
  `lib/three.min.js`.
- **`webFlow`** — p5.js generative flow-field / particle sketch. Uses vendored
  `lib/p5.min.js`.

Display names (tunable): "WebGL Plasma", "3D Particles (WebGL)", "Flow Field
(p5)".

## Resource pipeline

- `Package.swift`: add `.copy("Web")` to the `Lumora` target's `resources`
  array, alongside the existing `.process("Resources")`. The web bundle lives in
  its own top-level `Sources/Lumora/Web/` directory (NOT under `Resources/`) —
  `.process("Resources")` already globs everything under `Resources/`, so a
  `.copy` of a subdirectory of it would be an overlapping-rule build error.
  `.copy` preserves the directory structure verbatim so pages can reference
  `lib/three.min.js` by relative path; `.process` would flatten/optimize and
  break relative references.
- Access at runtime via
  `Bundle.module.url(forResource: "plasma", withExtension: "html", subdirectory: "Web")`
  and derive the `Web` directory URL for `allowingReadAccessTo:`.
- Vendored libraries are committed into `Sources/Lumora/Web/lib/` (no CDN, works
  offline, no CSP/network dependency).

## Persistence & compatibility

- Purely additive: new `EffectKind` cases + `EffectCategory.webGL` (category is
  derived from `EffectKind.category`, never persisted). Old `.lumora` files are
  unaffected; no new config structs on `Surface`.
- Existing effects/renderers are untouched (additive to the category, the
  `usesColor` false-list, and the `EffectView` dispatch switch).

## Testing & verification

- No new pure `LumoraKit` logic → no new unit tests. The existing **96 tests
  must still pass** (additive changes only).
- Web effects are live `WKWebView`s, not SwiftUI `Canvas`es, so the established
  offscreen `ImageRenderer` verify-script pattern does **not** apply — this is
  the first effect family without an automated verify script, by nature of the
  content being a live browser instance. Honest tradeoff, called out explicitly.
- Verification is therefore: **`swift build` clean**, then a **human eyeball via
  `swift run`** — mount each of the three effects on a surface and confirm it
  renders, animates, has a transparent background, and warps on an angled quad.
  The warp-spike frame is the key artifact for Task 1.

## Build order (verified sets, quick demo per set)

1. **Warp spike + framework + `webPlasma`** — add `WebEffectContent`, the
   `EffectCategory.webGL` + `webPlasma` case, the resource pipeline
   (`Sources/Lumora/Web/plasma.html` + `Package.swift` `.copy("Web")`), and resolve the warp
   mechanism with the one GLSL shader. `swift build` clean; `swift test` still
   96/96. Checkpoint: `swift run`, mount `webPlasma`, verify render + warp.
2. **`webParticles3D` + `webFlow`** — vendor `three.min.js` and `p5.min.js` into
   `Sources/Lumora/Web/lib/`, add the two pages + their `EffectKind` cases. `swift
   build` clean; `swift test` still 96/96. Checkpoint: `swift run`, mount both,
   verify render + warp.

## Out of scope (v1)

- User-authored / imported HTML, remote URLs, live web pages (curated local
  resources only — decided in brainstorm).
- Bridging Lumora's global effect clock into the page (a `time`/`iTime` uniform
  sync); pages self-animate via `requestAnimationFrame`. A nice future add for
  scrubbable / audio-reactive web effects.
- Audio reactivity (mic → shader uniforms) — future.
- Pausing/throttling off-screen or inactive-scene web views for performance —
  future optimization; v1 lets them run.
- User color/parameter config for web effects — future (would need a uniform
  bridge).
