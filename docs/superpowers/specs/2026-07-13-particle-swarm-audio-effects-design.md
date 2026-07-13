# Particle Swarm & Audio Reactive Particles — Design / Requirements

**Date:** 2026-07-13
**Status:** Approved (brainstorm), building.

## Summary

Two new `EffectKind`s sharing one particle engine:

- **Particle Swarm** — thousands of particles advected through a divergence-free
  curl-noise flow field, reading as a school of fish / murmuration.
- **Audio Reactive Particles** — the same engine, but the particles are driven by
  live microphone audio reduced to frequency bands. This is the project's first
  use of microphone permission.

## Architecture: one engine, two drivers

```
CurlNoiseField ─┐
                ├─▶ ParticleSwarmSystem.step(dt, drivers) ─▶ ParticleSwarmView (Canvas)
SwarmDrivers ───┘
   ├─ Swarm mode:  drivers from time (gentle sinusoids)
   └─ Audio mode:  drivers from live mic FFT bands (AudioLevels)
```

`SwarmDrivers` is the single modulation interface: `speed`, `turbulence`,
`cohesion`, `energy`, `colorMix`, `brightness`. The two effects differ only in
how these are produced.

## Motion model (decided)

Curl-noise flow field, **stateful particle buffer** stepped each frame (same
precedent as the existing stateful `OutlineGlowView`). Chosen over true boids
(O(n²), needs spatial hashing, marginal gain) and stateless closed-form paths
(no flocking coherence). Not deterministic across the editor and projector
windows — each instance runs its own sim; visually irrelevant for an ambient
swarm.

## Audio source (decided)

**Microphone (ambient).** `AVAudioEngine` taps the default input; music playing
in the room is picked up and FFT'd. Chosen over ScreenCaptureKit system-audio
capture (more complex, screen-recording permission). The app is **not sandboxed**
(ad-hoc signed), so this needs only an `NSMicrophoneUsageDescription` string plus
the runtime TCC prompt — no entitlement work.

## Components

### LumoraKit (pure, unit-tested — no AVFoundation, no SwiftUI)

- **`CurlNoiseField`** — value-noise + analytic curl → divergence-free 2-D flow
  sampled at `(x, y, time)`. `func flow(x:y:t:) -> CGVector`.
- **`ParticleSwarmSystem`** — `positions`, `velocities`, per-particle seeds
  (size/color variation). `init(count:seed:)` scatters particles in the unit
  square. `step(dt:drivers:field:)` advects each particle along the curl field
  scaled by `speed`, adds `turbulence` jitter + light global-attractor
  `cohesion`, integrates, clamps velocity, and **wraps toroidally** (constant
  density). Positions are normalized `0…1`. Default count ~1500, capped for perf.
- **`AudioLevels`** — value type: smoothed `bass`, `mid`, `treble`, `overall`
  in `0…1`.
- **`AudioBandAnalyzer`** — reduces an FFT magnitude spectrum (+ sample rate) into
  `AudioLevels`, with running **auto-gain** (normalize by a decaying running max
  so it adapts to room loudness — no user sensitivity knob) and attack/decay
  smoothing. Stateful across calls but pure Swift; tested with synthetic spectra.
- **`SwarmDrivers`** — the struct above, plus:
  - `static func idle(time:)` — gentle time-based defaults (Swarm mode + audio
    fallback).
  - `init(from: AudioLevels)` — bass → `speed` + `energy` (size pulse), mid →
    `turbulence`, treble → `colorMix` (sparkle/shift), overall → `brightness`.
    Monotonic mappings; unit-tested.

### Lumora app (AVFoundation / SwiftUI — not unit-tested in the pure suite)

