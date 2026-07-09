# Port 4 more effects from lovable-projection-effects → Lumora (set 2)

**Date:** 2026-07-10
**Status:** Approved design, ready for implementation
**Follows:** `2026-07-09-port-reference-effects-design.md` (Voronoi, Metaballs, Hex Grid, Flow Field — shipped, 51 effects total)

## Goal

Port four more generative effects from `../lovable-projection-effects`
(`src/routes/index.tsx`) into Lumora, in two batches of two.

- **Batch 1:** Lissajous, Orbits
- **Batch 2:** Vector Grid, Particle Mesh

## Existing architecture (unchanged)

Same three touchpoints as set 1:
1. **`EffectKind`** (`Sources/LumoraKit/EffectKind.swift`) — new case + `usesColor`/`usesAccent`/`displayName`. Picker auto-populates from `allCases`.
2. **`EffectView.body`** (`Sources/Lumora/Views/SurfaceContentView.swift`) — new arm in the category dispatch `switch`.
3. **A category ViewBuilder** — renderer(s) as `Canvas { ctx, size in draw…(ctx:size:) }` calling private helper methods (extracting into helpers avoids the Swift type-checker timeout — do it from the start, as set 1 did).

**Convention:** stateless (all animation from `time`; helpers `hash01`, `fract`); `Path`/gradient drawing, no per-pixel `ImageData` loops.

## Changes

### EffectKind (append after `flowField`)

New cases: `lissajous`, `orbits`, `vectorGrid`, `particleMesh`.

| case | displayName | usesColor | usesAccent |
|------|-------------|-----------|------------|
| `lissajous` | "Lissajous" | false | false |
| `orbits` | "Orbits" | false | false |
| `vectorGrid` | "Vector Grid" | false | false |
| `particleMesh` | "Particle Mesh" | true | true |

Rationale: Lissajous, Orbits, and Vector Grid are driven by fixed HSL/retro
palettes in the reference and read best that way (like Voronoi/Flow Field).
Particle Mesh maps cleanly onto `color` nodes + `accent` connecting lines.

### EffectView dispatch + new category

New `@ViewBuilder private var geometryEffects` grouping all four (a fresh
category keeps each ViewBuilder switch small for the type-checker), plus:

```swift
case .lissajous, .orbits, .vectorGrid, .particleMesh:
    geometryEffects
```

### Renderers (adapted to Lumora's style)

**Lissajous** (ref 535–558): centered. `R = min(w,h)*0.4`;
`a = 3 + sin(time*0.2)*2`, `b = 4 + cos(time*0.15)*2`, phase `dph = time*0.5`.
Stroke a 600-point polyline `x = sin(a*u + dph)*R`, `y = sin(b*u)*R` for
`u` in `0…2π`. Rainbow stroke `Color(hue: fract(time*40/360), sat 1, bri 0.65)`,
lineWidth ~1.5. Near-black background.

**Orbits** (ref 797–827): centered, recursive nested rings (depth 3). At each
depth draw a faint orbit circle and 5 planets at angle
`ang + time*(0.5 + depth*0.2) + i*2π/5`, radius `size`; planet dot radius
`depth*4`; recurse into `depth-1` at `size*0.45` around each planet with angle
`a*2`. Rainbow hue `hsl(depth*80 + i*30 + time*30)`. Near-black background.
Implement recursion with a nested Swift closure carrying an accumulated
translation/rotation (SwiftUI `GraphicsContext` has no save/restore stack — pass
absolute center + accumulated offset explicitly, or use `ctx.transform`).

**Vector Grid** (ref 1016–1056): synthwave scene, fixed palette (ignores
color/accent). Vertical gradient background (deep purple → magenta band at
mid → near-black lower half); a sun disc (`#ffd166`) near the horizon
(`h*0.55`); cyan perspective grid — 24 vertical lines fanning from the horizon
vanishing point to the bottom edge, plus ~18 horizontal lines marching toward
the viewer via `p = fract(i/18 + time*0.25)`, `y = horizon + p²*(h-horizon)`,
opacity `1-p`.

**Particle Mesh** (ref 217–265): ~80 nodes. Made **stateless**: each node's base
position seeded from its index hash (`hash01`/`fract(sin(i·k)*43758.5)`); animate
by slow deterministic drift `x = (baseX + sin(time*0.15 + i)*driftX)*w +
sin(time + baseX*10)*20`, similar for y (combines the reference's slow velocity
wander + the `sin(t + x*10)*20` wobble, both time-derived — no persisted
velocities). Connect node pairs closer than `maxD ≈ 180` with a line whose
opacity is `(1 - d/maxD)*0.6`, colored `accent`; draw each node as a small disc
in `color`. Near-black background.

## Testing / verification

Same as set 1: `swift build` clean, assign each effect to a surface in the
running app and confirm smooth animation, no regressions. Demo per batch.

## Out of scope

- Feedback Zoom (needs a previous-frame buffer — conflicts with stateless
  convention, deferred like Neon Life was).
- Remaining reference effects: Grid Warp, Water Ripple, Type Beat, Waveform,
  Checker Warp — future sets.
- No picker UI, sample-content, or persistence changes.
