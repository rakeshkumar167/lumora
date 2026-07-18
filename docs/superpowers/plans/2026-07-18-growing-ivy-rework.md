# Growing Ivy Rework — Implementation Plan

**Goal:** Rework the Growing Ivy effect: vines creep across the surface from a user-selectable edge (top-down / bottom-up / left→right / right→left), with sharper pointed leaves, ~2× slower growth, per-leaf shades of green, and occasional small pastel flowers. Keep the grow → hold → autumn/leaf-fall → regrow loop.

**Approved design:** see brainstorm decisions — directional vines (not outline tracing), pastel flowers (white/pale pink/violet/yellow), keep autumn fall.

## Tasks

### Task 1 — `GrowingIvyConfig` (LumoraKit, TDD)
- Create `Sources/LumoraKit/GrowingIvyConfig.swift`: `IvyDirection` enum (`topDown` default, `bottomUp`, `leftToRight`, `rightToLeft`) with `displayName` + unit `growth` `CGVector` (top-left origin, y down); `GrowingIvyConfig { direction }` Codable + tolerant `decodeIfPresent` default `.topDown`.
- Test `GrowingIvyConfigTests`: default direction; growth vectors (topDown = (0,1), rightToLeft = (-1,0)); tolerant decode of `{}` → topDown; all cases have a non-empty displayName.

### Task 2 — Surface config field
- `Surface.swift`: add `public var growingIvy: GrowingIvyConfig?`, init param (`= nil`), assign, and tolerant decode (`decodeIfPresent`). Mirror the existing `fallingLeaves` plumbing. Extend `ProjectCodableTests`-style coverage only if trivial; otherwise rely on build (tolerant decode keeps old files loading).

### Task 3 — Effect rewrite (`GrowingIvyView` in `SurfaceContentView.swift`, lines 271–533)
- Replace outline-tracing with **directional vines**: N vines start spread along the chosen start edge; each grows a distance ≈ the surface extent along `direction.growth`, meandering laterally via `amp·sin(freq·t + phase)`. Grow phase `growDur ≈ 28s` (was 14), then hold → autumn → fall → regrow (kept, scaled).
- Branches sprout off each vine at intervals (side-alternating), carrying leaves; ~1 in 6 branch tips also gets a **flower**.
- **Sharper leaf**: replace the ellipse `leafPath` with a pointed leaf (tip + two side lobes + base) via quad curves.
- **Green shades**: each leaf's base color is a per-leaf green (hash-varied hue/brightness); autumn lerps that to `accent`, then leaves fall (existing fall logic reused).
- **Flower**: 5 small pastel petals + a tiny yellow center; pastel chosen per-flower from {white, pale pink, pale violet, pale yellow}; fades with `stemFade`/leaf opacity in autumn.
- Signature: `GrowingIvyView(color:accent:time:direction:)` — drop `outline` (no longer used).

### Task 4 — Dispatch + properties panel
- `EffectView`: add `var ivy: GrowingIvyConfig? = nil`; pass `ivy: surface.growingIvy` at the call site; dispatch `GrowingIvyView(color:accent:time:direction:(ivy ?? .init()).direction)`.
- `PropertiesPanelView` / `MediaEditor`: add `@Binding var ivy: GrowingIvyConfig?`, pass `ivy: surface.growingIvy`, and a **Growth direction** `Picker` shown when `effectKind == .growingIvy` (options from `IvyDirection.allCases`, labels = `displayName`).

### Task 5 — Verify
- `swift test` green (+ config tests). `swift build`. Launch packaged app, set a surface to Growing Ivy, screenshot at least one direction; adjust leaf sharpness / green shades / flower frequency if needed. Show the screenshot.

## Notes
- `IvyDirection` needs `import CoreGraphics` for `CGVector`.
- Old `.lumora` files without `growingIvy` still load (tolerant decode → nil → default topDown).
