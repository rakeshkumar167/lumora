# Light Line Network Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a draw-a-glowing-line-network drawable to Lumora: click-to-drop joints, connect/fork lines, and a pulse that emits from a source joint, splits at forks, and fills the whole network before holding and resetting.

**Architecture:** A new standalone `LightLine` model (a graph of joints + segments + a source joint + style) lives in `LumoraKit` alongside `Surface`, with pure, unit-tested graph/animation math. The app layer adds a `LightLineView` renderer (glow via blur + `.plusLighter`, a fill front driven by graph distance-from-source), a pen-tool editing overlay, and sidebar/properties/persistence plumbing parallel to surfaces.

**Tech Stack:** Swift 5.9, SwiftUI (`Canvas`, `TimelineView`, `SpatialTapGesture`), AppKit, XCTest. Swift Package (no `.xcodeproj`); run with `swift run Lumora`, test with `swift test`, build with `swift build`.

## Global Constraints

- Platform: macOS 14+ (`Package.swift` `platforms: [.macOS(.v14)]`). `SpatialTapGesture`, `ContentUnavailableView` require macOS 14 — available.
- `LumoraKit` is **UI-free**: no SwiftUI/AppKit imports. Only `Foundation` / `CoreGraphics`. Model colors use `RGBAColor`, bridged to `Color` in the app via `ColorBridge.swift`.
- Only `LumoraKit` is unit-tested (target `LumoraTests`). App-layer views are verified by `swift build` succeeding plus offscreen `ImageRenderer` PNGs and running the app.
- The `time` passed to views from `TimelineView(.animation)` is a **global** monotonic clock (`timeline.date.timeIntervalSinceReferenceDate`), never reset per-view. Any "play from zero" animation MUST capture a start time in `.onAppear` via `@State` and compute `elapsed = time - startRef` (see `OutlineGlowView` in `SurfaceContentView.swift`).
- Glow recipe: `ctx.drawLayer { $0.addFilter(.blur(radius:)); $0.blendMode = .plusLighter; ... }`. No per-pixel loops.
- Lines are drawn directly in normalized→canvas space with **no** homography warp (same convention as polygon/ellipse surfaces).
- Normalized coordinates are `0...1`. Clamp joint positions to that range.
- Commit after each task. End commit messages with the repo's co-author trailer:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`

---

### Task 1: `LightLine` model + graph/animation math (LumoraKit, TDD)

The correctness-critical pure core: model types, shortest-path distance-from-source, and the fill-front math. Fully unit-tested, like `Homography`.

**Files:**
- Create: `Sources/LumoraKit/LightLine.swift`
- Create: `Tests/LumoraTests/LightLineTests.swift`

**Interfaces:**
- Consumes: `RGBAColor` (existing, `Sources/LumoraKit/RGBAColor.swift`).
- Produces (later tasks rely on these exact names/types):
  - `LightLine.Joint { id: UUID; point: CGPoint }`
  - `LightLine.Segment { id: UUID; a: UUID; b: UUID }`
  - `LightLineStyle { color, glowColor: RGBAColor; thickness, glowRadius, fillDuration, holdDuration: Double }`, `LightLineStyle.default`
  - `LightLine { id: UUID; name: String; joints: [Joint]; segments: [Segment]; sourceJointID: UUID?; style: LightLineStyle; isVisible: Bool; opacity: Double }`, plus `LightLine.empty(name:)`
  - `func distancesFromSource() -> [UUID: Double]`
  - `func maxDistance() -> Double`
  - `func litFraction(of:front:distances:) -> Double`
  - `FillCycle { fillDuration, holdDuration: Double; func frontFraction(elapsed:) -> Double }`

- [ ] **Step 1: Write the failing tests**

Create `Tests/LumoraTests/LightLineTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import LumoraKit

final class LightLineTests: XCTestCase {
    // Helpers to build a line with known joints/segments.
    private func line(joints: [(UUID, CGPoint)], edges: [(UUID, UUID)], source: UUID?) -> LightLine {
        LightLine(
            name: "T",
            joints: joints.map { LightLine.Joint(id: $0.0, point: $0.1) },
            segments: edges.map { LightLine.Segment(a: $0.0, b: $0.1) },
            sourceJointID: source
        )
    }

    func testDistancesAlongAChain() {
        let a = UUID(), b = UUID(), c = UUID()
        // A(0,0) - B(0.5,0) - C(1,0); each segment length 0.5.
        let l = line(joints: [(a, CGPoint(x: 0, y: 0)), (b, CGPoint(x: 0.5, y: 0)), (c, CGPoint(x: 1, y: 0))],
                     edges: [(a, b), (b, c)], source: a)
        let d = l.distancesFromSource()
        XCTAssertEqual(d[a]!, 0, accuracy: 1e-9)
        XCTAssertEqual(d[b]!, 0.5, accuracy: 1e-9)
        XCTAssertEqual(d[c]!, 1.0, accuracy: 1e-9)
        XCTAssertEqual(l.maxDistance(), 1.0, accuracy: 1e-9)
    }

    func testForkDistancesAndDisconnectedJoint() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), lonely = UUID()
        // A(0,0)-B(0.4,0); B-C(0.4,0.3); B-D(0.4,-0.3). `lonely` has no edge.
        let l = line(joints: [(a, CGPoint(x: 0, y: 0)), (b, CGPoint(x: 0.4, y: 0)),
                              (c, CGPoint(x: 0.4, y: 0.3)), (d, CGPoint(x: 0.4, y: -0.3)),
                              (lonely, CGPoint(x: 0.9, y: 0.9))],
                     edges: [(a, b), (b, c), (b, d)], source: a)
        let dist = l.distancesFromSource()
        XCTAssertEqual(dist[a]!, 0, accuracy: 1e-9)
        XCTAssertEqual(dist[b]!, 0.4, accuracy: 1e-9)
        XCTAssertEqual(dist[c]!, 0.7, accuracy: 1e-9)
        XCTAssertEqual(dist[d]!, 0.7, accuracy: 1e-9)
        XCTAssertNil(dist[lonely]) // unreachable from source
    }

    func testLitFractionLightsFromNearEndpoint() {
        let a = UUID(), b = UUID(), c = UUID()
        let l = line(joints: [(a, CGPoint(x: 0, y: 0)), (b, CGPoint(x: 0.5, y: 0)), (c, CGPoint(x: 1, y: 0))],
                     edges: [(a, b), (b, c)], source: a)
        let dist = l.distancesFromSource()
        let bc = l.segments[1] // B-C, near endpoint B at distance 0.5, length 0.5
        // front hasn't reached B yet.
        XCTAssertEqual(l.litFraction(of: bc, front: 0.25, distances: dist), 0, accuracy: 1e-9)
        // front halfway across B-C.
        XCTAssertEqual(l.litFraction(of: bc, front: 0.75, distances: dist), 0.5, accuracy: 1e-9)
        // front past the far end → fully lit, clamped.
        XCTAssertEqual(l.litFraction(of: bc, front: 2.0, distances: dist), 1.0, accuracy: 1e-9)
    }

    func testLitFractionUnreachableSegmentIsZero() {
        // Source is nil → nothing reachable → every segment dark.
        let a = UUID(), b = UUID()
        let l = line(joints: [(a, CGPoint(x: 0, y: 0)), (b, CGPoint(x: 1, y: 0))],
                     edges: [(a, b)], source: nil)
        let dist = l.distancesFromSource()
        XCTAssertTrue(dist.isEmpty)
        XCTAssertEqual(l.litFraction(of: l.segments[0], front: 5, distances: dist), 0, accuracy: 1e-9)
    }

    func testFillCyclePhases() {
        let c = FillCycle(fillDuration: 2, holdDuration: 1) // period 3
        XCTAssertEqual(c.frontFraction(elapsed: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(c.frontFraction(elapsed: 1), 0.5, accuracy: 1e-9)   // mid-fill
        XCTAssertEqual(c.frontFraction(elapsed: 2), 1.0, accuracy: 1e-9)   // fill complete
        XCTAssertEqual(c.frontFraction(elapsed: 2.5), 1.0, accuracy: 1e-9) // hold
        XCTAssertEqual(c.frontFraction(elapsed: 3), 0, accuracy: 1e-9)     // reset (wrap)
        XCTAssertEqual(c.frontFraction(elapsed: 4), 0.5, accuracy: 1e-9)   // next cycle mid-fill
    }

    func testCodableRoundTrip() throws {
        let a = UUID(), b = UUID()
        let original = line(joints: [(a, CGPoint(x: 0.1, y: 0.2)), (b, CGPoint(x: 0.8, y: 0.9))],
                            edges: [(a, b)], source: a)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LightLine.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LightLineTests`
