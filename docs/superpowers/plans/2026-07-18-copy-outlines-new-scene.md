# Copy Outlines Into New Scene — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the user adds a scene and the active scene has surfaces, prompt them to copy those surface outlines (geometry preserved, effect reset to grid) into the new scene.

**Architecture:** A pure, unit-tested `LumoraKit` helper (`Surface.outlineCopyWithGrid()`) performs the geometry-preserving copy with a fresh id and grid media. `ProjectStore.addScene(copyOutlinesFromActive:)` (app module) uses it to seed the new scene. `SceneStripView` gates the `+` button on the active scene having surfaces and shows a three-button confirmation dialog. TDD covers the helper; the store/UI wiring is verified by build + manual demo (the app module is not in the test target).

**Tech Stack:** Swift, SwiftUI, XCTest, SwiftPM. macOS app (`Lumora`) + `LumoraKit` library + `LumoraTests` (depends on `LumoraKit` only).

## Global Constraints

- `LumoraTests` depends on **`LumoraKit` only** — the app module (`Lumora`, which holds `ProjectStore`/`SceneStripView`) is **not** unit-testable. All new automated tests target `LumoraKit`.
- Grid default media must exactly match `ProjectStore.addSurface()`: `.effect(.grid, .cyan, RGBAColor(r: 0.05, g: 0.06, b: 0.09))`.
- No changes to the `.lumora` save format or the `Project`/`ProjectScene`/`Surface` stored properties.
- `addScene()`'s existing no-argument call sites must keep working unchanged (use a defaulted parameter).
- `swift test` must remain green (currently 96/96).

---

## File Structure

- `Sources/LumoraKit/Surface.swift` (modify) — add the pure `outlineCopyWithGrid()` method in an extension.
- `Tests/LumoraTests/SurfaceOutlineCopyTests.swift` (create) — unit tests for the helper.
- `Sources/Lumora/ProjectStore.swift` (modify) — `addScene(copyOutlinesFromActive:)`.
- `Sources/Lumora/Views/SceneStripView.swift` (modify) — `+` button gating + confirmation dialog.

---

### Task 1: Pure outline-copy helper in LumoraKit

**Files:**
- Modify: `Sources/LumoraKit/Surface.swift`
- Test: `Tests/LumoraTests/SurfaceOutlineCopyTests.swift`

**Interfaces:**
- Consumes: `Surface`, `MediaAssignment.effect`, `EffectKind.grid`, `RGBAColor` (all existing `LumoraKit` types).
- Produces: `Surface.outlineCopyWithGrid() -> Surface` — returns a copy of the receiver with a **new** `id`, `media` set to `.effect(.grid, .cyan, RGBAColor(r: 0.05, g: 0.06, b: 0.09))`, and every other stored property (`name`, `points`, `shape`, `rotation`, `opacity`, `zIndex`, `isVisible`, and all per-effect config structs) preserved unchanged.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/SurfaceOutlineCopyTests.swift`:

```swift
import XCTest
@testable import LumoraKit

final class SurfaceOutlineCopyTests: XCTestCase {
    private func sourceSurface() -> Surface {
        var s = Surface(
            name: "Wall Panel",
            points: [
                CGPoint(x: 0.1, y: 0.2),
                CGPoint(x: 0.4, y: 0.25),
                CGPoint(x: 0.4, y: 0.6),
                CGPoint(x: 0.1, y: 0.55),
            ],
            shape: .quad,
            media: .effect(.aurora, .magenta, .violet)
        )
        s.rotation = 0.35
        s.opacity = 0.7
        s.zIndex = 3
        s.isVisible = false
        return s
    }

    func testPreservesGeometryAndDisplayProperties() {
        let src = sourceSurface()
        let copy = src.outlineCopyWithGrid()
        XCTAssertEqual(copy.name, src.name)
        XCTAssertEqual(copy.points, src.points)
        XCTAssertEqual(copy.shape, src.shape)
        XCTAssertEqual(copy.rotation, src.rotation)
        XCTAssertEqual(copy.opacity, src.opacity)
        XCTAssertEqual(copy.zIndex, src.zIndex)
        XCTAssertEqual(copy.isVisible, src.isVisible)
    }

    func testGetsFreshIdentity() {
        let src = sourceSurface()
        let copy = src.outlineCopyWithGrid()
        XCTAssertNotEqual(copy.id, src.id)
    }

