# Bioluminescent Night Scenes — Design / Requirements

**Date:** 2026-07-16
**Status:** Implemented 2026-07-16 (all 4 effects shipped; see BACKLOG "Done recently").

## Summary

A new **Bioluminescent** effect category — four composable, cinematic
"Avatar/Pandora night jungle" effects the user assigns across surfaces (and
combines via Scenes): **Misty Peaks** (backdrop), **Drifting Spores** (ambient
overlay), **Glowing Flora** (growing plants), and **Bioluminescent River**
(flowing glowing water). All share one fixed Pandora palette so they read as a
single world. Adds 4 effects to the roster (~75 shipped today → ~79).

Everything follows the established Lumora patterns: `EffectKind` case +
`EffectCategory` in `LumoraKit`; renderers in `SurfaceContentView.swift` (a new
`bioluminescentEffects` @ViewBuilder and/or dedicated `View` structs); fixed
palette so effects return `false` from `usesColor`/`usesAccent`; offscreen
`ImageRenderer` verify scripts; the near-black + blurred `plusLighter` glow idiom.

No new pure `LumoraKit` logic is required (these are renderers) — so no new unit
tests; each effect is validated by a `scripts/verify_<name>.swift` (asserting
non-blank + color variance + change-over-time) plus a human-eyeballed rendered
frame, matching how the recent effects were verified.

## Shared foundation

### New category
`EffectCategory.bioluminescent`, display name **"Bioluminescent"**. Derived from
`EffectKind.category` (never persisted), so it is save-compatible.

### `BioPalette` (fixed, shared)
A small fixed palette shared by all four effects so the set is cohesive out of
the box. Define as `Color` constants in `SurfaceContentView.swift` near the
effects (or a tiny `BioPalette` enum). Suggested values (tunable at
implementation):

- `night`: near-black deep teal `#02060A` (background base).
- `waterDeep`: `#031318`, `waterMid`: `#05323A` (river gradient).
- `glowCyan`: `#28E6D2`, `glowAqua`: `#5CF2FF`, `glowTeal`: `#12B7A8`
  (primary bioluminescence tiers).
- `accentMagenta`: `#B94BE0`, `accentViolet`: `#7A4BFF` (flower cores / rare motes).
- `moon`: `#BFE9FF` (soft moon-glow), `mist`: `#0E2A33` (mist bands).

All four effects return `false` from both `usesColor` and `usesAccent` (no
color pickers) — add each to the `usesColor` FALSE-list, and to NEITHER
`usesAccent` list. (Recall `usesColor`'s default is `true`, so fixed-palette
effects MUST be listed in its false-case.)

### Glow idiom (already standard)
Dark base fill, then per-element a blurred `plusLighter` under-layer + a crisp
brighter core (see `OutlineGlowView`, `drawPointCloud3D`, the caustics/god-rays
renderers). No new technique.

---

## Effect 1 — Misty Peaks (`mistyPeaks`)

Backdrop layer. **Stateless** time-driven `Canvas` (no `@State` needed — mist and
stars animate from `time`). Draw back-to-front:

1. **Sky gradient:** vertical, `night` at bottom → a slightly lifted deep
   blue-teal at top.
2. **Moon glow:** a soft radial `moon`-colored bloom disk high in the frame
   (blurred, `plusLighter`), slightly off-center, gently breathing.
3. **Stars:** ~60 faint points at hashed positions, twinkling via
   `sin(time + i)`.
4. **Parallax ridges:** 3–4 mountain silhouette layers, each a jagged polyline
   baseline (deterministic via `hash01`) filled downward. Farther ridges are
   lighter/bluer and drift slower; nearer ridges darker. Each drifts
   horizontally at its own slow speed (parallax).
5. **Mist bands:** 2–3 horizontal translucent blurred bands drifting sideways
   between/over the ridges, `mist`-colored, low opacity, `plusLighter`.

No user config. Fully deterministic from `time`.

## Effect 2 — Drifting Spores (`driftingSpores`)

Ambient overlay. Reuses the swarm engine like **Butterflies**:
- Dedicated `struct DriftingSporesView: View { let time: Double }` with a
  reference-type `@State` render object holding `ParticleSwarmSystem(count: 65)`
  + `lastTime`; `dt` from the shared `time` with the `guard now != lastTime`
  sizing-pass skip (do NOT double-step); calm `SwarmDrivers.idle(time:)` +
  `CurlNoiseField()`.
- Gentle **upward-biased drift**: after stepping, nudge each particle's y up a
  little (reuse the `ParticleSwarmSystem.nudgeY` mutator added for Butterflies),
  wrapping bottom→top, so spores rise.
- Render each spore as a soft glowing bloom: a blurred `plusLighter` halo +
  bright core, `glowAqua`/`glowCyan`, with a rare `accentViolet` one; twinkle
  brightness via `sin(time*rate + seed*6.283)`. Optional faint radiating
  tendrils (a few short spokes) for a woodsprite feel; keep it subtle. Near-black
  (or transparent) background so it overlays other surfaces well.

No user config.

## Effect 3 — Glowing Flora (`glowingFlora`)