Expected: FAIL to compile — `cannot find 'LightLine' in scope`.

- [ ] **Step 3: Write the model + math**

Create `Sources/LumoraKit/LightLine.swift`:

```swift
import CoreGraphics
import Foundation

/// Visual + timing parameters for a light line network.
public struct LightLineStyle: Equatable, Codable {
    public var color: RGBAColor       // primary line color
    public var glowColor: RGBAColor   // accent / tracer-head tint
    public var thickness: Double      // core line width in points
    public var glowRadius: Double     // blur radius for the glow layer
    public var fillDuration: Double   // seconds for the front to reach maxDistance
    public var holdDuration: Double   // seconds fully-lit before reset

    public init(
        color: RGBAColor = .cyan,
        glowColor: RGBAColor = .white,
        thickness: Double = 3,
        glowRadius: Double = 12,
        fillDuration: Double = 3,
        holdDuration: Double = 1.5
    ) {
        self.color = color
        self.glowColor = glowColor
        self.thickness = thickness
        self.glowRadius = glowRadius
        self.fillDuration = fillDuration
        self.holdDuration = holdDuration
    }

    public static let `default` = LightLineStyle()
}

/// A network of connected line segments that render as a glowing path with a
/// pulse that fills from a chosen source joint, splitting at forks.
///
/// The graph is undirected: `joints` are nodes (normalized 0...1 positions),
/// `segments` are edges referencing joint ids. A joint of degree >= 3 is a fork.
public struct LightLine: Identifiable, Equatable, Codable {
    public struct Joint: Identifiable, Equatable, Codable {
        public var id: UUID
        public var point: CGPoint    // normalized 0...1 room-space position
        public init(id: UUID = UUID(), point: CGPoint) {
            self.id = id
            self.point = point
        }
    }

    public struct Segment: Identifiable, Equatable, Codable {
        public var id: UUID
        public var a: UUID           // Joint.ID
        public var b: UUID           // Joint.ID
        public init(id: UUID = UUID(), a: UUID, b: UUID) {
            self.id = id
            self.a = a
            self.b = b
        }
    }

    public var id: UUID
    public var name: String
    public var joints: [Joint]
    public var segments: [Segment]
    public var sourceJointID: UUID?
    public var style: LightLineStyle
    public var isVisible: Bool
    public var opacity: Double

    public init(
        id: UUID = UUID(),
        name: String,
        joints: [Joint] = [],
        segments: [Segment] = [],
        sourceJointID: UUID? = nil,
        style: LightLineStyle = .default,
        isVisible: Bool = true,
        opacity: Double = 1
    ) {
        self.id = id
        self.name = name
        self.joints = joints
        self.segments = segments
        self.sourceJointID = sourceJointID
        self.style = style
        self.isVisible = isVisible
        self.opacity = opacity
    }

    /// An empty line ready for the pen tool to draw into.
    public static func empty(name: String) -> LightLine {
        LightLine(name: name)
    }

    // MARK: - Geometry / graph

    public func joint(_ id: UUID) -> Joint? {
        joints.first { $0.id == id }
    }

    /// Euclidean length of a segment in normalized space (0 if an endpoint is missing).
    public func length(of segment: Segment) -> Double {
        guard let a = joint(segment.a)?.point, let b = joint(segment.b)?.point else { return 0 }
        return Double(hypot(b.x - a.x, b.y - a.y))
    }

    /// Shortest-path distance (summed segment lengths) from the source joint to
    /// every reachable joint, keyed by joint id. Empty if there is no source.
    /// Unreachable joints are absent from the result.
    public func distancesFromSource() -> [UUID: Double] {
        guard let source = sourceJointID, joint(source) != nil else { return [:] }

        // Adjacency: joint id -> [(neighbor id, weight)].
        var adj: [UUID: [(UUID, Double)]] = [:]
        for s in segments {
            let w = length(of: s)
            adj[s.a, default: []].append((s.b, w))
            adj[s.b, default: []].append((s.a, w))
        }

        // Dijkstra (small graphs: linear scan for the min is fine).
        var dist: [UUID: Double] = [source: 0]
        var settled: Set<UUID> = []
        while true {
            // Pick the unsettled joint with the smallest tentative distance.
            var current: UUID?
            var best = Double.greatestFiniteMagnitude
            for (id, d) in dist where !settled.contains(id) && d < best {
                best = d
                current = id
            }
            guard let u = current else { break }
            settled.insert(u)
            for (v, w) in adj[u] ?? [] where !settled.contains(v) {
                let nd = best + w
                if nd < (dist[v] ?? .greatestFiniteMagnitude) {
                    dist[v] = nd
                }
            }
        }
        return dist
    }

    /// The largest reachable joint distance — the full-fill target. 0 if none.
    public func maxDistance() -> Double {
        distancesFromSource().values.max() ?? 0
    }

    /// Fraction (0...1) of `segment` that is lit given the current absolute
    /// front distance, lighting from the endpoint nearer the source outward.
    /// Returns 0 for segments unreachable from the source.
    public func litFraction(of segment: Segment, front: Double, distances: [UUID: Double]) -> Double {
        guard let dA = distances[segment.a], let dB = distances[segment.b] else { return 0 }
        let near = Swift.min(dA, dB)
        let segLen = length(of: segment)
        guard segLen > 0 else { return front >= near ? 1 : 0 }
        let f = (front - near) / segLen
        return Swift.min(Swift.max(f, 0), 1)
    }
}

/// The fill -> hold -> reset timing cycle. `frontFraction` returns the fill
/// front as a fraction (0...1) of the network's max distance for a given
/// elapsed time since the animation started.
public struct FillCycle: Equatable {
    public var fillDuration: Double
    public var holdDuration: Double

    public init(fillDuration: Double, holdDuration: Double) {
        self.fillDuration = fillDuration
        self.holdDuration = holdDuration
    }

    public func frontFraction(elapsed: Double) -> Double {
        let fill = Swift.max(fillDuration, 0.0001)
        let period = fill + Swift.max(holdDuration, 0)
        guard period > 0 else { return 1 }
        let p = elapsed.truncatingRemainder(dividingBy: period)
        let phase = p < 0 ? p + period : p
        return phase < fill ? phase / fill : 1
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LightLineTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/LightLine.swift Tests/LumoraTests/LightLineTests.swift
git commit -m "$(cat <<'EOF'
Add LightLine model + graph/fill math with tests

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Persistence + store plumbing

Add `lightLines` to `Project` (backward-compatible decode) and to `ProjectStore`, with the `.pen` tool, CRUD, selection, and pen mutations. UI wiring for save/open already round-trips `makeProject()`/`load(_:)`, so it inherits lines automatically.

**Files:**
- Modify: `Sources/LumoraKit/Project.swift`
- Modify: `Sources/Lumora/ProjectStore.swift`
- Test: `Tests/LumoraTests/ProjectCodableTests.swift` (create)

**Interfaces:**
- Consumes: `LightLine`, `LightLineStyle` (Task 1).
- Produces (used by Tasks 3–5):
  - `Project.lightLines: [LightLine]`
  - `ProjectStore.lightLines: [LightLine]` (`@Published`), `ProjectStore.selectedLineID: LightLine.ID?` (`@Published`)
  - `EditTool.pen`
  - `ProjectStore.selectedLine: LightLine?`, `selectedLineBinding() -> Binding<LightLine>?`
  - `addLine()`, `deleteLine(_:)`, `updateLine(_:_:)`, `selectLine(_:)`, `selectSurface(_:)`
  - `setLineSource(_ lineID:, _ jointID:)`, `deleteJoint(_ lineID:, _ jointID:)`
  - `addJoint(to lineID:, at point: CGPoint, connectingTo lastJointID: UUID?) -> UUID`

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/ProjectCodableTests.swift`:

