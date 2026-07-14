# New Effects (16) + Shared Audio Drivers — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generalize the mic/FFT plumbing so any effect can react to audio (spectrum bins + beat detection + a per-surface toggle + 5 retrofits), then add 16 new generative effects, taking the roster from 63 to 79.

**Architecture:** Pure, testable logic lives in `LumoraKit` (audio analysis, maze/Hilbert/attractor/Chladni generators, config structs); Canvas renderers live in `Sources/Lumora/Views/SurfaceContentView.swift` grouped by category `@ViewBuilder`s; heavy simulations are pre-baked by `scripts/generate_*.swift` into JSON resources loaded once (the Game of Life precedent). Audio flows through the existing `AudioInputManager` → `AudioLevelsProviding` → `AudioLevels` path with no interface change.

**Tech Stack:** Swift 5.9, SwiftUI `Canvas`/`TimelineView`, `LumoraKit` (UI-free core), `AVFoundation`/`Accelerate` (existing mic FFT), XCTest.

## Global Constraints

- **Platform:** macOS 14+, Swift 5.9. Keep it compiling at every step.
- **Build/test commands:** `swift build`, `swift test`, `swift run` (dev, no mic prompt), `bash scripts/make_app.sh` (packaged app — the ONLY way mic permission works).
- **Test target:** `Tests/LumoraTests/` (name is `LumoraTests`, depends on `LumoraKit`; only pure `LumoraKit` code is unit-tested — follow this, do not try to test SwiftUI views).
- **New effect wiring recipe (apply for EVERY new `EffectKind`):**
  1. Add the `case` to `EffectKind` enum in `Sources/LumoraKit/EffectKind.swift`.
  2. Add it to `usesColor` and/or `usesAccent` switches (per the spec's Colors rule — fixed-palette effects go in NEITHER, i.e. they fall through to `return false`).
  3. Add it to the `category` switch (existing category, or `.livingSystems`).
  4. Add a `displayName` case.
  5. Add it to the dispatch `switch kind` in `EffectView.body` (route to the right category `@ViewBuilder`).
  6. Add the render `case` inside that category's `@ViewBuilder` in `SurfaceContentView.swift`.
- **Config-struct recipe (for effects needing persisted params):** new `Sources/LumoraKit/<Name>Config.swift` (Codable, all fields defaulted); add optional `var <name>: <Name>Config?` to `Surface` with a `CodingKeys` entry, an `init` param, and a `decodeIfPresent` line (see `MarqueeConfig` / `Surface.swift`). Thread it through `EffectView`'s params and `PropertiesPanelView`.
- **Verify-script recipe:** `scripts/verify_<name>.swift` renders the effect offscreen via `ImageRenderer` at a few `time` values and writes PNGs to `/tmp`, printing non-blank pixel stats. Model on existing `scripts/verify_*.swift`. Run with `swift scripts/verify_<name>.swift`.
- **Bake-script recipe:** `scripts/generate_<name>.swift` simulates offline, bit-packs/quantizes frames, base64-encodes into `Sources/Lumora/Resources/<name>.json` with keys the loader expects, and prints frame/byte counts. A `<Name>Pattern` enum (model on `Sources/Lumora/GameOfLifePattern.swift`) loads it once via `Bundle.module`.
- **Colors:** `caustics` uses primary+accent; `godRays`/`inkFlow`/`butterflies`/`growingIvy`/`mazeSolve`/`countdown`/`strangeAttractor` use color/accent per spec; `stainedGlass`/`fallingSand`/`aquarium` are fixed-palette (return false from both); `physarum` uses primary+accent; `lenia`/`dnaHelix`/`hilbertCurve` are rainbow (fixed).
- **Commit** after each passing step. Prefix `feat:` for effects, `test:` for test-only, `chore:` for wiring/docs.
- **Global-clock gotcha:** effects are driven by a single shared `time`; "start now / play once" needs a per-view `@State startRef` captured on appear (see `OutlineGlowView`). Clocks/countdown use real wall-clock time, NOT `time`.
- **Do not rebuild:** `AudioInputManager`, `AudioLevelsProviding`, `SwarmDrivers`, `ParticleSwarmSystem`, `CurlNoiseField`, `render3DSurface`/`rot3`/`Vec3`/`normalize3`, `GameOfLifePattern`.

---

# PART 1 — Shared audio drivers

## Task 1: Extend `AudioLevels` with spectrum + beat fields

**Files:**
- Modify: `Sources/LumoraKit/Audio/AudioLevels.swift`
- Test: `Tests/LumoraTests/AudioLevelsTests.swift` (create)

**Interfaces:**
- Produces: `AudioLevels.spectrum: [Double]` (default `[]`), `AudioLevels.beatCount: Int` (default `0`), `AudioLevels.beatStrength: Double` (default `0`); memberwise `init` gains the three params with defaults so all existing call sites (`SwarmDrivers(from:)`, `AudioBandAnalyzer`) keep compiling.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/LumoraTests/AudioLevelsTests.swift
import XCTest
@testable import LumoraKit

final class AudioLevelsTests: XCTestCase {
    func testSilentHasEmptySpectrumAndNoBeats() {
        let s = AudioLevels.silent
        XCTAssertEqual(s.spectrum, [])
        XCTAssertEqual(s.beatCount, 0)
        XCTAssertEqual(s.beatStrength, 0)
    }

    func testExistingInitStillWorksWithoutNewFields() {
        let l = AudioLevels(bass: 0.5, mid: 0.4, treble: 0.3, overall: 0.4)
        XCTAssertEqual(l.spectrum, [])
        XCTAssertEqual(l.beatCount, 0)
    }

    func testNewFieldsRoundTrip() {
        let l = AudioLevels(bass: 0, mid: 0, treble: 0, overall: 0,
                            spectrum: [0.1, 0.2], beatCount: 3, beatStrength: 0.7)
        XCTAssertEqual(l.spectrum, [0.1, 0.2])
        XCTAssertEqual(l.beatCount, 3)
        XCTAssertEqual(l.beatStrength, 0.7)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AudioLevelsTests`
Expected: FAIL — extra arguments / no member `spectrum`.

- [ ] **Step 3: Add the fields**

Replace the struct body of `Sources/LumoraKit/Audio/AudioLevels.swift` with:

```swift
public struct AudioLevels: Equatable {
    public var bass: Double
    public var mid: Double
    public var treble: Double
    public var overall: Double
    /// 16 log-spaced smoothed bins, 20 Hz…8 kHz, each 0…1. Empty until filled.
    public var spectrum: [Double]
    /// Monotonically increasing beat count; consumers diff against last-seen.
    public var beatCount: Int
    /// Strength of the most recent beat, 0…1.
    public var beatStrength: Double

    public init(bass: Double = 0, mid: Double = 0, treble: Double = 0, overall: Double = 0,
                spectrum: [Double] = [], beatCount: Int = 0, beatStrength: Double = 0) {
        self.bass = bass
        self.mid = mid
        self.treble = treble
        self.overall = overall
        self.spectrum = spectrum
        self.beatCount = beatCount
        self.beatStrength = beatStrength
    }

    public static let silent = AudioLevels()
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AudioLevelsTests`
Expected: PASS (3 tests). Also run `swift build` to confirm `SwarmDrivers(from:)` still compiles.

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/Audio/AudioLevels.swift Tests/LumoraTests/AudioLevelsTests.swift
git commit -m "feat: add spectrum + beat fields to AudioLevels"
```

---

## Task 2: `BeatDetector` (pure onset detection)

**Files:**
- Create: `Sources/LumoraKit/Audio/BeatDetector.swift`
- Test: `Tests/LumoraTests/BeatDetectorTests.swift`

**Interfaces:**
- Produces: `final class BeatDetector` with `init(historyLen: Int = 43, k: Double = 1.5, floor: Double = 0.15, refractory: Int = 8)`, `func process(bass: Double) -> (isBeat: Bool, strength: Double)`, `func reset()`. `historyLen` ≈ 1 s at the ~43 Hz analysis rate; `refractory` ≈ 180 ms in frames.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/LumoraTests/BeatDetectorTests.swift
import XCTest
@testable import LumoraKit

final class BeatDetectorTests: XCTestCase {
    func testSteadyLevelProducesNoBeats() {
        let d = BeatDetector()
        var beats = 0
        for _ in 0..<200 { if d.process(bass: 0.4).isBeat { beats += 1 } }
        XCTAssertEqual(beats, 0)
    }

    func testNoiseFloorProducesNoBeats() {
        let d = BeatDetector()
        var beats = 0
        for i in 0..<200 { if d.process(bass: 0.02 + 0.01 * Double(i % 3)).isBeat { beats += 1 } }
        XCTAssertEqual(beats, 0, "levels under the absolute floor must not fire")
    }

    func testPeriodicSpikesFireOnceEach() {
        let d = BeatDetector()
        var beats = 0
        // Quiet baseline with a sharp spike every 20 frames.
        for i in 0..<200 {
            let level = (i % 20 == 0) ? 0.9 : 0.1
            if d.process(bass: level).isBeat { beats += 1 }
        }
        // 10 spikes; allow the first to be swallowed while history warms up.
        XCTAssertGreaterThanOrEqual(beats, 8)
        XCTAssertLessThanOrEqual(beats, 10)
    }

    func testRefractorySuppressesAdjacentFrames() {
        let d = BeatDetector(refractory: 8)
        var beats = 0
        // Two consecutive loud frames should count as ONE beat.
        for i in 0..<40 {
            let level = (i == 20 || i == 21) ? 0.9 : 0.1
            if d.process(bass: level).isBeat { beats += 1 }
        }
        XCTAssertEqual(beats, 1)
    }

    func testStrengthIsBoundedAndPositiveOnBeat() {
        let d = BeatDetector()
        var maxStrength = 0.0
        for i in 0..<100 {
            let r = d.process(bass: (i % 25 == 0) ? 0.95 : 0.1)
            if r.isBeat { maxStrength = max(maxStrength, r.strength) }
        }
        XCTAssertGreaterThan(maxStrength, 0)
        XCTAssertLessThanOrEqual(maxStrength, 1.0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BeatDetectorTests`
Expected: FAIL — `BeatDetector` undefined.

- [ ] **Step 3: Implement `BeatDetector`**

```swift
// Sources/LumoraKit/Audio/BeatDetector.swift
import Foundation

/// Energy-onset beat detection on the bass band. Pure Swift, unit-tested with
/// synthetic level sequences. Keeps a short ring buffer of recent bass levels
/// and fires when the current level is both well above the local mean
/// (`mean + k·stddev`) and above an absolute floor, with a refractory window so
/// one kick reads as one beat.
public final class BeatDetector {
    private let historyLen: Int
    private let k: Double
    private let floor: Double
    private let refractory: Int

    private var history: [Double] = []
    private var sinceLast: Int

    public init(historyLen: Int = 43, k: Double = 1.5, floor: Double = 0.15, refractory: Int = 8) {
        self.historyLen = max(4, historyLen)
        self.k = k
        self.floor = floor
        self.refractory = refractory
        self.sinceLast = refractory   // allow an immediate first beat once warm
    }

    public func reset() {
        history.removeAll(keepingCapacity: true)
        sinceLast = refractory
    }

    /// Feed one bass level (0…1). Returns whether this frame is a beat onset and
    /// its strength (how far above the mean, clamped 0…1).
    public func process(bass: Double) -> (isBeat: Bool, strength: Double) {
        sinceLast += 1
        defer {
            history.append(bass)
            if history.count > historyLen { history.removeFirst() }
        }
        guard history.count >= historyLen / 2 else { return (false, 0) }

        let mean = history.reduce(0, +) / Double(history.count)
        let variance = history.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(history.count)
        let std = variance.squareRoot()
        let threshold = mean + k * std

        let isBeat = bass > threshold && bass > floor && sinceLast >= refractory
        if isBeat {
            sinceLast = 0
            let strength = std > 1e-6 ? min(1.0, (bass - mean) / (4 * std)) : min(1.0, bass)
            return (true, max(0, strength))
        }
        return (false, 0)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter BeatDetectorTests`
Expected: PASS (5 tests). If `testPeriodicSpikesFireOnceEach` is off by one, that's the warm-up frame — the assertion range already allows it.

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/Audio/BeatDetector.swift Tests/LumoraTests/BeatDetectorTests.swift
git commit -m "feat: add pure BeatDetector onset detector"
```

---

## Task 3: Fold spectrum bins + beat into `AudioBandAnalyzer`

**Files:**
- Modify: `Sources/LumoraKit/Audio/AudioBandAnalyzer.swift`
- Test: `Tests/LumoraTests/AudioBandAnalyzerTests.swift` (create)

**Interfaces:**
- Consumes: `BeatDetector` (Task 2), extended `AudioLevels` (Task 1).
- Produces: unchanged public signature `process(magnitudes:sampleRate:) -> AudioLevels`, now also filling `spectrum` (16 bins), `beatCount`, `beatStrength`. `reset()` also resets the detector and bin state.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/LumoraTests/AudioBandAnalyzerTests.swift
import XCTest
@testable import LumoraKit

final class AudioBandAnalyzerTests: XCTestCase {
    // Build a magnitude spectrum with a single spike at `hz`.
    private func spectrum(spikeHz: Double, sampleRate: Double, bins: Int) -> [Float] {
        var m = [Float](repeating: 0, count: bins)
        let hzPerBin = sampleRate / Double(2 * bins)
        let idx = min(bins - 1, max(0, Int(spikeHz / hzPerBin)))
        m[idx] = 1.0
        return m
    }

    func testSpectrumHas16Bins() {
        let a = AudioBandAnalyzer()
        let m = spectrum(spikeHz: 440, sampleRate: 44100, bins: 512)
        let levels = a.process(magnitudes: m, sampleRate: 44100)
        XCTAssertEqual(levels.spectrum.count, 16)
    }

    func testLowSpikeLandsInLowBins() {
        let a = AudioBandAnalyzer()
        let m = spectrum(spikeHz: 60, sampleRate: 44100, bins: 512)
        var levels = AudioLevels.silent
        for _ in 0..<10 { levels = a.process(magnitudes: m, sampleRate: 44100) }
        let lowEnergy = levels.spectrum.prefix(4).reduce(0, +)
        let highEnergy = levels.spectrum.suffix(4).reduce(0, +)
        XCTAssertGreaterThan(lowEnergy, highEnergy)
    }

    func testHighSpikeLandsInHighBins() {
        let a = AudioBandAnalyzer()
        let m = spectrum(spikeHz: 6000, sampleRate: 44100, bins: 512)
        var levels = AudioLevels.silent
        for _ in 0..<10 { levels = a.process(magnitudes: m, sampleRate: 44100) }
        let lowEnergy = levels.spectrum.prefix(4).reduce(0, +)
        let highEnergy = levels.spectrum.suffix(4).reduce(0, +)
        XCTAssertGreaterThan(highEnergy, lowEnergy)
    }

    func testResetClearsBeatCount() {
        let a = AudioBandAnalyzer()
        for i in 0..<100 {
            let hz = 60.0
            let mag: Float = (i % 20 == 0) ? 4.0 : 0.2
            var m = spectrum(spikeHz: hz, sampleRate: 44100, bins: 512)
            m = m.map { $0 * mag }
            _ = a.process(magnitudes: m, sampleRate: 44100)
        }
        a.reset()
        let after = a.process(magnitudes: [Float](repeating: 0, count: 512), sampleRate: 44100)
        XCTAssertEqual(after.beatCount, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AudioBandAnalyzerTests`
Expected: FAIL — `spectrum` empty / member missing.

- [ ] **Step 3: Extend the analyzer**

In `Sources/LumoraKit/Audio/AudioBandAnalyzer.swift`:

Add stored state near `smoothed`:

```swift
    private let beatDetector = BeatDetector()
    private var beatCount = 0
    private var lastBeatStrength = 0.0
    private var smoothedBins = [Double](repeating: 0, count: 16)
    /// Log-spaced band edges 20 Hz…8 kHz for the 16 bins (17 edges).
    private static let binEdges: [Double] = {
        let lo = 20.0, hi = 8000.0, n = 16
        return (0...n).map { lo * pow(hi / lo, Double($0) / Double(n)) }
    }()
```

In `reset()` add:

```swift
        beatDetector.reset()
        beatCount = 0
        lastBeatStrength = 0
        smoothedBins = [Double](repeating: 0, count: 16)
```

At the end of `process(...)`, before `return smoothed`, replace the final block so it computes bins, runs the detector, and attaches them. Full new tail:

```swift
        // 16 log-spaced spectrum bins, auto-gained by the same running peak and
        // smoothed with the same attack/decay.
        var binSum = [Double](repeating: 0, count: 16)
        var binN = [Int](repeating: 0, count: 16)
        for (i, mgf) in magnitudes.enumerated() {
            let hz = Double(i) * hzPerBin
            if hz < Self.binEdges.first! || hz > Self.binEdges.last! { continue }
            // Which bin? (linear scan is fine — 16 edges.)
            var b = 0
            while b < 16 && hz > Self.binEdges[b + 1] { b += 1 }
            if b < 16 { binSum[b] += Double(mgf); binN[b] += 1 }
        }
        for b in 0..<16 {
            let raw = binN[b] > 0 ? binSum[b] / Double(binN[b]) : 0
            let target = clamp(raw * inv)
            smoothedBins[b] = smooth(smoothedBins[b], target)
        }

        let beat = beatDetector.process(bass: smoothed.bass)
        if beat.isBeat { beatCount += 1; lastBeatStrength = beat.strength }

        smoothed.spectrum = smoothedBins
        smoothed.beatCount = beatCount
        smoothed.beatStrength = beat.isBeat ? beat.strength : lastBeatStrength
        return smoothed
```

Note: `smoothed` is currently a `let`-style rebuild at the bottom; make it a `var` so the tail can mutate `.spectrum`/`.beatCount`/`.beatStrength`. Change `smoothed = AudioLevels(...)` to build into `smoothed` (already a stored `var` property) and drop any trailing `return smoothed` duplication.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter AudioBandAnalyzerTests` then full `swift test`
Expected: PASS. Existing `ParticleSwarmTests` must still pass (SwarmDrivers path unchanged).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/Audio/AudioBandAnalyzer.swift Tests/LumoraTests/AudioBandAnalyzerTests.swift
git commit -m "feat: spectrum bins + beat detection in AudioBandAnalyzer"
```

---

## Task 4: Per-surface Audio Reactive toggle + renderer plumbing

**Files:**
- Modify: `Sources/LumoraKit/Surface.swift` (add `audioReactive`)
- Modify: `Sources/LumoraKit/EffectKind.swift` (add `supportsAudio`)
- Modify: `Sources/Lumora/Views/SurfaceContentView.swift` (thread `audioReactive` into `EffectView`)
- Modify: `Sources/Lumora/Views/PropertiesPanelView.swift` (toggle UI)
- Test: `Tests/LumoraTests/ProjectCodableTests.swift` (extend — audioReactive round-trips + old files default false)

**Interfaces:**
- Produces: `Surface.audioReactive: Bool` (default `false`); `EffectKind.supportsAudio: Bool`; `EffectView` gains `var audioReactive: Bool = false`.

- [ ] **Step 1: Write the failing test**

Append to `Tests/LumoraTests/ProjectCodableTests.swift`:

```swift
    func testAudioReactiveDefaultsFalseForOldFiles() throws {
        // JSON without the field (simulates a pre-audio .lumora surface).
        let json = """
        {"id":"\(UUID().uuidString)","name":"S","points":[{"x":0,"y":0}],
         "media":{"color":{"r":0,"g":0,"b":0,"a":1}},"isVisible":true,"opacity":1}
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(Surface.self, from: json)
        XCTAssertFalse(s.audioReactive)
    }

    func testAudioReactiveRoundTrips() throws {
        var s = Surface.defaultRect(name: "S")
        s.audioReactive = true
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Surface.self, from: data)
        XCTAssertTrue(back.audioReactive)
    }

    func testSupportsAudioMatchesSpec() {
        let yes: [EffectKind] = [.equalizer, .strobe, .liquidSlosh, .aurora, .plasma, .chladni]
        for k in yes { XCTAssertTrue(k.supportsAudio, "\(k) should support audio") }
        XCTAssertFalse(EffectKind.grid.supportsAudio)
        XCTAssertFalse(EffectKind.audioParticles.supportsAudio) // inherently audio; no toggle
    }
```

(If the raw-JSON decode shape doesn't match `Surface`'s exact keys, adjust to the minimal valid payload — the point is the missing `audioReactive` key defaulting to false. `chladni` will not exist until Task 7; temporarily drop `.chladni` from `yes` and re-add it in Task 7's test step.)

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProjectCodableTests`
Expected: FAIL — no member `audioReactive` / `supportsAudio`.

- [ ] **Step 3: Add `Surface.audioReactive`**

In `Sources/LumoraKit/Surface.swift`: add property `public var audioReactive: Bool`, an `init` param `audioReactive: Bool = false` (assign it), a `CodingKeys` case `audioReactive`, and in `init(from:)`:

```swift
        audioReactive = try c.decodeIfPresent(Bool.self, forKey: .audioReactive) ?? false
```

- [ ] **Step 4: Add `EffectKind.supportsAudio`**

In `Sources/LumoraKit/EffectKind.swift`, after `usesAccent`:

```swift
    /// Whether this effect can react to live microphone audio when the
    /// surface's Audio Reactive toggle is on. (`audioParticles` is inherently
    /// audio and is excluded — it has no toggle.)
    public var supportsAudio: Bool {
        switch self {
        case .equalizer, .strobe, .liquidSlosh, .aurora, .plasma, .chladni:
            return true
        default:
            return false
        }
    }
```

(`.chladni` won't compile until Task 7 adds the case — add `supportsAudio` now but comment out `.chladni` in the case list, restoring it in Task 7. Alternatively land Task 4 and Task 7's enum case together; simplest is to add the `chladni` enum case now as part of this step and leave its renderer for Task 7. Choose the latter: add `case chladni` to the enum here so the switch is final.)

- [ ] **Step 5: Thread `audioReactive` into `EffectView`**

In `SurfaceContentView.swift`, `mediaContent`'s `.effect` case, pass `audioReactive: surface.audioReactive` into `EffectView(...)`. Add `var audioReactive: Bool = false` to the `EffectView` struct's stored properties.

- [ ] **Step 6: Add the panel toggle**

In `PropertiesPanelView.swift`, inside the `.effect(let effectKind, ...)` media branch (near the `if effectKind == .marqueeText` blocks), add:

```swift
            if effectKind.supportsAudio {
                Toggle("Audio Reactive", isOn: audioReactiveBinding)
                if AudioInputManager.shared.isDenied {
                    Text("Microphone unavailable — running idle.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
```

Thread a `@Binding var audioReactive: Bool` into the media-editor subview (mirror how `marquee` is threaded from `editor(_:)` — pass `audioReactive: surface.audioReactive`), and define `audioReactiveBinding` as that binding. If the panel edits `Surface` via a single `Binding<Surface>`, bind directly to `surface.audioReactive`.

- [ ] **Step 7: Run tests + build**

Run: `swift test --filter ProjectCodableTests` then `swift build`
Expected: PASS + compiles. `swift run` and confirm the toggle appears for Equalizer/Strobe/Plasma/etc. (it does nothing visually yet — that lands in Tasks 5–7).

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: per-surface Audio Reactive toggle + supportsAudio + chladni case"
```

---

## Task 5: Retrofit Equalizer + Strobe  — ⛳ CHECKPOINT 1

**Files:**
- Modify: `Sources/Lumora/Views/SurfaceContentView.swift` (equalizer + strobe renderers, audio path)
- Create: `scripts/verify_audio_retrofit.swift`

**Interfaces:**
- Consumes: `AudioLevelsProviding`, extended `AudioLevels`. Renderers read `AudioInputManager.shared.currentLevels` when `audioReactive && !isDenied`, else fall back to today's time-driven code.

**Design note (applies to all retrofits):** audio-capable renderers need live levels + retain/release. The cleanest reuse is a small wrapper view per retrofit that owns `onAppear/onDisappear` retain/release and reads `currentLevels`, mirroring `ParticleSwarmView`. For the two simplest (equalizer/strobe) you can instead read `AudioInputManager.shared` directly inside the existing `Canvas` and gate retain/release on a wrapper `.onAppear`. Use this helper wrapper (add once, reuse in Tasks 5–7):

```swift
/// Wraps an audio-reactive effect: retains the mic only while visible AND the
/// toggle is on, and hands the current levels to its content. When off/denied,
/// passes `.silent` so the effect renders its idle (time-driven) path.
private struct AudioReactiveEffect<Content: View>: View {
    let active: Bool
    var audio: AudioLevelsProviding = AudioInputManager.shared
    @ViewBuilder let content: (AudioLevels) -> Content
    var body: some View {
        content((active && !audio.isDenied) ? audio.currentLevels : .silent)
            .onAppear { if active { audio.retain() } }
            .onDisappear { if active { audio.release() } }
    }
}
```

- [ ] **Step 1: Equalizer audio path**

Replace the `case .equalizer:` body in `motionEffects` so it wraps in `AudioReactiveEffect(active: audioReactive)` and, when `levels.spectrum` is non-empty, drives 16 bars from the bins with peak-hold; otherwise runs the existing randomized bars. Core change (inside the `Canvas`, per bar `i`):

```swift
                let level: Double
                if !levels.spectrum.isEmpty {
                    level = min(1.0, max(0.04, levels.spectrum[i]))   // real bin
                } else {
                    // …existing s1/s2/s3 + beat computation…
                    level = min(1.0, max(0.05, 0.12 + 0.66 * mix + kick))
                }
```

Peak-hold caps: keep a per-view `@State var peaks = [Double](repeating: 0, count: 16)` in the wrapper content; each frame `peaks[i] = max(level, peaks[i] - 0.9 * dt)` and draw a thin cap line at `peaks[i]`. (dt from the shared-time delta, same pattern as `ParticleSwarmView.step`.) Since `Canvas` closures are stateless, hold peaks in a small reference-type `@State` object like `SwarmRenderState`.

- [ ] **Step 2: Strobe audio path**

Replace `case .strobe:` in `gradientEffects` with:

```swift
        case .strobe:
            AudioReactiveEffect(active: audioReactive) { levels in
                StrobeView(color: color, accent: accent, time: time, levels: levels)
            }
```

Add a small `StrobeView` that, when `levels.spectrum.isEmpty` (idle), uses today's `Int(time * 3) % 2` flash; when audio-active, holds a `@State lastBeat` and flashes to `color` for a short decay window whenever `levels.beatCount` increases, opacity scaled by `levels.beatStrength`, resting on `accent` between flashes.

- [ ] **Step 3: Verify script**

Create `scripts/verify_audio_retrofit.swift` with a stub `AudioLevelsProviding` returning scripted levels (a rising spectrum, a bumped `beatCount`), render Equalizer + Strobe via `ImageRenderer` at 3 times each, write PNGs to `/tmp`, assert non-black pixel counts differ between idle and audio-active renders.

- [ ] **Step 4: Run + build + verify**

Run: `swift build && swift test && swift scripts/verify_audio_retrofit.swift`
Expected: compiles, tests pass, script prints differing pixel stats and writes PNGs.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: audio-reactive Equalizer + Strobe retrofits"
```

- [ ] **Step 6: ⛳ CHECKPOINT 1 — hand off for user testing**

Build the packaged app so the mic works:

```bash
bash scripts/make_app.sh
```

Tell the user: open the app, add a surface, set Effect → Equalizer (Waves & Motion) and → Strobe (Gradients), toggle **Audio Reactive** on each, play music, confirm bars track the spectrum and Strobe flashes on beats; confirm both still look correct with the toggle OFF and with mic denied. **Wait for the user's go-ahead before Task 6.**

---

## Task 6: Retrofit Liquid Slosh + Aurora  — ⛳ CHECKPOINT 2

**Files:** Modify `Sources/Lumora/Views/SurfaceContentView.swift`; extend `scripts/verify_audio_retrofit.swift`.

- [ ] **Step 1: Liquid Slosh audio path**

Wrap `case .liquidSlosh:` in `AudioReactiveEffect(active: audioReactive)`. The slosh already integrates a tank; add a lateral impulse each time `levels.beatCount` increases (magnitude ∝ `beatStrength`) and a continuous swell term ∝ `levels.bass` added to the tilt. When `spectrum.isEmpty`, behaviour is unchanged. Hold the "last seen beatCount" + impulse velocity in the effect's existing state object (or a new small reference-type `@State`).

- [ ] **Step 2: Aurora audio path**

Wrap `case .aurora:` in `AudioReactiveEffect`. Multiply each curtain's `amp` by `(1 + 0.8 * levels.bass)`, its ray `bright` and fill opacity by `(0.7 + 0.6 * levels.overall)`, and add `levels.treble * 2.5` to the shimmer term's time coefficient. Idle (`.silent`) reproduces today's look exactly (bass/overall/treble all 0 → multipliers reduce to current constants — verify the constants match; if not, gate on `spectrum.isEmpty` to pick the original expression).

- [ ] **Step 3: Extend verify + run**

Add Liquid Slosh + Aurora renders to `verify_audio_retrofit.swift`. Run `swift build && swift scripts/verify_audio_retrofit.swift`.
Expected: compiles; idle vs audio renders differ.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: audio-reactive Liquid Slosh + Aurora retrofits"
```

- [ ] **Step 5: ⛳ CHECKPOINT 2**

`bash scripts/make_app.sh`. User tests Liquid Slosh (bass shoves the tank) + Aurora (curtains breathe with music), and confirms idle/denied unchanged. **Wait for go-ahead.**

---

## Task 7: Retrofit Plasma + new Chladni effect (audio-native)  — ⛳ CHECKPOINT 3

**Files:**
- Create: `Sources/LumoraKit/ChladniField.swift`
- Test: `Tests/LumoraTests/ChladniFieldTests.swift`
- Modify: `SurfaceContentView.swift` (plasma audio path + chladni renderer in `patternEffects`)
- (`chladni` enum case, category, displayName, dispatch, supportsAudio already added in Task 4 — verify.)
- Create: `scripts/verify_chladni.swift`

**Interfaces:**
- Produces: `enum ChladniField { static func value(x: Double, y: Double, n: Double, m: Double) -> Double }` returning the standing-wave field `cos(nπx)cos(mπy) − cos(mπx)cos(nπy)` for `x,y ∈ [0,1]`; `static func modeForBands(bass:mid:treble:) -> (n: Double, m: Double)`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/LumoraTests/ChladniFieldTests.swift
import XCTest
@testable import LumoraKit

final class ChladniFieldTests: XCTestCase {
    func testAntisymmetricUnderSwap() {
        // Swapping n and m negates the field.
        let a = ChladniField.value(x: 0.3, y: 0.7, n: 2, m: 5)
        let b = ChladniField.value(x: 0.3, y: 0.7, n: 5, m: 2)
        XCTAssertEqual(a, -b, accuracy: 1e-9)
    }

    func testZeroOnMainDiagonalWhenXEqualsY() {
        // At x==y the two terms are equal → field is 0 (a nodal line).
        for t in stride(from: 0.0, through: 1.0, by: 0.1) {
            XCTAssertEqual(ChladniField.value(x: t, y: t, n: 3, m: 4), 0, accuracy: 1e-9)
        }
    }

    func testRangeWithinPlusMinusTwo() {
        var maxAbs = 0.0
        for i in 0...20 { for j in 0...20 {
            let v = ChladniField.value(x: Double(i)/20, y: Double(j)/20, n: 4, m: 7)
            maxAbs = max(maxAbs, abs(v))
        }}
        XCTAssertLessThanOrEqual(maxAbs, 2.0 + 1e-9)
    }

    func testBassPicksLowerModesThanTreble() {
        let low = ChladniField.modeForBands(bass: 1, mid: 0, treble: 0)
        let high = ChladniField.modeForBands(bass: 0, mid: 0, treble: 1)
        XCTAssertLessThan(low.n + low.m, high.n + high.m)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ChladniFieldTests`
Expected: FAIL — `ChladniField` undefined.

- [ ] **Step 3: Implement `ChladniField`**

```swift
// Sources/LumoraKit/ChladniField.swift
import Foundation

/// Vibrating-plate nodal field. `value` is the classic square-plate standing
/// wave whose zero-set is where "sand" collects. Pure + unit-tested.
public enum ChladniField {
    public static func value(x: Double, y: Double, n: Double, m: Double) -> Double {
        let a = cos(n * .pi * x) * cos(m * .pi * y)
        let b = cos(m * .pi * x) * cos(n * .pi * y)
        return a - b
    }

    /// Map the dominant band to a target mode pair. Bass → low modes, treble →
    /// high modes. Returns non-integer targets so the renderer can morph.
    public static func modeForBands(bass: Double, mid: Double, treble: Double) -> (n: Double, m: Double) {
        let energy = bass + mid + treble
        guard energy > 1e-6 else { return (3, 4) }
        // Weighted mode index 2…9.
        let idx = (bass * 2 + mid * 5 + treble * 9) / energy
        let n = idx
        let m = idx + 1 + treble * 2   // keep n≠m so patterns stay interesting
        return (n, m)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ChladniFieldTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Plasma audio path**

Wrap `case .plasma:` in `AudioReactiveEffect`. Scale the two radial gradients' `endRadius` by `(1 + 0.5 * levels.bass)`, overall opacity by `(0.6 + 0.5 * levels.overall)`, and bump saturation briefly on `beatCount` change. Idle unchanged.

- [ ] **Step 6: Chladni renderer**

In `patternEffects`, add:

```swift
        case .chladni:
            AudioReactiveEffect(active: audioReactive) { levels in
                ChladniView(time: time, color: color, accent: accent, levels: levels)
            }
```

Add `ChladniView`: samples `ChladniField.value` on a grid (≈ 160×160 for a surface, or per-pixel via `Canvas` at coarse resolution then blur), brightness = `1 - smoothstep(0, threshold, abs(value))` so nodal lines glow. Time mode: morph `(n,m)` smoothly through a sequence via `@State` easing. Audio mode (`!spectrum.isEmpty`): ease `(n,m)` toward `ChladniField.modeForBands(...)`, line brightness/thickness ∝ `levels.overall`. Dark plate background, sand-colored (warm off-white) lines.

- [ ] **Step 7: Verify + run**

Create `scripts/verify_chladni.swift` (render at 3 times, two mode pairs, assert bright nodal pixels present). Run `swift build && swift test && swift scripts/verify_chladni.swift`.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: Plasma audio retrofit + Chladni effect (ChladniField + audio mode)"
```

- [ ] **Step 9: ⛳ CHECKPOINT 3**

`bash scripts/make_app.sh`. User tests Plasma (audio) + Chladni (Patterns & Geometry) in both time and audio modes — frequency should select the pattern. Confirms all 5 retrofits + Chladni. **This closes Part 1. Wait for go-ahead.**

---

# PART 2 — New effects (low-effort first)

Each task below adds two effects and ends with a packaged-app checkpoint. For every effect, apply the **New effect wiring recipe** (Global Constraints) — those exact 6 edits are implied and not repeated as separate steps; the steps below give the renderer/pure-logic specifics.

## Task 8: Stained Glass + Water Caustics  — ⛳ CHECKPOINT 4

Both reuse the vector Voronoi machinery (`case .voronoi` in `fieldEffects`, ~line 1404). Read that renderer first for the half-plane cell-clipping approach.

**Files:** Modify `EffectKind.swift`, `SurfaceContentView.swift`; create `scripts/verify_glass_caustics.swift`.

- [ ] **Step 1: Wire `stainedGlass` (category `.fields`, fixed-palette) + `caustics` (category `.ambient`, uses color+accent).** Apply the 6-edit recipe for both.

- [ ] **Step 2: Stained Glass renderer** in `fieldEffects`: reuse the voronoi cell polygons; fill each cell with a jewel tone from a fixed palette (deep blue/ruby/emerald/amber/violet) at ~0.8 opacity over a dark backing; stroke cell borders thick (`lineWidth 4`) in near-black "lead"; overlay a slow-moving radial gradient (a bright spot orbiting on `time`) multiplied via `.blendMode(.plusLighter)` to read as light behind the glass. Cells are static (seed once); only the light sweep animates.

```swift
        case .stainedGlass:
            Canvas { ctx, size in
                let cells = voronoiCells(in: size, count: 26, seed: 7)   // reuse helper
                let palette: [Color] = [
                    Color(red:0.10,green:0.20,blue:0.65), Color(red:0.65,green:0.10,blue:0.20),
                    Color(red:0.10,green:0.55,blue:0.30), Color(red:0.85,green:0.65,blue:0.15),
                    Color(red:0.45,green:0.15,blue:0.60)]
                // light sweep center
                let lc = CGPoint(x: size.width*(0.5+0.4*cos(time*0.3)), y: size.height*(0.5+0.4*sin(time*0.23)))
                for (i, poly) in cells.enumerated() {
                    var p = Path(); p.addLines(poly); p.closeSubpath()
                    let d = hypot(poly.first!.x-lc.x, poly.first!.y-lc.y)
                    let lit = max(0.35, 1.0 - d/Double(hypot(size.width,size.height)))
                    ctx.fill(p, with: .color(palette[i % palette.count].opacity(0.85*lit)))
                    ctx.stroke(p, with: .color(Color(white:0.05)), lineWidth: 4)
                }
            }
```

(If `voronoiCells`/`voronoiSites` isn't a standalone helper, extract the site+clip logic from `case .voronoi` into a private `func voronoiCells(in:count:seed:) -> [[CGPoint]]` and call it from both voronoi and stainedGlass — DRY.)

- [ ] **Step 3: Water Caustics renderer** in `ambientEffects`: 2–3 layers of drifting cellular ridges. For each layer, compute a Worley-style nearest-site distance field on a coarse grid of moving sites, take `bright = smoothstep` of the ridge (distance near a threshold), draw as blurred `plusLighter` strokes/fills tinted `accent` over a `color`-tinted water base; counter-drift layers at different speeds.

```swift
        case .caustics:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin:.zero,size:size)), with:.color(color.color.opacity(0.9)))
                for layer in 0..<3 {
                    let n = 14, sp = 0.15 + 0.08*Double(layer)
                    var sites: [CGPoint] = (0..<n).map { i in
                        CGPoint(x: size.width*(0.5+0.5*sin(time*sp+Double(i)*1.7+Double(layer))),
                                y: size.height*(0.5+0.5*cos(time*sp*1.3+Double(i)*2.3)))
                    }
                    ctx.drawLayer { l in
                        l.addFilter(.blur(radius: 6)); l.blendMode = .plusLighter
                        // ridge = thin bright ring around each site
                        for s in sites {
                            let r: CGFloat = 26 + 8*CGFloat(sin(time+Double(s.x)))
                            l.stroke(Path(ellipseIn: CGRect(x:s.x-r,y:s.y-r,width:2*r,height:2*r)),
                                     with:.color(accent.color.opacity(0.25)), lineWidth: 3)
                        }
                        _ = sites
                    }
                }
            }
```

(Tune site count/opacity so it reads as pool caustics; the ridge-ring approximation is intentional and cheap.)

- [ ] **Step 4: Verify + run**

`scripts/verify_glass_caustics.swift` renders both at 3 times; assert non-trivial color variance. `swift build && swift scripts/verify_glass_caustics.swift`.

- [ ] **Step 5: Commit** `feat: Stained Glass + Water Caustics effects`

- [ ] **Step 6: ⛳ CHECKPOINT 4** — `swift run` is enough (no mic). User confirms both render and animate. Update README effect count later. **Wait for go-ahead.**

---

## Task 9: God Rays + Butterflies  — ⛳ CHECKPOINT 5

Butterflies reuses `ParticleSwarmSystem` (see `ParticleSwarmView`). God Rays is a self-contained Canvas.

**Files:** Modify `EffectKind.swift`, `SurfaceContentView.swift`; create `Sources/Lumora/Views/ButterfliesView.swift`; `scripts/verify_godrays_butterflies.swift`.

- [ ] **Step 1: Wire `godRays` (`.ambient`, uses color) + `butterflies` (`.nature`, uses color+accent).**

- [ ] **Step 2: God Rays renderer** in `ambientEffects`: 4 soft translucent beams from the top-left, each a thin quad fanning downward, blurred + `plusLighter`, intensity breathing on `sin(time*0.2 + phase)`; sparse dust motes (20–30 slow points) drifting, clipped to the union of beams.

```swift
        case .godRays:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin:.zero,size:size)), with:.color(Color(white:0.02)))
                let origin = CGPoint(x: size.width*0.15, y: -size.height*0.1)
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: 24)); l.blendMode = .plusLighter
                    for i in 0..<4 {
                        let ang = 0.5 + Double(i)*0.22
                        let breathe = 0.4 + 0.6*abs(sin(time*0.2 + Double(i)))
                        let far = CGPoint(x: origin.x + cos(ang)*size.width*1.4,
                                          y: origin.y + sin(ang)*size.height*1.6)
                        var beam = Path()
                        let w: CGFloat = 40
                        beam.move(to: CGPoint(x: origin.x-w, y: origin.y))
                        beam.addLine(to: CGPoint(x: origin.x+w, y: origin.y))
                        beam.addLine(to: CGPoint(x: far.x+w*3, y: far.y))
                        beam.addLine(to: CGPoint(x: far.x-w*3, y: far.y))
                        beam.closeSubpath()
                        l.fill(beam, with:.color(color.color.opacity(0.18*breathe)))
                    }
                }
                // dust
                for i in 0..<28 {
                    let x = fract(hash01(i,3) + time*0.01) * size.width
                    let y = (hash01(i,5) + time*0.02).truncatingRemainder(dividingBy: 1) * size.height
                    ctx.fill(Path(ellipseIn: CGRect(x:x,y:y,width:2,height:2)),
                             with:.color(color.color.opacity(0.25)))
                }
            }
```

- [ ] **Step 3: Butterflies** — add `ButterfliesView` modeled on `ParticleSwarmView` (mode-less): `ParticleSwarmSystem(count: 40)`, `SwarmDrivers.idle`-style drivers with an upward y-bias, render each particle as two triangular wings whose x-scale oscillates on a per-particle flap phase (`sin(time*6 + seed*6.28)`), tinted by a `color`→`accent` gradient. Route `case .butterflies:` in `natureEffects` to `ButterfliesView(color:accent:time:)`.

- [ ] **Step 4: Verify + run** `swift build && swift scripts/verify_godrays_butterflies.swift`.

- [ ] **Step 5: Commit** `feat: God Rays + Butterflies effects`

- [ ] **Step 6: ⛳ CHECKPOINT 5** — `swift run`; user confirms. **Wait for go-ahead.**

---

## Task 10: DNA Helix + Hilbert Curve  — ⛳ CHECKPOINT 6

DNA Helix reuses the 3D pipeline (`rot3`/`Vec3`, painter's sort — see `drawPointCloud3D`). Hilbert Curve needs a pure generator (tested) + a trace renderer (Contour-Trace rainbow style).

**Files:** Modify `EffectKind.swift`, `SurfaceContentView.swift`; create `Sources/LumoraKit/HilbertCurve.swift`, `Tests/LumoraTests/HilbertCurveTests.swift`, `scripts/verify_dna_hilbert.swift`.

- [ ] **Step 1: Write failing Hilbert test**

```swift
// Tests/LumoraTests/HilbertCurveTests.swift
import CoreGraphics
import XCTest
@testable import LumoraKit

final class HilbertCurveTests: XCTestCase {
    func testOrderNVisitsEveryCellExactlyOnce() {
        for order in 1...5 {
            let pts = HilbertCurve.points(order: order)
            XCTAssertEqual(pts.count, (1 << order) * (1 << order))
            XCTAssertEqual(Set(pts.map { "\(Int($0.x)),\(Int($0.y))" }).count, pts.count)
        }
    }
    func testConsecutiveStepsAreUnitLength() {
        let pts = HilbertCurve.points(order: 4)
        for i in 1..<pts.count {
            let d = abs(pts[i].x - pts[i-1].x) + abs(pts[i].y - pts[i-1].y)
            XCTAssertEqual(d, 1, accuracy: 1e-9)
        }
    }
}
```

- [ ] **Step 2: Run — fails** (`swift test --filter HilbertCurveTests`).

- [ ] **Step 3: Implement `HilbertCurve`**

```swift
// Sources/LumoraKit/HilbertCurve.swift
import CoreGraphics

/// Integer Hilbert space-filling curve. `points(order:)` returns the visitation
/// sequence over a 2^order × 2^order grid (integer cell coords). Pure + tested.
public enum HilbertCurve {
    public static func points(order: Int) -> [CGPoint] {
        let n = 1 << max(0, order)
        var result: [CGPoint] = []
        result.reserveCapacity(n * n)
        for d in 0..<(n * n) {
            var rx = 0, ry = 0, t = d, x = 0, y = 0
            var s = 1
            while s < n {
                rx = 1 & (t / 2)
                ry = 1 & (t ^ rx)
                // rotate
                if ry == 0 {
                    if rx == 1 { x = s - 1 - x; y = s - 1 - y }
                    swap(&x, &y)
                }
                x += s * rx; y += s * ry
                t /= 4
                s <<= 1
            }
            result.append(CGPoint(x: x, y: y))
        }
        return result
    }
}
```

- [ ] **Step 4: Run — passes.**

- [ ] **Step 5: Wire + renderers.** `dnaHelix` (`.threeD`, rainbow) and `hilbertCurve` (`.patterns`, rainbow).

  - **DNA Helix** in `threeDEffects`: two phase-offset helices of spheres. For `i in 0..<count`, `t = Double(i)/count`, angle `= t*turns*2π + time*speed`; strand A at `(cos, t*height, sin)`, strand B at angle+π; add rungs connecting A↔B every k. Project with the same `rot3`+cam-distance code as `drawPointCloud3D`, depth-sort, draw spheres as depth-cued `plusLighter` circles, hue = `fract(t + time*0.05)`. Respect `three?.speed`.
  - **Hilbert** in `patternEffects`: `HilbertCurve.points(order: 6)` scaled to the box; trace with a glowing pen head up to arc-length `progress(time)` (generate→hold→fade→repeat cycle via a per-view `@State startRef`, like `OutlineGlowView`); color by arc-length rainbow (hue = index/total), alternate orientation each cycle (flip x).

- [ ] **Step 6: Verify + run** `swift build && swift test && swift scripts/verify_dna_hilbert.swift`.

- [ ] **Step 7: Commit** `feat: DNA Helix + Hilbert Curve effects`

- [ ] **Step 8: ⛳ CHECKPOINT 6** — `swift run`; user confirms. **Wait for go-ahead.**

---

## Task 11: Ink in Water + Aquarium  — ⛳ CHECKPOINT 7

Both reuse existing engines: Ink uses `CurlNoiseField` to advect blobs (stateful, `ParticleSwarmView` state pattern); Aquarium reuses `ParticleSwarmSystem` at low count + time-driven kelp/bubbles.

**Files:** Modify `EffectKind.swift`, `SurfaceContentView.swift`; create `Sources/Lumora/Views/InkFlowView.swift`, `Sources/Lumora/Views/AquariumView.swift`, `scripts/verify_ink_aquarium.swift`.

- [ ] **Step 1: Wire `inkFlow` (`.ambient`, uses color+accent) + `aquarium` (`.nature`, fixed-palette).**

- [ ] **Step 2: `InkFlowView`** — reference-type `@State` holding an array of blobs `{pos, radius, age, colorIsAccent}`. Each frame: advance age, grow radius, fade opacity, advect `pos` by sampling `CurlNoiseField` (see `ParticleSwarmSystem.step` for how it queries the field); spawn a new blob every ~1.5 s alternating primary/accent. Draw blobs as heavily blurred filled circles (`.blur(radius: 18)`), `plusLighter`, so overlaps read as diffusing ink. `dt` from shared-time delta.

- [ ] **Step 3: `AquariumView`** — `ParticleSwarmSystem(count: 55)` with calm idle drivers; deep-water vertical gradient background; render each particle as a velocity-aligned tapered fish body + wagging tail (`sin(time*4 + seed)`), in 3 size/color tiers from a fixed palette (orange/silver/blue). Add 3 kelp strands anchored to the bottom edge swaying on `sin(time + x)`, and 2 bubble columns rising and looping. Route `case .aquarium:` and `case .inkFlow:` to the two views.

- [ ] **Step 4: Verify + run** `swift build && swift scripts/verify_ink_aquarium.swift`.

- [ ] **Step 5: Commit** `feat: Ink in Water + Aquarium effects`

- [ ] **Step 6: ⛳ CHECKPOINT 7** — `swift run`; user confirms. **Wait for go-ahead.**

---

## Task 12: Strange Attractor + Growing Ivy  — ⛳ CHECKPOINT 8

Strange Attractor needs a pure integrator (tested) + 3D-pipeline ribbon. Growing Ivy reuses `EffectOutline` (see `OutlineGlowView`'s `outlinePolyline`).

**Files:** Modify `EffectKind.swift`, `SurfaceContentView.swift`; create `Sources/LumoraKit/StrangeAttractor.swift`, `Tests/LumoraTests/StrangeAttractorTests.swift`, `scripts/verify_attractor_ivy.swift`.

- [ ] **Step 1: Write failing test**

```swift
// Tests/LumoraTests/StrangeAttractorTests.swift
import XCTest
@testable import LumoraKit

final class StrangeAttractorTests: XCTestCase {
    func testLorenzStaysBoundedAndFinite() {
        let pts = StrangeAttractor.lorenz(steps: 5000, dt: 0.005)
        XCTAssertEqual(pts.count, 5000)
        for p in pts {
            XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.z.isFinite)
            XCTAssertLessThan(abs(p.x), 100); XCTAssertLessThan(abs(p.y), 100); XCTAssertLessThan(abs(p.z), 100)
        }
    }
    func testDeterministic() {
        XCTAssertEqual(StrangeAttractor.lorenz(steps: 100, dt: 0.01).last!.x,
                       StrangeAttractor.lorenz(steps: 100, dt: 0.01).last!.x, accuracy: 1e-12)
    }
}
```

- [ ] **Step 2: Run — fails.**

- [ ] **Step 3: Implement**

```swift
// Sources/LumoraKit/StrangeAttractor.swift
import Foundation

public struct AttractorPoint: Equatable { public var x, y, z: Double }

public enum StrangeAttractor {
    /// Classic Lorenz system, RK-free forward Euler (fine at small dt). Fixed
    /// seed → deterministic. Returns the integrated polyline.
    public static func lorenz(steps: Int, dt: Double,
                              sigma: Double = 10, rho: Double = 28, beta: Double = 8.0/3.0) -> [AttractorPoint] {
        var x = 0.1, y = 0.0, z = 0.0
        var out: [AttractorPoint] = []; out.reserveCapacity(steps)
        for _ in 0..<steps {
            let dx = sigma * (y - x)
            let dy = x * (rho - z) - y
            let dz = x * y - beta * z
            x += dx * dt; y += dy * dt; z += dz * dt
            out.append(AttractorPoint(x: x, y: y, z: z))
        }
        return out
    }
}
```

- [ ] **Step 4: Run — passes.**

- [ ] **Step 5: Wire + renderers.** `strangeAttractor` (`.threeD`, rainbow/color) + `growingIvy` (`.edge`, uses color+accent).

  - **Strange Attractor** in `threeDEffects`: compute `lorenz` once (cache in a per-view `@State`, recompute per ~30s cycle), normalize into a unit cube, rotate with `rot3(time*speed…)`, project (cam code from `drawPointCloud3D`), draw as a connected polyline with depth-cued width + rainbow along arc length, `plusLighter` glow.
  - **Growing Ivy** in `edgeEffects`: take `outlinePolyline(size)` (extract/reuse from `OutlineGlowView` — make it accessible or duplicate the small helper), grow a stem along it up to `progress`; sprout side-branches at intervals with leaves (small filled ovals) appearing as the stem passes; a per-view `@State startRef` drives grow → hold → autumn hue-shift (`color`→`accent`) → leaf-fall → regrow.

- [ ] **Step 6: Verify + run** `swift build && swift test && swift scripts/verify_attractor_ivy.swift`.

- [ ] **Step 7: Commit** `feat: Strange Attractor + Growing Ivy effects`

- [ ] **Step 8: ⛳ CHECKPOINT 8** — `swift run`; user confirms. **Wait for go-ahead.**

---

## Task 13: Maze Generate & Solve + Countdown Timer  — ⛳ CHECKPOINT 9

Maze needs a pure generator + solver (tested). Countdown needs a config + panel + real-time clock + fireworks-reuse finale.

**Files:** Modify `EffectKind.swift`, `SurfaceContentView.swift`, `Surface.swift`, `PropertiesPanelView.swift`; create `Sources/LumoraKit/Maze.swift`, `Sources/LumoraKit/CountdownConfig.swift`, `Tests/LumoraTests/MazeTests.swift`, `Tests/LumoraTests/CountdownConfigTests.swift`, `scripts/verify_maze_countdown.swift`.

- [ ] **Step 1: Write failing Maze test**

```swift
// Tests/LumoraTests/MazeTests.swift
import XCTest
@testable import LumoraKit

final class MazeTests: XCTestCase {
    func testPerfectMazeHasExactlyOnePathBetweenAnyTwoCells() {
        let m = Maze.generate(cols: 12, rows: 8, seed: 3)
        // A perfect maze on N cells has exactly N-1 removed walls (edges).
        XCTAssertEqual(m.passages.count, 12 * 8 - 1)
        XCTAssertTrue(m.isFullyConnected())
    }
    func testSolveFindsPathFromStartToEnd() {
        let m = Maze.generate(cols: 12, rows: 8, seed: 3)
        let path = m.solve()
        XCTAssertEqual(path.first, MazeCell(x: 0, y: 0))
        XCTAssertEqual(path.last, MazeCell(x: 11, y: 7))
        // Consecutive path cells must be adjacent AND connected by a passage.
        for i in 1..<path.count { XCTAssertTrue(m.connected(path[i-1], path[i])) }
    }
    func testDeterministicForSeed() {
        XCTAssertEqual(Maze.generate(cols: 10, rows: 10, seed: 9).passages,
                       Maze.generate(cols: 10, rows: 10, seed: 9).passages)
    }
}
```

- [ ] **Step 2: Run — fails.**

- [ ] **Step 3: Implement `Maze`** — `struct MazeCell: Hashable { var x, y: Int }`; `struct Maze { let cols, rows: Int; let passages: Set<Passage> }` where a `Passage` is an unordered cell pair. `generate(cols:rows:seed:)` = recursive backtracker with a seeded PRNG (reuse the `hash01`-style deterministic hashing already in the repo, or a small LCG). `connected(_:_:)`, `isFullyConnected()` (BFS reaches all cells), `solve()` = BFS/A* from (0,0) to (cols-1,rows-1) following passages. All pure.

- [ ] **Step 4: Run — passes.**

- [ ] **Step 5: Write failing Countdown test**

```swift
// Tests/LumoraTests/CountdownConfigTests.swift
import XCTest
@testable import LumoraKit

final class CountdownConfigTests: XCTestCase {
    func testDefaults() {
        let c = CountdownConfig()
        XCTAssertEqual(c.label, "")
        XCTAssertTrue(c.finale)
    }
    func testRoundTrips() throws {
        let c = CountdownConfig(target: Date(timeIntervalSince1970: 1_800_000_000), label: "NYE", finale: false)
        let back = try JSONDecoder().decode(CountdownConfig.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back, c)
    }
}
```

- [ ] **Step 6: Implement `CountdownConfig`** per spec (default `target` = next midnight computed in the init, `label ""`, `finale true`). Add `countdown: CountdownConfig?` to `Surface` (recipe: CodingKeys + init param + `decodeIfPresent`). Run — passes.

- [ ] **Step 7: Wire + renderers.** `mazeSolve` (`.patterns`, uses color+accent) + `countdown` (`.clocks`, uses color+accent).

  - **Maze** in `patternEffects`: `Maze.generate` once per cycle (per-view `@State`), draw walls progressively with a glowing head (Circuit-Trace style) during a "carve" phase, then trace `solve()` path in `accent` with a runner glow, hold, fade, re-seed — `@State startRef` cycle.
  - **Countdown** in `clockEffects`: uses **real wall-clock time** (`Date()`, like `DigitalClockView` — NOT `time`). Compute remaining to `config.target`; format adaptively (`d h m s` > 24h, `h:mm:ss` < day, `m:ss` < 10min, pulsing seconds < 10s). At/after zero: if `finale`, render ~20s of the existing fireworks (call the fireworks renderer / reuse its code) behind a label swap, then hold. Thread `countdown: surface.countdown` through `EffectView`; add a panel section (date picker, label `TextField`, finale `Toggle`) gated on `effectKind == .countdown`.

- [ ] **Step 8: Verify + run** `swift build && swift test && swift scripts/verify_maze_countdown.swift`.

- [ ] **Step 9: Commit** `feat: Maze Generate & Solve + Countdown Timer effects`

- [ ] **Step 10: ⛳ CHECKPOINT 9** — `swift run`; user tests maze carve/solve and sets a countdown target ~1 min out to watch the finale. **Wait for go-ahead.**

---

## Task 14: Physarum + Lenia (baked) + Living Systems category  — ⛳ CHECKPOINT 10

Both follow the Game of Life bake precedent exactly (`scripts/generate_gol.swift` + `GameOfLifePattern` + `Package.swift` already `.process("Resources")`). This task also creates the `.livingSystems` category and moves `gameOfLife` + `reactionDiffusion` into it.

**Files:** Modify `EffectKind.swift` (2 cases + new category + 2 moves), `EffectCategory` enum, `SurfaceContentView.swift`; create `scripts/generate_physarum.swift`, `scripts/generate_lenia.swift`, `Sources/Lumora/PhysarumPattern.swift`, `Sources/Lumora/LeniaPattern.swift`, resources `Sources/Lumora/Resources/physarum.json` + `lenia.json`, `scripts/verify_physarum_lenia.swift`.

- [ ] **Step 1: Add `.livingSystems` category.** In `EffectCategory`: add `case livingSystems`, a `displayName` "Living Systems". In `EffectKind.category`, move `gameOfLife` and `reactionDiffusion` out of `.ambient` into `.livingSystems` (they'll join `physarum`/`lenia`). Build + confirm the picker shows the new category with GoL + Reaction-Diffusion. Commit `chore: add Living Systems category`.

- [ ] **Step 2: Physarum bake script.** `scripts/generate_physarum.swift`: simulate ~5000 agents (pos+heading) on a 128×72 pheromone grid — deposit, sense 3 points ahead, steer toward strongest, diffuse (box blur) + evaporate each step. Bake the trail field quantized to 4-bit (nibble-packed, 2 cells/byte), ~1200 frames. Write `{cols,rows,frames,data(base64)}` to `Sources/Lumora/Resources/physarum.json`. Print frame/byte counts; if > 6 MB, drop to 96×54 or 900 frames. Run: `swift scripts/generate_physarum.swift`.

- [ ] **Step 3: `PhysarumPattern` loader** — model on `GameOfLifePattern`, but `intensity(frame:x:y:) -> Double` reads a 4-bit nibble → `0…1`. Renderer `case .physarum:` in a `livingSystemsEffects` `@ViewBuilder` (create it; route `.livingSystems` kinds through it — gameOfLife/reactionDiffusion keep their existing renderers, just move the `case`s into the new builder): map intensity → `color` glow (`plusLighter`), hue drift toward `accent` at high intensity; loop frames, reset at end.

- [ ] **Step 4: Lenia bake + loader.** `scripts/generate_lenia.swift`: continuous CA (a growth function over a smooth kernel-convolved neighborhood); search a few known-good `(kernel radius, μ, σ)` sets × seeds for the liveliest (activity metric like `generate_gol.swift`), bake state quantized 4-bit, ~1200 frames → `lenia.json`. `LeniaPattern` loader mirrors Physarum. Renderer `case .lenia:` maps state → rainbow hue (like GoL per-gen hue), glowing.

- [ ] **Step 5: Verify + run** `swift build && swift scripts/verify_physarum_lenia.swift` (assert loaders return non-nil patterns with expected frame counts, renders non-blank). Note: resources must be built into the bundle — `swift build` picks them up via `.process("Resources")`.

- [ ] **Step 6: Commit** `feat: Physarum + Lenia baked effects (Living Systems)`

- [ ] **Step 7: ⛳ CHECKPOINT 10** — `swift run`; user confirms both loop smoothly and GoL/Reaction-Diffusion still work under the new category. **Wait for go-ahead.**

---

## Task 15: Falling Sand (baked) + final polish  — ⛳ CHECKPOINT 11

**Files:** Modify `EffectKind.swift`, `SurfaceContentView.swift`; create `scripts/generate_fallingsand.swift`, `Sources/Lumora/FallingSandPattern.swift`, `Sources/Lumora/Resources/fallingsand.json`, `scripts/verify_fallingsand.swift`; update `README.md`, `docs/BACKLOG.md`.

- [ ] **Step 1: Falling Sand bake.** `scripts/generate_fallingsand.swift`: sand cellular automaton on ~160×90 — 2–3 moving spouts emit colored grains; each step, grains fall / slide diagonally into empty cells, pile up; periodically drain the floor and restart. Bake **palette indices** 4-bit (fixed warm palette: ~6 sand colors + empty=0), ~1400 frames → `fallingsand.json` with an extra `palette` key (array of hex or rgba). Print counts. Run it.

- [ ] **Step 2: `FallingSandPattern` loader** (`colorIndex(frame:x:y:) -> Int` from nibbles + a decoded `palette: [RGBAColor]`). Renderer `case .fallingSand:` (`.livingSystems`, fixed-palette): draw each non-empty cell as a filled rect in its palette color; loop.

- [ ] **Step 3: Verify + run** `swift build && swift scripts/verify_fallingsand.swift`.

- [ ] **Step 4: Update docs.** README: bump effect count 63 → 79, add the 16 effects under their categories + the new "Living Systems" category + the "Audio Reactive" toggle note. `docs/BACKLOG.md`: add a "Done recently (2026-07-15)" section summarizing the audio abstraction + 16 effects; mark the audio-everywhere backlog idea addressed.

- [ ] **Step 5: Full test + build + package.**

Run: `swift test && swift build && bash scripts/make_app.sh`
Expected: all tests pass, packaged app builds.

- [ ] **Step 6: Commit** `feat: Falling Sand effect + README/BACKLOG update (roster now 79)`

- [ ] **Step 7: ⛳ CHECKPOINT 11 (final)** — user does a full pass: every new effect in the picker, the Audio Reactive toggle across the 6 audio effects in the packaged app, and confirms old `.lumora` projects still open. **Wait for sign-off, then this plan is complete.**

---

## Self-Review notes (author)

- **Spec coverage:** Part 1 (AudioLevels ext, BeatDetector, analyzer integration, toggle, 5 retrofits) → Tasks 1–7. All 16 Part-2 effects → Tasks 7–15 (Chladni in 7; the other 15 across 8–15). New "Living Systems" category + gameOfLife/reactionDiffusion moves → Task 14. Persistence/compat (audioReactive, countdown decodeIfPresent) → Tasks 4, 13. Testing (BeatDetector, spectrum bins, maze, Hilbert, attractor, Chladni, CountdownConfig) → dedicated test steps. Verify scripts → one per set. Packaged-app mic testing → every audio checkpoint.
- **Ordering honors the user:** Part 1 fully first; then low-effort Part 2 (canvas re-skins, small engine/3D deltas) before medium (ink/aquarium/attractor/ivy/maze/countdown) before the heavy baked sims (physarum/lenia/sand) last. A test checkpoint after every 2 effects.
- **Type consistency:** `AudioLevels.spectrum/beatCount/beatStrength`, `BeatDetector.process(bass:)->(isBeat:strength:)`, `ChladniField.value(x:y:n:m:)`/`modeForBands`, `HilbertCurve.points(order:)`, `StrangeAttractor.lorenz(steps:dt:)`/`AttractorPoint`, `Maze.generate(cols:rows:seed:)`/`MazeCell`/`solve()`/`connected`, `CountdownConfig(target:label:finale:)`, `AudioReactiveEffect(active:)` used consistently across tasks.
- **Known judgment calls left to the implementer:** exact Canvas aesthetic tuning (opacities, counts, blur radii) — the code blocks are working starting points, not frozen values; bake grid/frame sizes may need trimming to hit the ~6 MB resource ceiling.
