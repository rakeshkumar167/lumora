# Lumora

A macOS app for **projection mapping**: treat a room (or any surface) as a
digital canvas, define projection surfaces, assign generative or image-based
media to each, preview the whole composition live, and send fullscreen output to
a projector.

## Run it

```sh
swift run          # build + launch
swift build        # build only
swift test         # run the homography unit tests
```

Requires macOS 14+ and the Xcode command-line tools (Swift 5.9+). You can also
open the package folder in Xcode and hit Run.

## What it does

### Surfaces
- **Three shapes** — 4-corner **quads** (perspective-warped), N-point
  **polygons** (3–12 sides), and **ellipses**.
- **Direct manipulation** — drag vertex handles to reshape, or grab the whole
  surface to move it (Arrow vs. Hand pointer modes).
- **Per-surface rotation** — a canvas rotation knob plus a panel slider; quads
  fold rotation into the homography, polygons/ellipses rotate their clipped media.
- **Live preview** — the room canvas shows the real, animating composition.

### Media
Each surface can display:
- **Solid color**
- **51 built-in generative effects**, each animated and warp-aware, with
  primary + accent color controls. They're organized into categories:
  - *Gradients & washes* — Grid, Color Wash, Gradient Sweep, Breathing Glow,
    Rainbow Sweep, Radial Pulse, Aurora, Plasma, Strobe
  - *Patterns & geometry* — Checkerboard, Barber Stripes, Color Bars, Neon Grid,
    Halftone Dots, Moiré, Truchet Tiles, Concentric Polygons, Spirograph
  - *Particles & nature* — Sparkle, Starfield Warp, Fireflies, Snow, Lava Lamp,
    Fire, Rain, Lightning, Bubbles, Falling Leaves
  - *Waves & motion* — Waves, Equalizer Bars, Vortex, Tunnel, Pendulum Wave,
    Kaleidoscope, Prism Falls (continuous spectrum waterfall), Liquid Slosh
    (confined-box tank liquid)
  - *Retro & digital* — TV Static, CRT Scanlines, Matrix Rain, Glitch, Pixel
    Dissolve, DVD Bounce, Marquee Text
  - *Fractals* — Fractal Tree, Barnsley Fern, Koch Snowflake, Sierpinski
    Triangle. Each runs a ~2-minute **generate → hold → vanish** cycle, re-seeded
    each cycle so it restarts from a different starting point.
  - *Fields* — Voronoi Cells (drifting Worley shatter), Metaballs (blobby
    merge), Hex Grid (pulsing honeycomb), Flow Field (perlin-ish particle
    streams)
- **Imported still image**
- **Looping muted video**
- **Laser Trace** — takes an image, edge-detects it (Core Image `CIEdges`), and a
  glowing laser bar sweeps bottom→top; edges light up in the laser color as it
  passes and persist into the full outline, which holds and fades before
  repeating. Selectable color + adjustable trace speed.
- **Contour Trace** — takes an image, detects contours (Vision
  `VNDetectContoursRequest`), and a single pen tip draws them one at a time,
  navigating edge to edge. Selectable color + adjustable trace speed.

### Projection & project files
- **Projection mode** — opens fullscreen output on a second display (projector)
  if present, otherwise the main display.
- **Save / Open** — projects persist to `.lumora` JSON (⌘S / ⌘O).
- **Surface list & properties panel** — add / delete / rename (inline in the
  sidebar) / hide surfaces, set opacity, pick shape, and assign media.

## Architecture

- **`LumoraKit`** — pure, UI-free geometry + model core (unit-tested `Homography`
  math; `Surface`, `MediaAssignment`, `EffectKind`, `RGBAColor` value types). No
  SwiftUI/AppKit dependency.
- **`Lumora`** — the SwiftUI app (state store, canvas/editor/projection views,
  effect renderers).

Perspective warping uses the pure `Homography` (rect → quad) driven through
SwiftUI's native `ProjectionTransform`. Generative effects are stateless
`Canvas` closures driven only by a shared `time`, grouped into per-category
`@ViewBuilder` renderers.

## Roadmap

Per-surface playback settings (loop / volume / speed / fill mode),
projector-native output to remove letterboxing, room-photo import to replace the
blank backdrop, a real document model (current-doc tracking, recent files), and
optional skeletonization for single-line contour tracing. See `docs/BACKLOG.md`.