```swift
import XCTest
@testable import LumoraKit

final class ProjectCodableTests: XCTestCase {
    // Old .lumora files have no `lightLines` key; they must still decode.
    func testDecodesLegacyProjectWithoutLightLines() throws {
        let json = """
        { "surfaces": [] }
        """.data(using: .utf8)!
        let project = try JSONDecoder().decode(Project.self, from: json)
        XCTAssertEqual(project.surfaces.count, 0)
        XCTAssertEqual(project.lightLines.count, 0)
    }

    func testRoundTripsLightLines() throws {
        let a = UUID(), b = UUID()
        let line = LightLine(
            name: "L1",
            joints: [.init(id: a, point: .init(x: 0.1, y: 0.1)), .init(id: b, point: .init(x: 0.9, y: 0.9))],
            segments: [.init(a: a, b: b)],
            sourceJointID: a
        )
        let project = Project(surfaces: [], lightLines: [line])
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(decoded.lightLines, [line])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ProjectCodableTests`
Expected: FAIL — `Project` has no `lightLines` member.

- [ ] **Step 3: Extend `Project` with backward-compatible decode**

Replace the entire contents of `Sources/LumoraKit/Project.swift`:

```swift
import Foundation

/// A saveable project: the ordered set of surfaces plus light line networks.
/// The room reference photo is managed by the app layer.
public struct Project: Codable, Equatable {
    public var surfaces: [Surface]
    public var lightLines: [LightLine]

    public init(surfaces: [Surface] = [], lightLines: [LightLine] = []) {
        self.surfaces = surfaces
        self.lightLines = lightLines
    }

    private enum CodingKeys: String, CodingKey {
        case surfaces, lightLines
    }

    // Custom decode so older `.lumora` files (saved before `lightLines`
    // existed) still load. Encoding stays synthesized.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        surfaces = try c.decode([Surface].self, forKey: .surfaces)
        lightLines = try c.decodeIfPresent([LightLine].self, forKey: .lightLines) ?? []
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ProjectCodableTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Add store plumbing**

In `Sources/Lumora/ProjectStore.swift`:

Add the `pen` case to `EditTool` (line ~7-11):

```swift
enum EditTool: String, CaseIterable, Identifiable {
    case arrow   // drag corner handles to warp the surface
    case hand    // drag anywhere inside to move the whole surface
    case pen     // click to drop/connect joints of the selected light line
    var id: String { rawValue }
}
```

Add published state next to the existing `@Published` properties (after `var tool`):

```swift
    @Published var lightLines: [LightLine] = []
    @Published var selectedLineID: LightLine.ID?