Growth effect. Reuses **Growing Ivy**'s growth + glow machinery, but rooted at
the BOTTOM edge growing UPWARD (not tracing the surface outline). Dedicated
`struct GlowingFloraView: View { let time: Double }` (fixed palette) with a
per-view `@State startRef` cycle (like `OutlineGlowView`/`GrowingIvyView`) and a
reference-type layout cache:

- **Layout (per cycle, cached):** 3–6 plants rooted at deterministic x positions
  along the bottom edge. Each plant = a main stem (slightly curved, growing
  upward) with a few side-branches; each branch ends in a **glowing flower-pod**.
  Fronds (small fern-like leaf pairs) along stems. All positions/angles seeded
  from `hash01`.
- **Cycle:** **grow** (~12 s) — stems + branches extend upward along their paths
  with a bright growing tip (glow-head like Ivy); flower-pods bloom (scale up +
  brighten) as their branch completes → **breathe/sway** (~hold) — grown plants
  gently sway (`sin(time + x)`) and flower-pods pulse → **fade** → repeat
  (re-seed for variety). Driven by `startRef`, not `time % period` (which snaps).
- **Color:** stems/fronds `glowTeal`/`glowCyan` (glow strokes); flower-pods
  `accentMagenta`/`accentViolet` cores with a cyan halo. Near-black background.

Reuse `GrowingIvyView`'s glow-stroke idiom and arc-length helpers
(`closedLengths`/`pointAt` are already file-private free functions); the growth
paths here are open upward curves rather than the closed outline loop, so it
walks its own stem polylines.

No user config.

## Effect 4 — Bioluminescent River (`bioRiver`)

Flow effect. Reuses `CurlNoiseField` + a stateful mote buffer, like
**Ink in Water**, but with a DIRECTIONAL current (water flows one way). Dedicated
`struct BioRiverView: View { let time: Double }` with a reference-type `@State`
holding the mote array + `lastTime`; `dt` from shared `time` with the same-time
skip.

- **Water base:** vertical gradient `waterDeep`→`waterMid` (darker at bottom).
- **Current:** motes are advected by a base directional velocity (e.g. flowing
  down-screen or diagonally) PLUS a `CurlNoiseField` sample for meander/swirl,
  so the flow reads as a river, not a random swarm. Motes wrap around when they
  exit (respawn at the inflow edge).
- **Motes:** ~120 small glowing particles (`glowCyan`/`glowAqua`), velocity-
  aligned streaks (short tails along flow), a rare brighter `accentViolet`
  glint; blurred `plusLighter` so dense areas pool into glowing eddies.
- **Ripple highlights:** a few faint moving highlight bands / caustic-like
  ridges drifting with the current for water surface shimmer (light, optional).
- Bound mote count + blur for 60fps.

No user config.

---

## Reuse map

| Effect | Reuses | New |
|---|---|---|
| Misty Peaks | glow idiom, `hash01` | stateless parallax + mist Canvas |
| Drifting Spores | `ParticleSwarmSystem` + `nudgeY`, `CurlNoiseField` (Butterflies pattern) | spore bloom sprite |
| Glowing Flora | `GrowingIvyView` growth/glow + arc-length helpers, `startRef` cycle | upward stem growth + flower-pods |
| Bioluminescent River | `CurlNoiseField` + stateful mote buffer (Ink pattern) | directional current + ripples |

## Persistence & compatibility

- New `EffectKind` cases + category are additive. No config structs on `Surface`
  (no user-tunable params), so nothing new to persist and old `.lumora` files
  are unaffected.
- Existing effects/renderers are untouched (purely additive to the category and
  dispatch switches).

## Testing & verification

- No new pure `LumoraKit` logic → no new unit tests (existing 96 must still
  pass — additive changes only).
- One `scripts/verify_<name>.swift` per effect: offscreen `ImageRenderer` at 2–3
  `time` values, asserting non-blank, non-trivial color variance, and
  change-over-time (motion/growth). Mirror each renderer inline with a stub
  where a private view/engine can't be imported (repo convention).
- Human eyeball: render a frame of each and confirm it reads as intended
  (mountains/mist, rising spores, growing glowing plants, flowing river).

## Build order (verified sets of 2)

1. **Misty Peaks + Drifting Spores** — establishes `EffectCategory.bioluminescent`,
   `BioPalette`, and the `bioluminescentEffects` dispatch/@ViewBuilder. Both are
   the most self-contained (stateless backdrop; swarm reuse). Model routing:
   both **Sonnet**.
2. **Glowing Flora + Bioluminescent River** — the more elaborate growth + flow
   effects. Model routing: both **Opus** (stateful cycle / stateful directional
   flow, elaborate rendering).

Each set: `swift build` clean, full `swift test` still 96/96, each verify script
passes, a rendered frame eyeballed. Checkpoint for the user to `swift run` after
each set (none are audio-reactive, so no packaged build needed).

## Out of scope

- User-configurable colors (fixed Pandora palette by decision).
- A single combined "full scene" preset effect (chosen the composable-pieces
  shape; a combined preset could be a later follow-up).
- Audio reactivity (could be a nice future add — e.g. spores/river responding to
  the mic — but not now).
- Photoreal fidelity — this is painterly/stylized bioluminescence, not a
  film-grade render.
