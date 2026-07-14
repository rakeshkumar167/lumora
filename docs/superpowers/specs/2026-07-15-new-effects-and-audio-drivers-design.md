# New Effects (16) + Shared Audio Drivers — Design / Requirements

**Date:** 2026-07-15
**Status:** Approved (brainstorm), ready for implementation plan.
**Model note:** To be built with Opus. Build incrementally in **verified sets of
2** (ordering at the bottom); keep it compiling at each step; end with a
packaged-app demo (`scripts/make_app.sh`) since mic permission needs the
packaged app.

## Summary

Two workstreams in one spec:

1. **Shared audio abstraction** — generalize the mic/FFT plumbing built for
   Audio Reactive Particles so *any* effect can react to audio: real spectrum
   bins, beat detection, a per-surface **Audio Reactive** toggle, and five
   retrofits of existing effects that prove the reuse.
2. **16 new effects** (63 → 79 total), grouped by the existing infrastructure
   each reuses: cheap Canvas re-skins, the GoL bake pipeline, the software 3D
   pipeline, the curl-noise swarm engine, the trace/growth aesthetic, and two
   practical/event effects. Includes one new category, **Living Systems**.

Everything follows the established patterns: `EffectKind` case + category in
LumoraKit, renderer in a per-category `@ViewBuilder` in
`Sources/Lumora/Views/SurfaceContentView.swift` (or a dedicated stateful view
like `ParticleSwarmView` where noted), optional per-effect config structs on
`Surface` with tolerant decode, pure logic in LumoraKit with unit tests,
offscreen `ImageRenderer` verify scripts in `scripts/`.

---

## Part 1 — Shared audio drivers

### What exists (do not rebuild)

- `AudioLevels` (LumoraKit) — smoothed normalized `bass/mid/treble/overall`,
  `0…1`, `.silent` fallback.
- `AudioBandAnalyzer` (LumoraKit) — pure, stateful FFT-magnitudes → `AudioLevels`
  reducer with fast-attack/slow-decay smoothing and running-peak auto-gain.
  Unit-testable with synthetic spectra.
- `AudioInputManager` (app) — shared singleton mic tap; 1024-point FFT per
  buffer; ref-counted `retain()`/`release()` so the engine runs only while an
  audio effect is on screen; `isDenied` fallback. Mic permission only works in
  the packaged app.
- `AudioLevelsProviding` protocol — how views consume audio; injectable for
  previews/verify scripts.
- `SwarmDrivers(from:)` — the existing particle mapping. Unchanged.

### Extensions (LumoraKit, all backward-compatible)

**`AudioLevels` gains three fields** (defaults keep `.silent` and existing
call sites valid):

```swift
public struct AudioLevels: Equatable {
    public var bass, mid, treble, overall: Double     // existing
    /// 16 log-spaced smoothed bins, 20 Hz…8 kHz, each 0…1 (auto-gained like
    /// the bands). For visualizers that need more than 3 bands.
    public var spectrum: [Double]                     // default []
    /// Monotonically increasing count of detected beats. Views detect a beat
    /// by comparing against the last count they saw — robust to any frame
    /// rate mismatch between the ~46 Hz analysis rate and 60 fps rendering.
    public var beatCount: Int                         // default 0
    /// Strength of the most recent beat, 0…1.
    public var beatStrength: Double                   // default 0
}
```

**New `BeatDetector`** (pure LumoraKit, unit-tested with synthetic level
sequences): energy-onset detection on the bass band. Keeps a short ring buffer
(~1 s) of bass levels; fires when the current level exceeds
`mean + k · stddev` (k ≈ 1.5) *and* an absolute floor (~0.15), with a ~180 ms
refractory period so one kick reads as one beat. `beatStrength` = how far above
the mean the spike was, clamped 0…1.

**`AudioBandAnalyzer`** composes a `BeatDetector` and fills the new fields in
`process(magnitudes:sampleRate:)`. It also folds the magnitudes into the 16
log-spaced spectrum bins (same auto-gain peak as the bands, per-bin smoothing
with the same attack/decay). `reset()` resets the detector too.

`AudioInputManager` and `AudioLevelsProviding` need **no interface change** —
the richer `AudioLevels` flows through the existing `currentLevels`.

### Per-surface Audio Reactive toggle

- `Surface.audioReactive: Bool` — default `false`, `decodeIfPresent` (same
  tolerant-decode pattern as the config structs).