```

Update `makeProject()` and `load(_:)`:

```swift
    /// The current editable state as a saveable document.
    func makeProject() -> Project { Project(surfaces: surfaces, lightLines: lightLines) }

    /// Replace all surfaces and light lines with those from a loaded project.
    func load(_ project: Project) {
        surfaces = project.surfaces
        lightLines = project.lightLines
        selectedID = surfaces.first?.id
        selectedLineID = nil
    }
```

Add the light-line API (place after `update(_:_:)` at the end of the class, before the closing brace):

```swift
    // MARK: - Light lines

    var selectedLine: LightLine? { lightLines.first { $0.id == selectedLineID } }

    /// A binding to the currently selected light line, for the properties panel.
    func selectedLineBinding() -> Binding<LightLine>? {
        guard let id = selectedLineID, lightLines.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.lightLines.first { $0.id == id } ?? LightLine.empty(name: "") },
            set: { newValue in
                if let i = self.lightLines.firstIndex(where: { $0.id == id }) {
                    self.lightLines[i] = newValue
                }
            }
        )
    }

    /// Create a new empty light line, select it, and switch to the pen tool.
    func addLine() {
        let line = LightLine.empty(name: "Line \(lightLines.count + 1)")
        lightLines.append(line)
        selectLine(line.id)
        tool = .pen
    }

    /// Select a light line (clearing any surface selection).
    func selectLine(_ id: LightLine.ID) {
        selectedLineID = id
        selectedID = nil
    }

    /// Select a surface (clearing any light-line selection).
    func selectSurface(_ id: Surface.ID) {
        selectedID = id
        selectedLineID = nil
    }

    func deleteLine(_ id: LightLine.ID) {
        lightLines.removeAll { $0.id == id }
        if selectedLineID == id { selectedLineID = nil }
    }

    func updateLine(_ id: LightLine.ID, _ mutate: (inout LightLine) -> Void) {
        guard let i = lightLines.firstIndex(where: { $0.id == id }) else { return }
        mutate(&lightLines[i])
    }

    /// Set (or move) the source joint of a line.
    func setLineSource(_ lineID: LightLine.ID, _ jointID: UUID) {
        updateLine(lineID) { $0.sourceJointID = jointID }
    }

    /// Delete a joint and any segments touching it. Clears the source if it was it.
    func deleteJoint(_ lineID: LightLine.ID, _ jointID: UUID) {
        updateLine(lineID) { line in
            line.joints.removeAll { $0.id == jointID }
            line.segments.removeAll { $0.a == jointID || $0.b == jointID }
            if line.sourceJointID == jointID { line.sourceJointID = line.joints.first?.id }
        }
    }

    /// Append a joint at a normalized point, connecting it to `lastJointID`
    /// with a new segment (unless nil). If the line has no source yet, the
    /// first joint created becomes the source. Returns the target joint's id.
    @discardableResult
    func addJoint(to lineID: LightLine.ID, at point: CGPoint, connectingTo lastJointID: UUID?) -> UUID {
        let joint = LightLine.Joint(point: point)
        updateLine(lineID) { line in
            line.joints.append(joint)
            if let last = lastJointID, last != joint.id {
                line.segments.append(LightLine.Segment(a: last, b: joint.id))
            }
            if line.sourceJointID == nil { line.sourceJointID = joint.id }
        }
        return joint.id
    }

    /// Connect an existing joint to `lastJointID` with a segment (used when a
    /// pen click snaps onto an existing joint). No-op if already the same joint.
    func connectJoint(to lineID: LightLine.ID, existing jointID: UUID, from lastJointID: UUID?) {
        guard let last = lastJointID, last != jointID else { return }
        updateLine(lineID) { line in
            // Avoid duplicate segments between the same pair.
            let exists = line.segments.contains {
                ($0.a == last && $0.b == jointID) || ($0.a == jointID && $0.b == last)
            }
            if !exists { line.segments.append(LightLine.Segment(a: last, b: jointID)) }
        }
    }
```

- [ ] **Step 6: Verify it builds and tests pass**

Run: `swift build && swift test`
Expected: build succeeds; all tests pass (Homography + LightLine + ProjectCodable).

- [ ] **Step 7: Commit**

```bash
git add Sources/LumoraKit/Project.swift Sources/Lumora/ProjectStore.swift Tests/LumoraTests/ProjectCodableTests.swift
git commit -m "$(cat <<'EOF'
Persist light lines and add store plumbing

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `LightLineView` renderer + canvas integration

Draw the glowing network with the moving tracer, and composite it in both the editor preview and the fullscreen projection. Verified offscreen with `ImageRenderer`.

**Files:**
- Create: `Sources/Lumora/Views/LightLineView.swift`
- Modify: `Sources/Lumora/Views/RoomCanvasView.swift` (add lines to the ZStack)
- Modify: `Sources/Lumora/Views/ProjectionView.swift` (add lines to the ZStack)
- Verify: `scripts/verify_lightline.swift` (create; throwaway offscreen render)

**Interfaces:**
- Consumes: `LightLine`, `FillCycle`, `distancesFromSource()`, `litFraction(of:front:distances:)`, `maxDistance()` (Task 1); `RGBAColor.color` bridge (`ColorBridge.swift`).
- Produces: `struct LightLineView: View { init(line:canvasSize:time:) }`.

- [ ] **Step 1: Create the renderer**

Create `Sources/Lumora/Views/LightLineView.swift`:

```swift
import LumoraKit
import SwiftUI

/// Renders a light line network: a dim base structure, bright lit portions with
/// an additive glow, and bright tracer head(s) at the advancing fill front. The
/// front is driven by graph distance-from-source, so it splits at forks.
///
/// Drawn directly in normalized -> canvas space (no homography warp), so it
/// looks identical in the editor preview and the fullscreen projection.
struct LightLineView: View {
    let line: LightLine
    let canvasSize: CGSize
    let time: Double

    @State private var startRef: Double?

    var body: some View {
        Canvas { ctx, size in
            let elapsed = startRef.map { max(0, time - $0) } ?? 0
            LightLineView.draw(line: line, ctx: ctx, size: size, elapsed: elapsed)
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .opacity(line.opacity)
        .allowsHitTesting(false)
        .onAppear { if startRef == nil { startRef = Date().timeIntervalSinceReferenceDate } }
    }

    /// Pure-ish draw routine (static so the verify script can reuse it verbatim).
    static func draw(line: LightLine, ctx: GraphicsContext, size: CGSize, elapsed: Double) {
        guard line.segments.count > 0 else {
            // Still show a lone joint as a faint dot if present.
            for j in line.joints {
                let p = CGPoint(x: j.point.x * size.width, y: j.point.y * size.height)
                ctx.fill(dot(p, 3), with: .color(line.style.color.color.opacity(0.4)))
            }
            return
        }

        let distances = line.distancesFromSource()
        let maxD = distances.values.max() ?? 0
        let cycle = FillCycle(fillDuration: line.style.fillDuration, holdDuration: line.style.holdDuration)
        let front = cycle.frontFraction(elapsed: elapsed) * maxD

        let base = line.style.color.color
        let head = line.style.glowColor.color
        let core = line.style.thickness
        let glowR = line.style.glowRadius

        func pt(_ id: UUID) -> CGPoint? {
            guard let j = line.joint(id) else { return nil }
            return CGPoint(x: j.point.x * size.width, y: j.point.y * size.height)
        }

        // 1) Dim base structure — every segment faint, so geometry is visible.
        var basePath = Path()
        for s in line.segments {
            guard let a = pt(s.a), let b = pt(s.b) else { continue }
            basePath.move(to: a); basePath.addLine(to: b)
        }
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.blendMode = .plusLighter
            layer.stroke(basePath, with: .color(base.opacity(0.18)),
                         style: StrokeStyle(lineWidth: core, lineCap: .round, lineJoin: .round))
        }

        // 2) Lit portions + glow, per segment (lit from the near endpoint out).
        var litPath = Path()
        var heads: [CGPoint] = []
        for s in line.segments {
            let f = line.litFraction(of: s, front: front, distances: distances)
            guard f > 0, let a = pt(s.a), let b = pt(s.b) else { continue }
            // Order endpoints so `p0` is the one nearer the source.
            let dA = distances[s.a] ?? .greatestFiniteMagnitude
            let dB = distances[s.b] ?? .greatestFiniteMagnitude
            let (p0, p1) = dA <= dB ? (a, b) : (b, a)
            let litEnd = CGPoint(x: p0.x + (p1.x - p0.x) * f, y: p0.y + (p1.y - p0.y) * f)
            litPath.move(to: p0); litPath.addLine(to: litEnd)
            if f < 1 { heads.append(litEnd) } // still filling -> tracer head here
        }

        // Wide soft glow, brighter mid glow, crisp core.
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: glowR * 1.4))
            layer.blendMode = .plusLighter
            layer.stroke(litPath, with: .color(base.opacity(0.5)),
                         style: StrokeStyle(lineWidth: core * 6, lineCap: .round, lineJoin: .round))
        }
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: glowR * 0.6))
            layer.blendMode = .plusLighter
            layer.stroke(litPath, with: .color(base.opacity(0.7)),
                         style: StrokeStyle(lineWidth: core * 2.5, lineCap: .round, lineJoin: .round))
        }
        ctx.stroke(litPath, with: .color(base.opacity(0.95)),
                   style: StrokeStyle(lineWidth: core, lineCap: .round, lineJoin: .round))

        // 3) Tracer head glow(s) at the front (one per actively-filling segment).
        for h in heads {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: 6))
                layer.blendMode = .plusLighter
                layer.fill(dot(h, core * 2.5), with: .color(head))
            }
            ctx.fill(dot(h, core * 1.1), with: .color(.white))
        }
    }

    private static func dot(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
}
```

- [ ] **Step 2: Composite lines into the editor canvas**

In `Sources/Lumora/Views/RoomCanvasView.swift`, add the light lines to the ZStack right after the surfaces `ForEach` (inside the `TimelineView`, before the `HandlesOverlay` block):

```swift
                ForEach(store.surfaces) { surface in
                    if surface.isVisible {
                        SurfaceContentView(surface: surface, canvasSize: size, time: t)
                    }
                }

                ForEach(store.lightLines) { line in
                    if line.isVisible {
                        LightLineView(line: line, canvasSize: size, time: t)
                    }
                }
```

- [ ] **Step 3: Composite lines into the projection output**

In `Sources/Lumora/Views/ProjectionView.swift`, add the same block after the surfaces `ForEach` (inside the `ZStack(alignment: .topLeading)`):

```swift
                        ForEach(store.surfaces) { surface in
                            if surface.isVisible {
                                SurfaceContentView(surface: surface, canvasSize: size, time: t)
                            }
                        }

                        ForEach(store.lightLines) { line in
                            if line.isVisible {
                                LightLineView(line: line, canvasSize: size, time: t)
                            }
                        }
```

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 5: Offscreen render verification**

Create `scripts/verify_lightline.swift` (self-contained; hardcodes a fork network and copies the draw math so it links without the app target):

