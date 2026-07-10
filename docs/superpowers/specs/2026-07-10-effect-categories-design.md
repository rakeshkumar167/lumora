# Effect categories in the picker

**Date:** 2026-07-10
**Status:** Approved design, ready for implementation

## Goal

With 58 effects, the single flat "Effect" dropdown is unwieldy. Add a
**Category** dropdown that filters a second **Effect** dropdown, so the effect
list shown at once is small.

## Model (`Sources/LumoraKit/EffectKind.swift`)

Add `EffectCategory` (String, Codable, CaseIterable, Identifiable) with 10 cases
mirroring the existing per-category renderer groups in `EffectView.body`:

| category | displayName | effects |
|----------|-------------|---------|
| gradients | Gradients & Washes | grid, colorWash, gradientSweep, breathingGlow, rainbowSweep, radialPulse, aurora, plasma, strobe |
| patterns | Patterns & Geometry | checkerboard, barberStripes, colorBars, neonGrid, halftoneDots, moire, truchet, concentricPolygons, spirograph |
| nature | Particles & Nature | sparkle, starfieldWarp, fireflies, snow, lava, fire, rain, lightning, bubbles, fallingLeaves |
| motion | Waves & Motion | waves, equalizer, vortex, tunnel, pendulumWave, kaleidoscope, prismFalls, liquidSlosh |
| retro | Retro & Digital | tvStatic, crtScanlines, matrixRain, glitch, pixelDissolve, dvdBounce, marqueeText |
| fractals | Fractals | fractalTree, barnsleyFern, kochSnowflake, sierpinskiTriangle |
| fields | Fields | voronoi, metaballs, hexGrid, flowField |
| curvesGrids | Curves & Grids | lissajous, orbits, vectorGrid, particleMesh |
| ambient | Ambient & Illusion | livingTexture, depthBreaker |
| edge | Edge | outlineGlow |

- `EffectKind.category: EffectCategory` — an **exhaustive** switch (compiler then
  forces every future effect to declare a category).
- `EffectCategory.effects: [EffectKind]` = `EffectKind.allCases.filter { $0.category == self }`
  (preserves canonical enum order).

## UI (`Sources/Lumora/Views/PropertiesPanelView.swift`)

Replace the single `Picker("Effect", … ForEach(EffectKind.allCases))` in the
`.effect` case with two pickers:

- **Category** — selection bound to `effectKind.category`; on change, set
  `media = .effect(newCategory.effects.first!, primary, accent)` (every category
  is non-empty).
- **Effect** — selection bound to `effectKind`; `ForEach(effectKind.category.effects)`
  so only the current category's effects are listed.

`usesColor` / `usesAccent` color controls are unchanged, below the pickers.

## Testing / verification

`swift build` clean. In the app: the Category dropdown lists 10 groups; picking
one shows only that group's effects and auto-selects its first; picking an effect
still assigns it and keeps the color controls working. No model/persistence
change (media still stores the `EffectKind`; category is derived).

## Out of scope

- Reordering effects within categories.
- Search/filter box.
- Persisting the last-selected category (derived from the effect each time).