- `EffectKind.supportsAudio: Bool` — true for the retrofits below plus
  `chladni` (Part 2). `audioParticles` stays a distinct effect (it is
  *inherently* audio; no toggle).
- Properties panel: an "Audio Reactive" toggle shown only when
  `media == .effect` and `effect.supportsAudio`. Sub-note under the toggle when
  `isDenied`: "Microphone unavailable — running idle."
- Renderer plumbing: `EffectView` passes `audioReactive` down; audio-capable
  renderers take an `audio: AudioLevelsProviding = AudioInputManager.shared`
  (injectable, same as `ParticleSwarmView`) and call `retain()`/`release()` in
  `onAppear`/`onDisappear` **only when the toggle is on**. When off or denied,
  the effect renders exactly as today (time-driven) — zero visual regression
  for existing projects.

### Retrofits (prove the reuse)

| Effect | Audio mapping when toggle is on |
|---|---|
| **Equalizer** | Bars driven by the 16 real `spectrum` bins (resampled to the bar count); peak-hold caps that fall slowly. Falls back to today's randomized bars when off/denied. |
| **Strobe** | Flashes on `beatCount` change instead of the fixed clock; flash opacity scales with `beatStrength`. |
| **Liquid Slosh** | Each beat injects a lateral impulse into the tank proportional to `beatStrength`; `bass` adds a continuous swell. |
| **Aurora** | `bass` drives ribbon amplitude, `overall` drives brightness, `treble` adds shimmer speed. Silence = today's drift. |
| **Plasma** | `bass` scales the field's spatial frequency subtly, `overall` scales brightness, beats pulse saturation. |

Mappings must be **monotonic and bounded** (like `SwarmDrivers(from:)`) so a
denied/silent mic degrades to a calm version, never a broken one.

### Testing

- `BeatDetector`: synthetic sequences — steady level (no beats), periodic
  spikes (beats at the right times, refractory respected), noise floor (no
  false positives).
- `AudioBandAnalyzer` spectrum bins: synthetic single-frequency spectra land in
  the right bin; auto-gain normalizes.
- Verify scripts render Equalizer/Strobe with a stub `AudioLevelsProviding`
  feeding scripted levels.

---

## Part 2 — 16 new effects

New `EffectKind` cases, category, approach, and config for each. All are
warp-aware `Canvas` renderers driven by the shared `time` unless noted.
Naming: `caustics`, `inkFlow`, `godRays`, `stainedGlass`, `physarum`, `lenia`,
`fallingSand`, `strangeAttractor`, `dnaHelix`, `aquarium`, `butterflies`,
`mazeSolve`, `hilbertCurve`, `growingIvy`, `countdown`, `chladni`.

### New category: Living Systems

`EffectCategory.livingSystems`, display name **"Living Systems"**. Holds the
three new baked simulations plus two moves: `gameOfLife` and
`reactionDiffusion` (out of Ambient, which is crowded). Category is *derived*
from `EffectKind`, never persisted, so moving effects is save-compatible.

### Group A — Canvas re-skins (cheap, classic)

1. **Water Caustics** (`caustics`, Ambient) — the dancing pool-floor light
   webs. 2–3 layers of drifting cellular (Worley-style) bright ridges,
   blurred + `plusLighter`, slow counter-drifting layers. Reuses the vector
   voronoi half-plane machinery for cell edges. Primary color tints the water,
   accent tints the caustic web.
2. **Stained Glass** (`stainedGlass`, Fields) — the rebuilt vector Voronoi
   with thick dark lead lines, jewel-toned translucent cells (fixed palette,
   no color config — like the ambient effects), and a slow bright light sweep
   passing "behind" the glass (a moving radial gradient multiplied into cell
   brightness).
3. **God Rays** (`godRays`, Ambient) — 3–5 slow volumetric beams from a
   corner/top edge (soft-edged translucent quads, blurred, `plusLighter`),
   dust motes drifting inside the beams (sparse slow particles clipped to the
   beam shapes). Beams breathe in intensity over ~30 s. Primary color = light
   color.
4. **Ink in Water** (`inkFlow`, Ambient) — colored ink blooms: soft blobs
   spawned periodically, advected by the existing `CurlNoiseField`, expanding
   and fading; heavy blur so they read as fluid. Primary + accent = two ink
   colors alternating. Stateful blob buffer (same `@State` reference-type
   pattern as `ParticleSwarmView`).

