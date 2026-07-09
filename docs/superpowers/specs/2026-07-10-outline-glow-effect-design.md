# Outline Glow effect — accumulating edge runner

**Date:** 2026-07-10
**Status:** Approved design, ready for implementation

## Goal

An effect that traces a glowing light along the **chosen surface's outline**,
starting from one point and progressing around the edge, leaving a persistent
glow behind the leading point until the whole outline is lit — then holding with
a gentle breathing pulse. A "running light that keeps its trail."

## Key constraint: global clock

`time` passed to effects is `timeline.date.timeIntervalSinceReferenceDate` — a
global, monotonic clock, NOT reset when the effect is assigned. A literal
"fill once, ever" would already be complete before first view. Therefore the
effect runs on a **slow cycle** (fill sweep → long breathing hold → re-sweep),
and the outline never drops fully dark (a dim floor persists) so it always reads
as lit and alive.

## New: outline geometry plumbing

Effects today are shape-agnostic rect fills. This effect must trace the real
surface edge. Add a lightweight descriptor passed into `EffectView`:

```swift
enum EffectOutline { case rect; case polygon([CGPoint]); case ellipse }
```

- Computed in `SurfaceContentView` from `surface.shape` + `canvasSize`:
  - `.quad` → `.rect` — the effect Canvas is the full content rect and is then
    perspective-warped so the rect border lands on the real quad edges.
  - `.polygon` → `.polygon(pts)` where pts are the surface's local outline
    vertices **normalized to 0…1** against the shape's bounding box (the Canvas
    for polygon/ellipse fills that bounding box).
  - `.ellipse` → `.ellipse` — traced as the ellipse inscribed in the Canvas.
- `EffectView` gains `var outline: EffectOutline = .rect`. Only `outlineGlow`
  reads it; all other effects keep the default.

## EffectKind

Append `case outlineGlow` after `depthBreaker`. `displayName` "Outline Glow".
`usesColor` stays default true (glow color); add `.outlineGlow` to the
`usesAccent` true-list (running head color).

## Dispatch + category

New `@ViewBuilder private var edgeEffects` with `case .outlineGlow`, and a
dispatch arm `case .outlineGlow: edgeEffects`.

## Renderer (`drawOutlineGlow`), stateless

1. **Build the outline** as a closed polyline in Canvas coords from `outline`
   + `size`:
   - `.rect` → 4 corners.
   - `.polygon(norm)` → `norm.map { ($0.x·w, $0.y·h) }`.
   - `.ellipse` → sample ~120 points around the inscribed ellipse.
   Compute per-vertex cumulative arc length and total perimeter `L`.
2. **Timing:** `P ≈ 9` (cycle), `fillDur ≈ 3`. `localT = time.truncatingRemainder(dividingBy: P)`.
   `headFrac = min(localT / fillDur, 1)` — grows 0→1 during the sweep, then held
   at 1 for the breathing hold. `inHold = localT >= fillDur`.
   `pulse = 0.78 + 0.22·sin(time·2)` applied during hold.
3. **Draw passes** (each glow pass inside `ctx.drawLayer { $0.addFilter(.blur(radius:)) }`,
   `.plusLighter` for additive glow, round caps):
   - **Dim base:** full closed outline stroked at `color.opacity(~0.22)` — the
     persistent floor; never fully dark.
   - **Lit portion:** the sub-path from arc 0 to `headFrac·L`, stroked bright in
     `color` (glow ~7pt + crisp core ~1.5pt). During hold this is the whole
     outline, its brightness scaled by `pulse`.
   - **Comet head:** only while `!inHold`, a bright `accent` dot (+ short trailing
     segment) at the point at arc length `headFrac·L`.
4. **Arc-length helpers:** `subPath(upToLength:)` walks vertices accumulating
   full segments then a partial last segment; `point(atLength:)` similar. Keep
   these as small private helpers to avoid Swift type-checker timeouts.

## Testing / verification

`swift build` clean. Assign Outline Glow to a **quad**, a **polygon**, and an
**ellipse** surface; confirm the glow traces each true outline, fills, then
breathes, and never goes fully dark. Demo.

## Out of scope

- Configurable start point / direction (fixed start = first outline vertex / angle 0).
- Multiple simultaneous runners.
- Respecting per-surface start offset UI.
