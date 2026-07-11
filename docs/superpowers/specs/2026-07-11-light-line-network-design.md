# Light Line Network — Design

**Date:** 2026-07-11
**Status:** Approved, ready for implementation plan

## Summary

A new drawable for Lumora: a **light line network** you draw on the canvas. It
renders as a glowing line with a moving **tracer** that flows across its joints.
Lines can connect and fork; a pulse emitted from a chosen source joint spreads
through the whole network, splitting at forks, filling each segment as it
passes. Once the network is fully lit it holds briefly, then resets and refills.

This is a genuinely new kind of drawable — an **open polyline graph** — distinct
from the existing closed-shape `Surface` model (quad / polygon / ellipse). It is
modeled as its own standalone type (`LightLine`) living alongside surfaces, not
shoehorned into `Surface`.

## Motivation & requirements

Captured from brainstorming:

- Draw a line that, on projection, shows a **glow effect with a line tracer**.
- Place **joints** and **connect** with other lines → a network.
- Lines can **fork** (a joint hosting 3+ segments).
- The tracer flows across joints **as one sequence**; at a fork it **splits**
  into multiple tracers (like current/water spreading through the network).
- Origin is a chosen **source joint**. Behavior: **fill → hold → reset** — the
  pulse spreads and leaves each segment lit until the whole network glows, holds
  briefly, then goes dark and refills from the source.
- Drawing is a **click-to-drop-joints pen tool**; clicking near an existing
  joint snaps/connects to it (that is how lines connect and forks form).

## Why a graph model

"Multiple lines that link up, with forks" is naturally a **graph**: joints are
nodes, segments are edges, connecting/forking is just sharing a node. This makes
the split-at-fork wavefront and the fill→hold→reset cycle fall out cleanly:
precompute each node's shortest-path distance from the source, then advance a
single scalar "fill front" over that distance.

Rejected alternatives:

- **`SurfaceShape.line` inside `Surface`** — reuses plumbing but fights every
  closed-shape assumption (media fill, corner-handle warp, rotation-about-center)
  and cannot represent a fork shared across two lines. Rejected.
- **Each line its own object + a connection registry** — scatters the graph
  across objects; the wavefront tracer has to reassemble the graph anyway.
  Rejected.

## Data model (`LumoraKit`, pure + unit-tested)

One `LightLine` = one network = one sidebar item.

```
LightLine
  id: UUID
  name: String
  isVisible: Bool
  opacity: Double
  joints:   [Joint]        Joint   { id: UUID, point: CGPoint (normalized 0…1) }
  segments: [Segment]      Segment { a: Joint.ID, b: Joint.ID }
  sourceJointID: Joint.ID?
  style: LightLineStyle

LightLineStyle
  color: RGBAColor          // primary line color
  glowColor: RGBAColor      // accent / glow tint
  thickness: Double         // line width in points
  glowRadius: Double        // blur radius for the glow layer
  fillDuration: Double      // seconds for the front to reach maxDistance
  holdDuration: Double      // seconds fully-lit before reset
```

A joint with **degree ≥ 3** is a fork. Segments are undirected edges.

### Pure graph helpers (unit-tested, no UI)

- **adjacency** — joint → incident segments / neighbor joints.
- **distance-from-source** — Dijkstra over Euclidean segment lengths (in
  normalized space) → shortest-path distance from `sourceJointID` to every
  reachable joint.
- **maxDistance** — the largest reachable joint distance (the full-fill target).
- Joints with no path from the source have undefined distance and render dim
  (never lit).

## Fill / tracer animation

Driven by a single scalar **front distance** `F(t)`:

- A stateful `LightLineView` captures its start time in `.onAppear`
  (the `time` passed to Lumora effects is a global monotonic clock, so we must
  keep our own start reference) → `elapsed`.
- Cycle period = `fillDuration + holdDuration`. Let `p = elapsed mod period`.
  - Fill phase (`p < fillDuration`): `F = (p / fillDuration) · maxDistance`.
  - Hold phase: `F = maxDistance` (everything lit).
  - At period wrap: reset to `F = 0` and refill.