```swift
// Run: swift scripts/verify_lightline.swift
// Renders a fork network at several fill fronts to /tmp PNGs for inspection.
import AppKit
import SwiftUI

struct Seg { let a: Int; let b: Int }
let joints: [CGPoint] = [
    CGPoint(x: 0.10, y: 0.50), // 0 source
    CGPoint(x: 0.45, y: 0.50), // 1 fork
    CGPoint(x: 0.85, y: 0.25), // 2
    CGPoint(x: 0.85, y: 0.75), // 3
]
let segs = [Seg(a: 0, b: 1), Seg(a: 1, b: 2), Seg(a: 1, b: 3)]
let size = CGSize(width: 600, height: 400)

// Distances from source (joint 0) along edges.
func dist() -> [Double] {
    var d = [Double](repeating: .greatestFiniteMagnitude, count: joints.count)
    d[0] = 0
    // Simple relaxation (graph is a tree).
    for _ in 0..<joints.count {
        for s in segs {
            let w = Double(hypot(joints[s.b].x - joints[s.a].x, joints[s.b].y - joints[s.a].y))
            if d[s.a] + w < d[s.b] { d[s.b] = d[s.a] + w }
            if d[s.b] + w < d[s.a] { d[s.a] = d[s.b] + w }
        }
    }
    return d
}
let d = dist()
let maxD = d.max() ?? 1

struct Frame: View {
    let front: Double
    var body: some View {
        Canvas { ctx, sz in
            ctx.fill(Path(CGRect(origin: .zero, size: sz)), with: .color(.black))
            func pt(_ i: Int) -> CGPoint { CGPoint(x: joints[i].x * sz.width, y: joints[i].y * sz.height) }
            var lit = Path(); var heads: [CGPoint] = []
            for s in segs {
                let near = Swift.min(d[s.a], d[s.b])
                let segLen = Double(hypot(joints[s.b].x - joints[s.a].x, joints[s.b].y - joints[s.a].y))
                let f = segLen > 0 ? Swift.min(Swift.max((front - near) / segLen, 0), 1) : 0
                if f <= 0 { continue }
                let (p0, p1) = d[s.a] <= d[s.b] ? (pt(s.a), pt(s.b)) : (pt(s.b), pt(s.a))
                let e = CGPoint(x: p0.x + (p1.x - p0.x) * f, y: p0.y + (p1.y - p0.y) * f)
                lit.move(to: p0); lit.addLine(to: e)
                if f < 1 { heads.append(e) }
            }
            ctx.drawLayer { l in l.addFilter(.blur(radius: 16)); l.blendMode = .plusLighter
                l.stroke(lit, with: .color(.cyan.opacity(0.5)), style: StrokeStyle(lineWidth: 18, lineCap: .round)) }
            ctx.stroke(lit, with: .color(.cyan), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            for h in heads { ctx.fill(Path(ellipseIn: CGRect(x: h.x-4, y: h.y-4, width: 8, height: 8)), with: .color(.white)) }
        }
        .frame(width: size.width, height: size.height)
    }
}

for (i, frac) in [0.0, 0.4, 0.7, 1.0].enumerated() {
    let renderer = ImageRenderer(content: Frame(front: frac * maxD))
    renderer.scale = 2
    if let img = renderer.nsImage,
       let tiff = img.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        let url = URL(fileURLWithPath: "/tmp/lightline_\(i).png")
        try? png.write(to: url)
        print("wrote \(url.path)")
    }
}
```

Run: `swift scripts/verify_lightline.swift`
Then Read `/tmp/lightline_0.png` … `/tmp/lightline_3.png`.
Expected: frame 0 nearly dark; frame 1 the trunk lit with a head partway; frame 2 the pulse **past the fork** with two heads on the two branches; frame 3 the whole fork fully lit, no heads. Confirms the fork-split fill visually.

- [ ] **Step 6: Commit**

```bash
git add Sources/Lumora/Views/LightLineView.swift Sources/Lumora/Views/RoomCanvasView.swift Sources/Lumora/Views/ProjectionView.swift scripts/verify_lightline.swift
git commit -m "$(cat <<'EOF'
Render light line networks with fork-split fill tracer

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Pen tool + editing overlay

The interactive drawing/editing layer: a `.pen` tool in the toolbar, an "Add Line" button, and a `LightLineHandlesOverlay` that drops/snaps joints on click, drags joints, marks the source, and supports right-click set-source / delete.

**Files:**
- Modify: `Sources/Lumora/Views/RoomCanvasView.swift` (show the line overlay; add the pen capture layer)
- Modify: `Sources/Lumora/Views/WorkspaceView.swift` (toolbar: pen tool + Add Line button)
- Create: `Sources/Lumora/Views/LightLineHandlesOverlay.swift`

**Interfaces:**
- Consumes: `ProjectStore.selectedLine`, `addJoint(to:at:connectingTo:)`, `connectJoint(to:existing:from:)`, `setLineSource(_:_:)`, `deleteJoint(_:_:)`, `updateLine(_:_:)`, `EditTool.pen` (Task 2).
- Produces: `struct LightLineHandlesOverlay: View { init(line:canvasSize:) }`.

- [ ] **Step 1: Create the editing overlay**

Create `Sources/Lumora/Views/LightLineHandlesOverlay.swift`:

```swift
import AppKit
import LumoraKit
import SwiftUI

/// Editing affordances for the selected light line: a full-canvas click-capture
/// layer for the pen tool (drop/connect joints), draggable joint handles, and a
/// distinct source marker. Coordinates are in the "canvas" named space.
struct LightLineHandlesOverlay: View {
    @EnvironmentObject var store: ProjectStore
    let line: LightLine
    let canvasSize: CGSize

    /// The last joint placed in the current pen stroke (nil = start a new stroke).
    @State private var lastJointID: UUID?

    private let snapRadius: CGFloat = 14

    var body: some View {
        ZStack {
            if store.tool == .pen {
                penCaptureLayer
            }
            jointHandles
        }
        .allowsHitTesting(true)
    }

    // MARK: Pen — click to drop/connect joints