- **`AudioInputManager`** — **singleton** shared by both windows (one mic tap,
  both react):
  - Lazy `AVAudioEngine` input tap → vDSP FFT per buffer → `AudioBandAnalyzer` →
    latest `AudioLevels` stored behind a lock; renderers read the snapshot each
    frame (the upstream `TimelineView(.animation)` already redraws at 60 fps, so
    no Combine on the hot path).
  - **Permission**: first activation calls `AVCaptureDevice.requestAccess(for:
    .audio)`. Denied/unavailable → a published state the effect uses to fall back
    to idle motion; never hard-fails.
  - **Lifecycle**: ref-counted via `ParticleSwarmView` (audio mode)
    `onAppear`/`onDisappear`; engine runs only while an audio effect is on screen.
- **`AudioLevelsProviding`** — tiny protocol (`var currentLevels: AudioLevels`,
  `var isDenied: Bool`) so `ParticleSwarmView` can take a provider; default is
  `AudioInputManager.shared`, tests/previews inject synthetic levels.
- **`ParticleSwarmView`** — dedicated stateful view (like `OutlineGlowView`),
  holds `ParticleSwarmSystem` in `@State`, reuses the upstream global `time`
  (computes `dt` from the last timestamp — no nested `TimelineView`), steps the
  sim, and draws in a `Canvas`. Renders both modes; audio mode reads a provider.
  Thousands of particles: **batch ellipses into one `Path` per color/brightness
  tier and fill once** (per-particle fills are too slow); short velocity-aligned
  streak for the fish look; `.plusLighter` blur layer for the brightest few.

### Wiring

- `EffectKind`: add `particleSwarm` ("Particle Swarm") and `audioParticles`
  ("Audio Reactive Particles"). Both `usesColor` + `usesAccent`, both in the
  **`.nature`** ("Particles & Nature") category.
- `SurfaceContentView.natureEffects` — add cases instantiating `ParticleSwarmView`
  in swarm vs audio mode.
- `scripts/make_app.sh` — add `NSMicrophoneUsageDescription` to the Info.plist
  heredoc. **Audio works only in the packaged `.app`** (like CoreLocation
  weather); under `swift run` the swarm works but no mic prompt appears.

## Error handling / degradation

- Mic denied or no signal → `SwarmDrivers.idle` → gentle living motion, no error
  UI, no crash.
- `swift run` (no Info.plist) → audio effect runs in idle mode; documented.

## Testing

- **Unit (LumoraKit):** curl field divergence ≈ 0 (finite-difference sample) and
  determinism; `ParticleSwarmSystem.step` keeps positions in `0…1` (wrap), count
  conserved, higher `speed` → larger mean displacement; `AudioBandAnalyzer` maps
  low-bin-heavy spectrum → high bass/low treble, silence → zeros, auto-gain
  rises toward 1 under sustained tone; `SwarmDrivers(from:)` monotonicity.
- **Visual (throwaway, deleted after):** render `ParticleSwarmView` at several
  timestamps via `ImageRenderer` → PNGs, inspect distribution/coherence; feed
  synthetic `AudioLevels` to confirm audio-mode response — no mic needed. Use an
  asymmetric setup so flip/mirror bugs can't hide.
- **Manual:** packaged `.app` with music → permission prompt + reactivity.

## Scope boundaries (YAGNI)

Two effects, one engine. No user-facing knobs (auto-gain handles room levels); no
system-audio capture; no spectrum/waveform visualizer UI; no particle collision.
Palette is the surface's existing color + accent.

## File structure

- `Sources/LumoraKit/Particles/CurlNoiseField.swift`
- `Sources/LumoraKit/Particles/ParticleSwarmSystem.swift`
- `Sources/LumoraKit/Particles/SwarmDrivers.swift`
- `Sources/LumoraKit/Audio/AudioLevels.swift`
- `Sources/LumoraKit/Audio/AudioBandAnalyzer.swift`
- `Sources/Lumora/Audio/AudioInputManager.swift`
- `Sources/Lumora/Views/ParticleSwarmView.swift`
- Modify: `Sources/LumoraKit/EffectKind.swift`,
  `Sources/Lumora/Views/SurfaceContentView.swift`, `scripts/make_app.sh`
- Tests in `Tests/LumoraTests/`.