    func testMediaResetToGridDefault() {
        let copy = sourceSurface().outlineCopyWithGrid()
        XCTAssertEqual(
            copy.media,
            .effect(.grid, .cyan, RGBAColor(r: 0.05, g: 0.06, b: 0.09))
        )
    }

    func testSourceIsNotMutated() {
        let src = sourceSurface()
        let originalID = src.id
        _ = src.outlineCopyWithGrid()
        XCTAssertEqual(src.id, originalID)
        XCTAssertEqual(src.media, .effect(.aurora, .magenta, .violet))
    }
}
```

> Note: confirm `Surface`'s initializer parameter labels and the `EffectKind`/`RGBAColor` cases used above (`.aurora`, `.magenta`, `.violet`) exist; if a name differs, substitute any valid non-grid effect + two valid colors — the test only needs a source distinct from the grid default.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SurfaceOutlineCopyTests`
Expected: FAIL — compile error `value of type 'Surface' has no member 'outlineCopyWithGrid'`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/LumoraKit/Surface.swift` (after the closing brace of the `Surface` struct, at file scope):

```swift
extension Surface {
    /// A copy of this surface's outline for seeding a new scene: geometry and
    /// display properties are preserved, the identity is fresh, and the effect
    /// is reset to the default `grid` alignment effect (matching
    /// `ProjectStore.addSurface()`).
    public func outlineCopyWithGrid() -> Surface {
        var copy = self
        copy.id = UUID()
        copy.media = .effect(.grid, .cyan, RGBAColor(r: 0.05, g: 0.06, b: 0.09))
        return copy
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SurfaceOutlineCopyTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS — 100/100 (was 96, +4 new).

- [ ] **Step 6: Commit**

```bash
git add Sources/LumoraKit/Surface.swift Tests/LumoraTests/SurfaceOutlineCopyTests.swift
git commit -m "feat(kit): Surface.outlineCopyWithGrid for scene outline copy

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `addScene(copyOutlinesFromActive:)` in ProjectStore

**Files:**
- Modify: `Sources/Lumora/ProjectStore.swift:72-75`

**Interfaces:**
- Consumes: `Surface.outlineCopyWithGrid()` (Task 1); `ProjectStore.activeScene`, `ProjectStore.scenes`, `ProjectStore.selectScene(_:)`, `ProjectScene`.
- Produces: `ProjectStore.addScene(copyOutlinesFromActive: Bool = false)` — appends a new scene named `"Scene N"`. When `copyOutlinesFromActive == true`, the new scene's `surfaces` are `activeScene?.surfaces.map { $0.outlineCopyWithGrid() }` (read before the append); otherwise empty. Always selects the new scene. The defaulted parameter keeps `addScene()` callers unchanged.

- [ ] **Step 1: Replace the existing `addScene()`**

Current (`Sources/Lumora/ProjectStore.swift:72-75`):

```swift
    func addScene() {
        scenes.append(ProjectScene(name: "Scene \(scenes.count + 1)"))
        selectScene(scenes.count - 1)
    }
```

Replace with:

```swift
    /// Add a new scene. When `copyOutlinesFromActive` is true and the active
    /// scene has surfaces, each is copied into the new scene with its outline
    /// preserved and the effect reset to `grid` (see
    /// `Surface.outlineCopyWithGrid()`); copies are independent (fresh ids).
    func addScene(copyOutlinesFromActive: Bool = false) {
        var newScene = ProjectScene(name: "Scene \(scenes.count + 1)")
        if copyOutlinesFromActive, let source = activeScene {
            newScene.surfaces = source.surfaces.map { $0.outlineCopyWithGrid() }
        }
        scenes.append(newScene)
        selectScene(scenes.count - 1)
    }
```

> `activeScene` is read before `scenes.append`, so it still refers to the source scene. Confirm `ProjectScene.surfaces` is settable (it is — `ProjectStore.surfaces` writes `scenes[i].surfaces`).

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build complete, no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/Lumora/ProjectStore.swift
git commit -m "feat: ProjectStore.addScene can copy active scene outlines

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: `+` button prompt in SceneStripView

**Files:**
- Modify: `Sources/Lumora/Views/SceneStripView.swift` (the `+` `Button` at ~line 24; add `@State` near lines 10-15; attach `.confirmationDialog` on the `body`'s outer view).

**Interfaces:**
- Consumes: `ProjectStore.activeScene`, `ProjectStore.addScene(copyOutlinesFromActive:)` (Task 2).
- Produces: UI only — no new symbols consumed by later tasks.

- [ ] **Step 1: Add prompt state**

In `SceneStripView`, add alongside the existing `@State` properties (near `Sources/Lumora/Views/SceneStripView.swift:10-15`):

```swift
    @State private var showCopyPrompt = false
```

- [ ] **Step 2: Gate the `+` button on the active scene having surfaces**

Replace the existing add button (`Sources/Lumora/Views/SceneStripView.swift:24-28`):

```swift
                    Button { store.addScene() } label: {
                        Image(systemName: "plus").frame(width: 22, height: 22)
                    }
                    .buttonStyle(.bordered)
                    .help("Add scene")
```

with:

```swift
                    Button {
                        if store.activeScene?.surfaces.isEmpty == false {
                            showCopyPrompt = true
                        } else {
                            store.addScene()
                        }
                    } label: {
                        Image(systemName: "plus").frame(width: 22, height: 22)
                    }
                    .buttonStyle(.bordered)
                    .help("Add scene")
```

- [ ] **Step 3: Attach the confirmation dialog**

On the outer view of `body` — the `HStack(spacing: 10) { ... }` that already carries `.padding`/`.frame`/`.background`/`.onDisappear` (ends around `Sources/Lumora/Views/SceneStripView.swift:39`) — add after `.onDisappear { previewTimer = nil }`:

```swift
        .confirmationDialog(
            "Copy surface outlines from this scene into the new one?",
            isPresented: $showCopyPrompt,
            titleVisibility: .visible
        ) {
            Button("Copy Outlines") { store.addScene(copyOutlinesFromActive: true) }
            Button("Empty Scene") { store.addScene() }
            Button("Cancel", role: .cancel) {}
        }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build`
Expected: Build complete, no errors.

- [ ] **Step 5: Commit**

```bash
git add Sources/Lumora/Views/SceneStripView.swift
git commit -m "feat: prompt to copy outlines when adding a scene

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Manual verification on the packaged app

**Files:** none (verification only).

- [ ] **Step 1: Full test + build**

Run: `swift test && swift build`
Expected: tests PASS (100/100), build succeeds.

- [ ] **Step 2: Launch the packaged `.app` and demo**

Build/launch the packaged app (per the project's run skill / usual launch — the packaged `.app`, not `swift run`, per memory: launch pitfall). Then:

1. In Scene 1, draw one or two surfaces (varied shape/rotation).
2. Press the `+` in the scene strip → the confirmation dialog appears with **Copy Outlines / Empty Scene / Cancel**.
3. Choose **Copy Outlines** → the new scene shows the same outline(s), each rendering the grid effect. Move one copy and switch back — the source scene is unchanged (independent copies).
4. Press `+` again → choose **Empty Scene** → blank scene, no copies.
5. From an empty scene, press `+` → a new scene is added with **no** prompt.

- [ ] **Step 3: Final confirmation**

Confirm all five behaviors match. No commit (verification only). If any step fails, return to the relevant task.

---

## Self-Review

**Spec coverage:**
- Prompt only when active scene has surfaces → Task 3 Step 2 gate. ✅
- Three-button dialog (Copy / Empty / Cancel) → Task 3 Step 3. ✅
- Copy preserves name/points/shape/rotation/opacity/zIndex/isVisible, fresh id, media→grid, configs dormant → Task 1 helper + tests. ✅
- Source = active scene, read before append → Task 2. ✅
- Additive default arg keeps existing callers → Task 2 (`= false`). ✅
- No save-format/model change → helper + store only; no stored props added. ✅
- Verification (build, `swift test`, manual demo) → Task 4. ✅

**Placeholder scan:** No TBD/TODO; all code shown. The one caveat note (Task 1 Step 1) is a verification instruction with a concrete fallback, not a placeholder. ✅

**Type consistency:** `outlineCopyWithGrid()` defined in Task 1 and consumed identically in Task 2; `addScene(copyOutlinesFromActive:)` defined in Task 2 and called identically in Task 3; grid media literal identical across helper and spec. ✅