    private var penCaptureLayer: some View {
        Rectangle()
            .fill(Color.white.opacity(0.001)) // invisible but hit-testable
            .frame(width: canvasSize.width, height: canvasSize.height)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture(count: 2, coordinateSpace: .named("canvas"))
                    .onEnded { _ in lastJointID = nil } // double-click finishes the stroke
                    .exclusively(before:
                        SpatialTapGesture(count: 1, coordinateSpace: .named("canvas"))
                            .onEnded { value in handleClick(at: value.location) }
                    )
            )
            .onExitCommand { lastJointID = nil } // Esc finishes the stroke
    }

    private func handleClick(at location: CGPoint) {
        // Snap onto an existing joint if the click lands near one -> connects/forks.
        if let hit = nearestJoint(to: location) {
            store.connectJoint(to: line.id, existing: hit, from: lastJointID)
            lastJointID = hit
            return
        }
        let nx = min(max(location.x / canvasSize.width, 0), 1)
        let ny = min(max(location.y / canvasSize.height, 0), 1)
        let newID = store.addJoint(to: line.id, at: CGPoint(x: nx, y: ny), connectingTo: lastJointID)
        lastJointID = newID
    }

    private func nearestJoint(to location: CGPoint) -> UUID? {
        var best: (id: UUID, d: CGFloat)?
        for j in line.joints {
            let p = canvasPoint(j.point)
            let d = hypot(p.x - location.x, p.y - location.y)
            if d <= snapRadius, best == nil || d < best!.d { best = (j.id, d) }
        }
        return best?.id
    }

    // MARK: Joint handles — drag to move, right-click for actions

    private var jointHandles: some View {
        ForEach(line.joints) { joint in
            let isSource = joint.id == line.sourceJointID
            Circle()
                .fill(isSource ? Color.green : Color.white)
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 2.5))
                .frame(width: isSource ? 17 : 13, height: isSource ? 17 : 13)
                .position(canvasPoint(joint.point))
                .gesture(
                    DragGesture(coordinateSpace: .named("canvas"))
                        .onChanged { value in
                            let nx = min(max(value.location.x / canvasSize.width, 0), 1)
                            let ny = min(max(value.location.y / canvasSize.height, 0), 1)
                            store.updateLine(line.id) { l in
                                if let i = l.joints.firstIndex(where: { $0.id == joint.id }) {
                                    l.joints[i].point = CGPoint(x: nx, y: ny)
                                }
                            }
                        }
                )
                .contextMenu {
                    Button("Set as Source") { store.setLineSource(line.id, joint.id) }
                    Button("Delete Joint", role: .destructive) {
                        store.deleteJoint(line.id, joint.id)
                        if lastJointID == joint.id { lastJointID = nil }
                    }
                }
                .help(isSource ? "Source joint (pulse starts here)" : "Drag to move; right-click for options")
        }
    }

    private func canvasPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * canvasSize.width, y: p.y * canvasSize.height)
    }
}
```

- [ ] **Step 2: Show the overlay in the canvas**

In `Sources/Lumora/Views/RoomCanvasView.swift`, replace the selected-surface handles block:

```swift
                if let selected = store.selected {
                    HandlesOverlay(surface: selected, canvasSize: size)
                }
```

with a branch that also handles a selected line:

```swift
                if let selectedLine = store.selectedLine {
                    LightLineHandlesOverlay(line: selectedLine, canvasSize: size)
                } else if let selected = store.selected {
                    HandlesOverlay(surface: selected, canvasSize: size)
                }
