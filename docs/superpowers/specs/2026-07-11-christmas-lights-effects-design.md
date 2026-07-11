# Christmas Lights Effect Set — Design

**Date:** 2026-07-11

## Goal

Add a festive **"Christmas Lights"** effect category with four effects: a
decorated Christmas tree whose lights twinkle, and three variations of
horizontally-hung string lights (chasing, multi-colored, twinkling) that sag
between pinned ends like real strung lights.

## Scope

Four new `EffectKind` cases in a new `.christmas` `EffectCategory`:

1. **Christmas Tree** (`christmasTree`) — renders the bundled `christmas-tree.png`
   fitted to the surface, then overlays animated twinkle glints. **Glints only
   appear on the tree, never on the dark background.**
2. **Chasing Lights** (`chasingLights`) — a lit wave runs along sagging strands.
3. **Multi-Colored Lights** (`multiColorLights`) — steady palette bulbs
   alternating along the strands, with a gentle shimmer.
4. **Twinkling Lights** (`twinklingLights`) — bulbs randomly fade on/off out of
   phase along the strands.

All four use a **fixed festive palette** (red, green, gold, blue, warm-white).
None use the surface's primary/accent colors → `usesColor` / `usesAccent` are
both `false` for all four.

## Architecture

Follows the existing effect pattern: `EffectKind` (LumoraKit) + a `Canvas`-based
renderer group in `EffectView` (`SurfaceContentView.swift`) driven by the global
`time`, warpable, with glow via the established `drawLayer { blur; plusLighter }`
recipe.

### LumoraKit (pure, unit-tested)

- **`EffectKind.swift`** — add the 4 cases; `.christmas` category; display names;
  `usesColor`/`usesAccent` return `false` for all four; category grouping.
- **`ChristmasLights.swift`** (new) — pure geometry + palette, size-driven, no UI:
  - `static let palette: [RGBAColor]` — red, green, gold, blue, warm-white.
  - `struct Strand { var bulbs: [CGPoint] }` — bulb centers in the given pixel space.
  - `static func strands(in size: CGSize) -> [Strand]` — computes the sagging
    layout:
    - **Strand count** auto-scales to height: `max(2, round(size.height / rowSpacing))`
      where `rowSpacing ≈ 90` pt.
    - Each strand's pins sit at a small horizontal inset (`≈ 6%` of width) at the
      strand's base height `y0`.
    - **Bulb count per strand** auto-scales to width:
      `max(3, round(size.width / bulbSpacing))` where `bulbSpacing ≈ 55` pt.
    - Bulb `x` values are evenly spaced between the pins (inclusive of both ends).
    - **Parabolic sag**: for normalized position `t ∈ [0,1]` across the strand,
      `y = y0 + sag * 4 * t * (1 - t)` (0 at both pins, max `sag` at the middle),
      where `sag ≈ 0.35 * rowSpacing`.
  - Determinism: no randomness in geometry (twinkle randomness is per-bulb phase
    derived from bulb index in the renderer, so it's stable frame-to-frame).

### Lumora app (rendering)

- **`SurfaceContentView.swift`** — new `christmasEffects` `@ViewBuilder` group,
  dispatched from `EffectView.body` for the 4 cases:
  - **Tree**: load the image once (cached), draw it aspect-fit centered on a dark
    fill, then overlay twinkle glints (soft radial-gradient star flares) at
    precomputed on-tree points. Each glint pulses on its own phase; warm-white and
    gold dominate with occasional red/blue.
  - **Strings**: `ChristmasLights.strands(in:)` → draw a thin wire polyline through
    each strand's bulbs, then a glowing bulb at each point. Per-effect bulb state:
    - chasing: brightness = f(distance-along-strand − time·speed), a moving bright band.
    - multiColor: bulb color = palette[(index) % palette.count], brightness a slow
      per-bulb shimmer.
    - twinkling: brightness = twinkle(time, seed=bulbIndex) — smooth random fade.
- **Tree light masking** — `ChristmasTreeMask` helper (app-side, needs the image):
  downsample the bundled image to a small grid (e.g. 48×72), compute per-cell
  luminance, and keep cells above a threshold as normalized on-tree points. The
  vignetted dark background falls below the threshold, so glints are confined to
  the tree. Computed once and cached (the image is fixed).

### Resources

Move `Sources/Effects-data/christmas-tree.png` → `Sources/Lumora/Resources/`
(the `Bundle.module` resource dir). Load via
`Bundle.module.url(forResource: "christmas-tree", withExtension: "png")`, matching
the existing `AppAssets` pattern.

## Data flow

`Surface.media = .effect(kind, _, _)` → `EffectView(kind:…, time:)` →
`christmasEffects` → `Canvas` draws using `ChristmasLights` geometry (strings) or
the cached image + mask (tree), animated by `time`. Colors come from the fixed
palette, so the primary/accent params are ignored for these kinds.

## Error handling

- Tree image missing from the bundle: draw a dark fallback fill with the twinkle
  glints on a default triangular region (so the effect still animates rather than
  rendering blank). Not expected in practice; keeps the renderer total.
- `ChristmasLights.strands` never returns empty (min 2 strands, min 3 bulbs).

## Testing

- **Unit tests** (`ChristmasLightsTests` in LumoraKit):
  - strand count scales with height and is ≥ 2.
  - bulb count per strand scales with width and is ≥ 3.
  - each strand's first/last bulb sit at the pin height `y0` (sag = 0 at ends);
    the middle bulb sits below `y0` by ~`sag` (arc dips downward).
  - all bulbs lie within the surface bounds.
  - palette has 5 distinct colors.
- **Offscreen verification** (`ImageRenderer` → PNG, one per effect): confirm the
  tree glints land on foliage (not the background), strands visibly sag, and each
  string variation's bulbs animate as intended.

## Out of scope (YAGNI)

- User-configurable colors for these effects (fixed festive palette by design).
- Bulb shape/spacing controls in the properties panel.
- Vertical or diagonal strand orientations (horizontal only, per the request).
- Multiple bundled tree images / tree selection.
