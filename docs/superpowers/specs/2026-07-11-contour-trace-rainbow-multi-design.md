# Contour Trace — Rainbow Color & Multiple Images Design

**Date:** 2026-07-11

## Goal

Extend the Contour Trace media type with (1) a **rainbow** option — the pen
traces with a color that changes along the path (≈20 colors in gradient order),
and (2) **multiple images** — several images are traced in sequence, each
overlaying the previous and staying lit, building up a layered composition.

## Current behavior

`MediaAssignment.contourTrace(URL, RGBAColor, Double)` = (image, pen color,
speed). `ContourTraceModel` extracts + caches Vision contours for one image and
orders them into a single pen "walk". `ContourTraceContent` (a `Canvas`)
animates one glowing pen along the walk: sweep → hold → fade → repeat, drawing
the outline in the fixed pen color.

## Model change

Extend the case to:

```swift
case contourTrace([URL], RGBAColor, Double, Bool)   // images, pen color, speed(×), rainbow
```

- `[URL]` — one or more source images, traced in array order.
- `RGBAColor` — pen color (used only when `rainbow == false`).
- `Double` — trace speed multiplier (unchanged).
- `Bool` — rainbow on/off.

**Backward compatibility:** `MediaAssignment` uses Swift's synthesized `Codable`.
Changing this case's payload means a *previously saved* project containing a
Contour Trace surface will fail to decode (the old `_0` was a single `URL`, and
there was no `_3`). Only that one case is affected — every other media type and
project still opens. Acceptable at this dev stage; noted here and in the
backlog. No migration shim (matching the synthesized enum JSON by hand for all
cases would be fragile and risk breaking the others).

## Rainbow

A per-media toggle.

- **On:** each drawn segment is colored by its position along the *entire*
  concatenated trace. Hue = `(cumulativeArcLength / totalLength + time * drift)`
  wrapped into `0…1` — one spectrum pass across the whole trace, so the travel
  shows the full red→violet gradient once. Rendered as ~24 hue **bands** (24
  sub-paths, one stroke each) so it reads as "≈20 colors in gradient order"
  while staying cheap. The pen tip uses the local hue. `drift ≈ 0.03` gives a
  gentle shift over time.
- **Off:** the whole trace uses the fixed pen color (current behavior).

A tiny pure helper lives in LumoraKit and is unit-tested:

```swift
enum ContourTrace {
    static let rainbowBandCount = 24
    /// Band index 0..<bandCount for a point at `length` along a trace of
    /// `total`, offset by `phase` (0…1). Wraps.
    static func rainbowBand(length: CGFloat, total: CGFloat, phase: Double) -> Int
}
```

## Multiple images

- `ContourTraceModel.load([URL])` loads every URL (reusing the existing per-URL
  contour cache), orders each image's contours into its own walk
  (`orderAsWalk`), then **concatenates** the walks in array order into one
  `contours` list. `totalLength` is the sum.
- Because the walks are concatenated in order, the pen naturally traces image 1
  fully, then image 2, etc. All completed contours stay drawn at full
  brightness, so later images overlay earlier ones (build-up). No per-image
  fade.
- **Timing:** `sweepDur = 6.0 * max(1, imageCount) / speed` (≈6 s per image at
  1×), then `holdDur` + `fadeDur` as today; the whole cycle repeats.
- The concatenation order is deterministic (input array order) and is just an
  array append, so it needs no dedicated test; the correctness-critical pieces
  are per-image `orderAsWalk` (already present) and the rainbow banding (tested).

## UI (Properties panel, Contour Trace editor)

- **Images list:** one row per URL showing the filename with a trash button;
  removing is disabled when only one image remains.
- **Add Image…** button → `NSOpenPanel` with `allowsMultipleSelection = true`;
  appends the chosen URLs.
- **Rainbow** toggle.
- **Pen Color** swatches — shown only when Rainbow is off.
- **Trace Speed** slider (unchanged).

Selecting the Contour Trace media type still prompts for an image and seeds
`contourTrace([url], .green, 1.0, false)`.

## Rendering (ContourTraceContent)

- Build the `full` (completed) and `partial` (under the pen) geometry as today,
  but when `rainbow` is on, accumulate segments into `rainbowBandCount` separate
  `Path` buckets (by `ContourTrace.rainbowBand`) and stroke each bucket once
  with `Color(hue:)`; keep the glow underlay per band. When off, keep the single
  two-path stroke.
- Pen tip color: local hue when rainbow, else pen color.

## Error handling

- Empty `[URL]` (all removed — prevented by the min-1 UI, but defensively):
  render nothing (dark fill only).
- A URL that yields no contours contributes nothing; others still trace.

## Testing

- **Unit (LumoraKit):**
  - `MediaAssignment.contourTrace` round-trips through `JSONEncoder`/`Decoder`
    with multiple URLs + rainbow flag.
  - `ContourTrace.rainbowBand` returns `0..<bandCount`, is monotonic across a
    single spectrum pass, and wraps with phase.
- **Offscreen render:** a script that traces two synthetic images with rainbow
  on, confirming the gradient bands and that both images' outlines appear
  (build-up), saved to PNG for visual check.

## Out of scope (YAGNI)

- Per-image color/speed overrides.
- Reordering images in the list (add/remove only; array order = trace order).
- Rainbow for Laser Trace (this change is Contour Trace only).
- Codable migration of old single-image contourTrace projects.