```

- [ ] **Step 3: Add the pen tool + Add Line button to the toolbar**

In `Sources/Lumora/Views/WorkspaceView.swift`, add the pen case to the pointer `Picker`:

```swift
            Picker("Pointer", selection: $store.tool) {
                Image(systemName: "cursorarrow").tag(EditTool.arrow)
                Image(systemName: "hand.raised.fill").tag(EditTool.hand)
                Image(systemName: "pencil.line").tag(EditTool.pen)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Arrow: warp surface corners. Hand: move a surface. Pen: click to drop/connect light-line joints.")
```

And add an "Add Line" button right after the existing "Add Surface" button:

```swift
            Button {
                store.addSurface()
            } label: {
                Label("Add Surface", systemImage: "plus.square.on.square")
            }

            Button {
                store.addLine()
            } label: {
                Label("Add Line", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }
```

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 5: Manual verification in the app**

Run: `swift run Lumora` (background it plainly; confirm with `pgrep -xl Lumora` — do NOT wrap in a backgrounded subshell, per the launch pitfall).
Confirm by interacting:
1. Click **Add Line** → tool switches to Pen, a "Line 1" is created.
2. Click 3–4 points on the canvas → joints drop and connect with segments; a green **source** marker sits on the first joint; a tracer fills from it.
3. Click near the middle joint, then click a new spot → a **fork** forms; the pulse splits.
4. Double-click → stroke ends; clicking again starts a fresh joint.
5. Drag a joint → it moves and the glow follows.
6. Right-click a joint → **Set as Source** / **Delete Joint** work.
Quit the app when done (`pkill -x Lumora`).

- [ ] **Step 6: Commit**

```bash
git add Sources/Lumora/Views/LightLineHandlesOverlay.swift Sources/Lumora/Views/RoomCanvasView.swift Sources/Lumora/Views/WorkspaceView.swift
git commit -m "$(cat <<'EOF'
Add pen tool and editing overlay for light lines

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Sidebar section + properties panel

Surface the light lines in the sidebar (create/select/rename/delete/visibility) and give the selected line a properties editor (colors, thickness, glow, timing, source status).

**Files:**
- Modify: `Sources/Lumora/Views/SurfaceListView.swift` (add a "Light Lines" section; route selection)
- Modify: `Sources/Lumora/Views/PropertiesPanelView.swift` (branch to a line editor)

**Interfaces:**
- Consumes: `store.lightLines`, `selectLine(_:)`, `selectSurface(_:)`, `deleteLine(_:)`, `updateLine(_:_:)`, `selectedLineBinding()` (Tasks 2–4); `RGBAColor.palette`, `RGBAColor.color`/`init(_:)` bridge.
- Produces: line rows + a `LightLineEditor` in the properties panel.

- [ ] **Step 1: Add the Light Lines sidebar section**

The `List` currently binds selection to `$store.selectedID` (a `Surface.ID?`). Because lines need a separate id space, switch the list to a plain `List` and drive selection through explicit taps that call the store's select helpers.

In `Sources/Lumora/Views/SurfaceListView.swift`, replace the `List(selection:)` body. Change the top of `body`:

```swift
    var body: some View {
        List {
            Section("Surfaces") {
                ForEach(store.surfaces) { surface in
                    row(for: surface)
                        .listRowBackground(surface.id == store.selectedID ? Color.accentColor.opacity(0.15) : nil)
                        .contentShape(Rectangle())
                        .onTapGesture { store.selectSurface(surface.id) }
                        .contextMenu {
                            Button("Rename") { beginEditing(surface.id) }
                            Button("Delete", role: .destructive) { store.delete(surface.id) }
                        }
                }
            }

            Section("Light Lines") {
                ForEach(store.lightLines) { line in
                    lineRow(for: line)
                        .listRowBackground(line.id == store.selectedLineID ? Color.accentColor.opacity(0.15) : nil)
                        .contentShape(Rectangle())
                        .onTapGesture { store.selectLine(line.id) }
                        .contextMenu {
                            Button("Rename") { beginEditingLine(line.id) }
                            Button("Delete", role: .destructive) { store.deleteLine(line.id) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
    }
```

Add line-editing state next to the existing `@State private var editingID`:

```swift
    @State private var editingLineID: LightLine.ID?
```

Add the line row + helpers (place after the existing `row(for:)` and name helpers):

```swift
    @ViewBuilder
    private func lineRow(for line: LightLine) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                if editingLineID == line.id {
                    TextField("Name", text: lineNameBinding(line.id))
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFieldFocused)
                        .onSubmit { editingLineID = nil }
                        .onExitCommand { editingLineID = nil }
                } else {
                    Text(line.name)
                        .onTapGesture(count: 2) { beginEditingLine(line.id) }
                    Text("\(line.joints.count) joint\(line.joints.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                store.updateLine(line.id) { $0.isVisible.toggle() }
            } label: {
                Image(systemName: line.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(line.isVisible ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func beginEditingLine(_ id: LightLine.ID) {
        store.selectLine(id)
        editingLineID = id
        DispatchQueue.main.async { nameFieldFocused = true }
    }

    private func lineNameBinding(_ id: LightLine.ID) -> Binding<String> {
        Binding(
            get: { store.lightLines.first { $0.id == id }?.name ?? "" },
            set: { newValue in store.updateLine(id) { $0.name = newValue } }
        )
    }
```

Note: since surface selection is no longer bound via `List(selection:)`, the existing `beginEditing(_:)` already sets `store.selectedID` — change it to call `store.selectSurface(id)` so the line selection clears:

```swift
    private func beginEditing(_ id: Surface.ID) {
        store.selectSurface(id)
        editingID = id
        DispatchQueue.main.async { nameFieldFocused = true }
    }
```

- [ ] **Step 2: Add the line editor to the properties panel**

In `Sources/Lumora/Views/PropertiesPanelView.swift`, update `body` to prefer a selected line:

```swift
    var body: some View {
        Group {
            if let lineBinding = store.selectedLineBinding() {
                LightLineEditor(line: lineBinding)
            } else if let binding = store.selectedBinding() {
                editor(binding)
            } else {
                ContentUnavailableView(
                    "Nothing Selected",
                    systemImage: "square.dashed",
                    description: Text("Select or add a surface or light line to edit it.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
```

Add the `LightLineEditor` at the end of the file (after `MediaEditor`). It reuses the same swatch + `ColorPicker` pattern as `MediaEditor.colorControls`:

```swift
/// Edits the selected light line: name, colors, thickness, glow, and timing.
private struct LightLineEditor: View {
    @Binding var line: LightLine

    var body: some View {
        Form {
            Section("Light Line") {
                TextField("Name", text: $line.name)
                Toggle("Visible", isOn: $line.isVisible)
                VStack(alignment: .leading) {
                    Text("Opacity \(Int(line.opacity * 100))%").font(.caption)
                    Slider(value: $line.opacity, in: 0...1)
                }
                LabeledContent("Joints", value: "\(line.joints.count)")
                LabeledContent("Source", value: line.sourceJointID == nil ? "None (right-click a joint)" : "Set")
            }

            Section("Appearance") {
                Text("Line Color").font(.caption).foregroundStyle(.secondary)
                colorControls(current: line.style.color) { line.style.color = $0 }
                Text("Glow / Tracer Color").font(.caption).foregroundStyle(.secondary)
                colorControls(current: line.style.glowColor) { line.style.glowColor = $0 }

                VStack(alignment: .leading) {
                    Text("Thickness \(String(format: "%.1f", line.style.thickness))").font(.caption)
                    Slider(value: $line.style.thickness, in: 1...10)
                }
                VStack(alignment: .leading) {
                    Text("Glow Radius \(Int(line.style.glowRadius))").font(.caption)
                    Slider(value: $line.style.glowRadius, in: 2...30)
                }
            }

            Section("Timing") {
                VStack(alignment: .leading) {
                    Text("Fill Duration \(String(format: "%.1f", line.style.fillDuration))s").font(.caption)
                    Slider(value: $line.style.fillDuration, in: 0.5...10)
                }
                VStack(alignment: .leading) {
                    Text("Hold Duration \(String(format: "%.1f", line.style.holdDuration))s").font(.caption)
                    Slider(value: $line.style.holdDuration, in: 0...5)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Preset swatches plus a full color picker (mirrors MediaEditor.colorControls).
    @ViewBuilder
    private func colorControls(current: RGBAColor, apply: @escaping (RGBAColor) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: 8)], spacing: 8) {
            ForEach(RGBAColor.palette, id: \.self) { swatch in
                Circle()
                    .fill(swatch.color)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle().stroke(
                            swatch == current ? Color.primary : Color.black.opacity(0.2),
                            lineWidth: swatch == current ? 2.5 : 1
                        )
                    )
                    .onTapGesture { apply(swatch) }
            }
        }
        ColorPicker(
            "Custom Color",
            selection: Binding(get: { current.color }, set: { apply(RGBAColor($0)) }),
            supportsOpacity: true
        )
    }
}
```

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 4: Manual verification in the app**

Run: `swift run Lumora` (plain background; confirm with `pgrep -xl Lumora`).
Confirm:
1. **Add Line** creates a line that appears under a **Light Lines** sidebar section.
2. Selecting a line shows the **Light Line** properties editor; selecting a surface shows the surface editor (they don't both show; selection is mutually exclusive).
3. Changing line color / glow color / thickness / glow radius updates the render live.
4. Changing fill/hold duration changes the animation cadence.
5. Rename inline (double-click), toggle visibility (eye), and delete (right-click) all work for lines.
6. **⌘S** to a `.lumora`, then **⌘O** back → lines (with joints, source, style) round-trip.
Quit the app when done (`pkill -x Lumora`).

- [ ] **Step 5: Commit**

```bash
git add Sources/Lumora/Views/SurfaceListView.swift Sources/Lumora/Views/PropertiesPanelView.swift
git commit -m "$(cat <<'EOF'
Add light lines to sidebar and properties panel

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Notes on scope & known trade-offs

- **Cycles:** each edge lights from its nearer endpoint only. A closed loop will light from both sides toward the far point — acceptable for the tree/fork shapes this targets (per the spec).
- **One line edited at a time:** the pen tool and overlay operate on the single selected line. Multiple independent networks are separate `LightLine` items.
- **No homography warp** for lines (matches polygon/ellipse convention).
- **Out of scope (YAGNI):** branch-selection/Euler traversal modes, continuous multi-pulse streams, freehand drawing, per-segment styling.
