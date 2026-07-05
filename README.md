# Lumora

A macOS app for creating projection-mapped experiences — treat a room as a
digital canvas, define projection surfaces, assign media, preview live, and
send fullscreen output to a projector.

See the design/requirements doc: [`docs/superpowers/specs/2026-07-05-spatialcanvas-design.md`](docs/superpowers/specs/2026-07-05-spatialcanvas-design.md).

## Run it

```sh
swift run          # build + launch
swift build        # build only
swift test         # run the homography tests
```

Requires macOS 14+ and the Xcode command-line tools (Swift 5.9+).

You can also open the folder in Xcode (`File ▸ Open` the package) and hit Run.

## What works today (MVP)

- **Room canvas** — launches with a blank neutral canvas (placeholder until you
  import a room photo) and two demo surfaces so you see animation immediately.
- **Surfaces** — 4-corner quads. Drag the corner handles on the selected
  surface to reshape/perspective-correct it in real time.
- **Media** — solid color; **20 built-in animated effects** (Color Wash,
  Gradient Sweep, Breathing Glow, Rainbow Sweep, Radial Pulse, Checkerboard,
  Waves, Plasma, Strobe, Sparkle, Barber Stripes, Color Bars, Equalizer Bars,
  Starfield Warp, Neon Grid, Vortex, Aurora, Fireflies, Snow, Lava Lamp);
  imported still image; or a looping video.
- **Live preview** — the canvas shows the real composition, playing.
- **Projection mode** — the **Project** button (⌘P) opens fullscreen output on
  a second display (projector) if present, else on the main display. Esc exits.
- **Surface list & properties** — add / delete / rename / hide surfaces, adjust
  opacity, and change media assignment.

## Architecture

- `LumoraKit` — pure, UI-free geometry + model core (fully unit-tested
  homography math, `Surface`/`MediaAssignment`/`Project` value types).
- `Lumora` — the SwiftUI app (state store, views, sample content).

Perspective warping uses the pure `Homography` (rect → quad) driven through
SwiftUI's native `ProjectionTransform`. The renderer is intentionally isolated
so a Metal backend can be added later without touching the model or editor.

## Not yet built (next up)

Project save/open wiring, polygon (N-point) surfaces, per-surface playback
settings (loop toggle, volume, speed, fill mode), and the future roadmap items
from the spec (AI surface detection, auto-calibration, multi-projector sync,
edge blending, timelines).
