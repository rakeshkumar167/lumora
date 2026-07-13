# Pendulum Paint effect

Date: 2026-07-14

## Concept

A new generative effect simulating the *painting* produced by a rotating paint
bucket that drips paint onto a canvas as it sways. We simulate the accumulated
painting, not the bucket. The hidden emitter follows a **rotary harmonograph**
path — a swaying pendulum plus a rotation, both with gentle amplitude decay —
which traces spirograph-like looping rosettes, exactly like a real pendulum
paint rig.

## Motion — harmonograph

Emitter position as a function of a path parameter `s` (radians):

```
x(s) = Ax1 * sin(fx1*s + px1) * e^(-d*s) + Ax2 * sin(fx2*s + px2) * e^(-d*s)
y(s) = Ay1 * sin(fy1*s + py1) * e^(-d*s) + Ay2 * sin(fy2*s + py2) * e^(-d*s)
```

- One low-frequency term per axis = the **sway** (pendulum arc).
- One higher-frequency term per axis (near-integer ratio to the sway) = the
  **rotation** of the bucket, producing the looping rosette.
- `e^(-d*s)` = amplitude **decay**, so the figure spirals inward as a real
  swinging bucket loses energy.

Output is normalized to the surface's unit box (centered, scaled to fit with a
margin).

### Different pattern every run

Each cycle re-seeds all coefficients (frequency ratios, phases, decay,
amplitudes) from the integer cycle index via a small deterministic PRNG
(splitmix64-style). Same cycle index always yields the same figure, so the
effect stays a **pure function of `time`** — required so the editor and the
projector render identically (no live/stateful simulation). Every continuous
run paints a distinctly different figure.

## Cycle: draw → hold → fade

`cycle ≈ 90s`, matching the generative fractal effects' generate→hold→vanish
rhythm:

- **Draw** (~0–75%): parameter `s` sweeps `0 → sMax`; paint is laid down
  progressively along the arc-length (same reveal technique as `circuitTrace`).
- **Hold** (~75–92%): the finished painting rests at full opacity.
- **Fade** (~92–100%): opacity ramps to zero, then the next cycle index selects
  a new figure.

## Rendering / paint feel

- Drawn in a `Canvas { drawPendulumPaint(ctx:size:) }` in `SurfaceContentView`.
- A bright **wet paint head** (glowing blob via `drawLayer` + `.blur` +
  `.plusLighter`) rides the current tip during the draw phase, selling the
  "dripping as it sways" motion (same head technique as circuit trace).
- **Line width varies with speed**: where the sampled path moves slowly the
  stroke widens (paint pools); fast stretches thin out.
- Light touch (optional, kept cheap): an occasional heavier droplet that runs a
  short way straight down from a slow point.

## Color

New optional `PaintDripConfig { rainbow: Bool = true }` struct on `Surface`,
following the existing `MarqueeConfig` / `GameOfLifeConfig` / `FallingLeavesConfig`
optional-struct-with-tolerant-decode pattern. A **Rainbow** toggle in the
properties panel:

- **Rainbow on** (default): hue advances along the paint's arc-length — layered
  spectrum ribbons.
- **Rainbow off**: uses the surface's **primary color** (`usesColor = true`)
  with subtle per-layer lightness variation so overlapping passes read as depth.

## Integration points

- `EffectKind`: add `case pendulumPaint`; `displayName = "Pendulum Paint"`;
  `usesColor = true`; `usesAccent = false`; `category = .motion`.
- `Surface`: add `paintDrip: PaintDripConfig?` with tolerant decode; thread
  through `SurfaceContentView` like the other configs.
- `SurfaceContentView`: render case in `motionEffects` (or wherever `.motion`
  effects dispatch), plus `drawPendulumPaint`.
- Properties panel: Rainbow toggle shown when the effect is `pendulumPaint`.

## Pure, testable core (LumoraKit)

A `PendulumPaint` helper in LumoraKit holds the math with no SwiftUI dependency:

- `PendulumPaint.coefficients(cycle: Int) -> Coefficients` — deterministic seed.
- `PendulumPaint.point(_ s: Double, _ c: Coefficients) -> CGPoint` (unit space).
- `PendulumPaint.samples(cycle:count:) -> [CGPoint]` — the polyline.

Unit tests: determinism (same cycle → identical samples; different cycles →
different), points stay within the normalized box, sample count/endpoints.

## Backward compatibility

`paintDrip` is optional and decoded tolerantly, so existing `.lumora` projects
load unchanged. No existing effect is altered.