- A segment lights **from its endpoint nearer the source, outward**:
  `dNear = min(dist(a), dist(b))`, `segLength = |a − b|`,
  `litFraction = clamp((F − dNear) / segLength, 0, 1)`.
- At a fork every outgoing segment shares the same near-endpoint distance, so
  they all begin lighting at once → the pulse **splits** naturally.
- Lit portions **stay lit** through the fill phase (this is a fill, not a
  trailing comet).
- **Tracer head(s)** = extra-bright glow blobs positioned at graph-distance
  ≈ `F` along each currently-filling segment (there can be several after forks).
  This is the moving "line tracer."

Edge cases:

- **Cycles:** an edge lights from its nearer end only. Clean for the tree/fork
  shapes this is built for; acceptable if a loop closes slightly asymmetrically.
- **No source set / single joint / no segments:** render the dim base structure,
  no animation.

## Rendering (`Lumora`, SwiftUI `Canvas`)

`LightLineView` draws, in order:

1. **Base structure** — all segments faint (dim stroke), so unlit geometry stays
   visible while editing.
2. **Lit portions** — bright stroke plus glow via
   `ctx.drawLayer { $0.addFilter(.blur(radius: glowRadius)) }` with
   `layer.blendMode = .plusLighter` (Lumora's established additive-glow recipe).
3. **Tracer head glow** — bright blob(s) at the front distance.

Geometry is drawn directly in normalized → canvas space with **no homography
warp** (same convention as polygon / ellipse surfaces), so it renders
identically in `RoomCanvasView` (preview) and `ProjectionView` (fullscreen).

## Drawing interaction (pen tool)

New tool mode `.pen` alongside `.arrow` / `.hand`. With a `LightLine` selected:

- **Click** on empty canvas drops a joint, connected to the last-placed joint by
  a new segment (extends the current stroke).
- **Click near an existing joint** (within a snap radius) connects to that joint
  instead of creating a new one → strokes join and forks form.
- **Return / Esc / double-click** ends the current stroke; the next click starts
  a fresh stroke (a new disconnected chain, unless it snaps to an existing
  joint).
- **Drag a joint** to reposition it.
- **Right-click a joint** → *Set as source* / *Delete joint* (deleting removes
  incident segments).

A `LightLineHandlesOverlay` renders joint handles and a distinct **source
marker**, mirroring how `HandlesOverlay` works for surfaces.

Scope: the pen tool edits **one selected `LightLine` at a time**. You can create
many independent networks; forks form within a single `LightLine`.

## Persistence, sidebar, properties

- `Project` / `.lumora` JSON gains `lightLines: [LightLine]`, decoded with
  `decodeIfPresent` so older files (without the field) still load.
- **Sidebar** gains a *Light Lines* section parallel to surfaces: create,
  rename (inline), delete, toggle visibility, select.
- **Properties panel** for a selected line: primary color + glow color swatches
  (12 swatches + full `ColorPicker`, matching effect color controls), thickness,
  glow radius, fill duration, hold duration; joint count and source status.

## Style defaults

- Line color: electric cyan.
- Glow color: brighter accent tint.
- Thickness ≈ 3 pt.
- Glow radius ≈ 12.
- Fill duration ≈ 3 s.
- Hold duration ≈ 1.5 s.

## Testing

- **LumoraKit unit tests:** adjacency, distance-from-source (incl. a fork and a
  disconnected joint), `maxDistance`, `litFraction` math at representative fronts,
  and backward-compatible decode of a `.lumora` file lacking `lightLines`.
- **Renderer verification:** exercise `LightLineView`'s draw closure offscreen
  via `ImageRenderer(content:).nsImage` → PNG and inspect (base structure, a
  partial fill mid-network, a fork split, and full-hold), per the offscreen
  verification note in the rendering memory.

## Out of scope (YAGNI)

- Branch-selection / Euler-path traversal modes (only fork-split fill is built).
- Continuous multi-pulse streams (only single fill→hold→reset).
- Homography warping of lines.
- Freehand-drag drawing.
- Per-segment individual styling.