### Group B — Baked simulations (Living Systems, GoL pipeline)

All three follow the Game of Life precedent exactly: a
`scripts/generate_<name>.swift` bakes ~2 min of frames into a packed JSON
resource in `Sources/Lumora/Resources/`; a `<Name>Pattern` loader (like
`GameOfLifePattern`) loads it once; the renderer loops frames at zero
per-frame simulation cost and resets at the end.

5. **Physarum / Slime Mold** (`physarum`) — agent-based trail sim baked
   offline: agents deposit pheromone, sense-and-steer toward it, trail
   diffuses + evaporates → glowing organic networks that grow, merge, and
   dissolve. Bake the **trail field** quantized to 4-bit intensity
   (grid ≈ 128×72, ~1200 frames ≈ 5 MB packed — acceptable; tune grid/frames
   down if the resource exceeds ~6 MB). Render: intensity → primary-color
   glow with a hue drift toward accent at high intensity.
6. **Lenia** (`lenia`) — continuous-state Game of Life; smooth gliding
   cellular creatures. Same 4-bit quantized field bake. Bake script searches a
   few known-good kernel/growth parameter sets and seeds for a lively run
   (same "liveliest of N seeds" approach as `generate_gol.swift`). Rainbow hue
   mapped to cell state, like GoL's per-generation hue advance.
7. **Falling Sand** (`fallingSand`) — colored sand streams pouring from 2–3
   moving spouts, piling, avalanching; periodically the pile "drains" and the
   cycle restarts. Cellular sand automaton baked as 4-bit **palette indices**
   (fixed warm palette, ~6 sand colors + empty). No color config.

### Group C — 3D pipeline reuse (3D category)

8. **Strange Attractor** (`strangeAttractor`) — Lorenz (or Aizawa) attractor:
   integrate a few thousand steps once per cycle into a polyline, rotate it
   with the existing `rot3` + perspective projection, draw as a depth-cued
   glowing ribbon (brighter + thicker near camera), rainbow along arc length.
   The integrator is pure LumoraKit (unit-tested: bounded orbit, no NaNs).
   Respects `ThreeDConfig` speed like the other 3D effects.
9. **DNA Helix** (`dnaHelix`) — rotating double helix: two phase-offset
   strands of glowing spheres + base-pair rungs, depth-sorted via the existing
   painter's sort, rainbow depth-cued like 3D Point Cloud. Small delta on the
   point-cloud renderer.

### Group D — Swarm engine reuse (Particles & Nature)

10. **Aquarium** (`aquarium`) — the curl-noise swarm re-skinned as a fish
    tank: ~60 larger fish-shaped sprites (velocity-aligned tapered body +
    tail-wag sinusoid) in 2–3 size/color tiers, plus rising bubble columns and
    2–3 swaying kelp strands anchored to the bottom edge. Deep-water gradient
    background. Fixed palette. Reuses `ParticleSwarmSystem` with a lower count
    and calmer `SwarmDrivers.idle`-style drivers; kelp/bubbles are simple
    time-driven Canvas layers.
11. **Butterflies** (`butterflies`) — same engine, ~40 particles rendered as
    two-wing sprites with a wing-flap phase per particle (scale-x oscillation),
    gentle upward-biased drift. Primary/accent tint the wing gradient.

### Group E — Trace / growth aesthetic

12. **Maze Generate & Solve** (`mazeSolve`, Patterns & Geometry) — a maze
    carves itself (recursive backtracker, drawn wall-by-wall with a glowing
    head like Circuit Trace), then a runner solves it (A* path traced with a
    contrasting glow), hold, fade, re-seed — the fractal
    generate → hold → vanish cycle. Maze generation + solver are pure
    LumoraKit (unit-tested: perfect maze — exactly one path between any two
    cells; solver finds it). Primary = walls, accent = solution path.
13. **Hilbert Curve** (`hilbertCurve`, Patterns & Geometry) — an order-6
    Hilbert curve draws itself end to end with a glowing pen head, colored by
    arc-length rainbow (Contour Trace's rainbow treatment), hold, fade,
    repeat at alternating orientations. Curve generator is pure LumoraKit
    (unit-tested: visits every cell exactly once, unit step lengths).
14. **Growing Ivy** (`growingIvy`, Edge) — vines crawl along the surface's
    true outline (reuses `EffectOutline` like Outline Glow): main stems follow
    the outline path, side branches sprout inward with leaves appearing along
    them, then an autumn hue-shift and leaf-fall, then regrowth. Primary =
    leaf color (default green), accent = autumn color.

### Group F — Practical / event

15. **Countdown Timer** (`countdown`, Clocks & Info) — big styled digits
    counting down to a configurable target. New `CountdownConfig` on `Surface`
    (tolerant decode, same pattern as `MarqueeConfig`):

    ```swift
    public struct CountdownConfig: Codable, Equatable {
        public var target: Date            // default: next midnight
        public var label: String           // optional caption, default ""
        public var finale: Bool            // default true
    }
    ```

    Panel: date+time picker, label field, finale toggle. Uses the real-time
    clock plumbing (like Digital Clock — **not** the shared effect `time`;
    see the global-clock gotcha). Display adapts: `d h m s` when >24 h,
    `h:mm:ss` under a day, big `m:ss` under 10 min, pulsing whole seconds
    under 10 s. At zero: if `finale`, ~20 s of the existing fireworks renderer
    (reused, mega-burst tier) behind a "00:00:00"→label swap; then holds.
    Primary/accent color the digits/accents.
16. **Chladni Patterns** (`chladni`, Patterns & Geometry) — vibrating-plate
    nodal patterns: brightness = closeness to the zero-set of a 2-D standing
    wave `cos(nπx)cos(mπy) − cos(mπx)cos(nπy)`; sand-like bright lines on a
    dark plate. Time-driven mode morphs `(n, m)` smoothly through a sequence.
    **`supportsAudio = true`**: with Audio Reactive on, the dominant band
    picks the target `(n, m)` (bass → low modes, treble → high modes) and
    `overall` drives line brightness/thickness — frequency literally selects
    the pattern. The plate function is pure LumoraKit (unit-tested: symmetry,
    zero-set sanity at known modes).

### Colors

Follow existing conventions: fixed-palette effects (`stainedGlass`,
`fallingSand`, `aquarium`, plus the baked sims' rainbow treatments) return
`false` from `usesColor`; the rest wire `usesColor`/`usesAccent` as described
per effect above.

---

## Persistence & compatibility

- `Surface.audioReactive` and `Surface.countdown` use `decodeIfPresent` —
  old `.lumora` files load unchanged.
- `AudioLevels`' new fields have defaults — no encoding concerns (it is never
  persisted).
- Category moves (`gameOfLife`, `reactionDiffusion` → Living Systems) are
  UI-only.
- No changes to existing effect renderers except the five opt-in retrofits,
  which are visually identical with the toggle off.

## Testing & verification

- Unit tests (LumoraKit): `BeatDetector`, spectrum binning, maze
  generator/solver, Hilbert generator, attractor integrator, Chladni plate
  function, `CountdownConfig` decode.
- Bake scripts print frame/byte counts; renderers assert resource presence
  (like `GameOfLifePattern.shared` guard).
- One offscreen `ImageRenderer` verify script per set (pattern:
  `scripts/verify_*.swift`), with a stub audio provider for audio checks.
- Manual: packaged app (`scripts/make_app.sh`) for the mic-permission path;
  editor + projector windows simultaneously (independent sims are fine —
  established precedent).

## Build order (verified sets of 2)

1. Water Caustics + Stained Glass
2. God Rays + Ink in Water
3. Audio abstraction (spectrum + `BeatDetector` + toggle plumbing) + retrofits: Equalizer, Strobe
4. Retrofits: Liquid Slosh, Aurora, Plasma + **Chladni** (with audio mode)
5. Physarum + Lenia (bake scripts + loaders + renderers, Living Systems category lands here)
6. Falling Sand + Maze Generate & Solve
7. Hilbert Curve + Growing Ivy
8. Strange Attractor + DNA Helix
9. Aquarium + Butterflies
10. Countdown Timer (+ panel work) — final polish pass, README/BACKLOG update

Each set: compiles, unit tests pass, verify script renders, quick app demo.

## Out of scope

- Audio input other than the microphone (no system-audio loopback capture).
- A user sensitivity knob (auto-gain already handles room loudness).
- Audio-reactive support beyond the five retrofits + Chladni (the toggle
  makes future additions incremental).
- Live (non-baked) physarum/lenia/sand simulation.
- Effect-picker search/favorites (worth doing as the roster hits 79, but a
  separate spec).
