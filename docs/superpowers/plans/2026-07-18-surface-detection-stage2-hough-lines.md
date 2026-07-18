# Surface Detection — Stage 2: Hough Lines + Merge + Intersections (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From a Canny `EdgeMap` (Stage 1), detect straight line segments (deterministic Hough transform), merge near-duplicate/collinear lines, and compute line intersections as candidate corners.

**Architecture:** New `DetectedLine` model plus stateless enums `HoughLineDetector`, `LineMerger`, `LineIntersector` under `Sources/LumoraKit/SurfaceDetection/CV/`. Deterministic standard Hough (accumulator → peak NMS → segment extraction along each peak) — chosen over randomized probabilistic Hough so tests are reproducible; it still yields line *segments* with real endpoints. Pure Swift, no dependencies. Coordinates are working-image **pixels** (normalization happens later, at Stage 6 integration).

**Tech Stack:** Swift, XCTest, CoreGraphics (only for the opt-in overlay artifact). Target: `LumoraKit`; tests: `LumoraTests`.

## Global Constraints

- **Pure Swift only** — no OpenCV/Vision/ML. CoreGraphics is used solely by the opt-in overlay test.
- **Deterministic** — no randomness; identical input yields identical output (standard accumulator Hough, not randomized PPHT).
- Consumes Stage 1's `EdgeMap` (`width`, `height`, `edges: [Bool]`, row-major, top-left origin) unchanged.
- Angles are line **orientations** in radians normalized to `[0, π)`. Angle difference uses `min(|a-b|, π-|a-b|)`.
- All new types `public`; helpers may be `internal` for `@testable` access.
- `swift test` stays green (currently 110 tests) and grows.

---

## File Structure

- `Sources/LumoraKit/SurfaceDetection/CV/DetectedLine.swift` (create) — `DetectedLine` model + angle helpers.
- `Sources/LumoraKit/SurfaceDetection/CV/HoughLineDetector.swift` (create) — accumulator, peaks, segment extraction.
- `Sources/LumoraKit/SurfaceDetection/CV/LineMerger.swift` (create) — merge near-parallel/close/overlapping lines.
- `Sources/LumoraKit/SurfaceDetection/CV/LineIntersector.swift` (create) — line intersections → candidate corners.
- `Tests/LumoraTests/HoughLineDetectorTests.swift` (create)
- `Tests/LumoraTests/LineMergerTests.swift` (create)
- `Tests/LumoraTests/LineIntersectorTests.swift` (create)

---

### Task 1: `DetectedLine` model + angle helpers

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/DetectedLine.swift`
- Test: `Tests/LumoraTests/HoughLineDetectorTests.swift` (angle-helper tests; grows in later tasks)

**Interfaces:**
- Produces:
  - `struct DetectedLine: Equatable { var p1: CGPoint; var p2: CGPoint; var angle: Double; var length: Double }` — endpoints in working-image pixels; `angle` = orientation in `[0, π)`; `length` = |p2−p1|. Convenience init `DetectedLine(p1:p2:)` computes `angle`/`length`.
  - `enum LineGeometry { static func normalizeAngle(_ a: Double) -> Double; static func angleDifference(_ a: Double, _ b: Double) -> Double }` — `normalizeAngle` folds into `[0, π)`; `angleDifference` returns the acute difference in `[0, π/2]`.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/HoughLineDetectorTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class HoughLineDetectorTests: XCTestCase {
    func testDetectedLineComputesAngleAndLength() {
        let l = DetectedLine(p1: CGPoint(x: 0, y: 0), p2: CGPoint(x: 3, y: 4))
        XCTAssertEqual(l.length, 5, accuracy: 1e-9)
        XCTAssertEqual(l.angle, atan2(4.0, 3.0), accuracy: 1e-9)
    }

    func testNormalizeAngleFoldsIntoZeroPi() {
        XCTAssertEqual(LineGeometry.normalizeAngle(-0.1), Double.pi - 0.1, accuracy: 1e-9)
        XCTAssertEqual(LineGeometry.normalizeAngle(Double.pi + 0.1), 0.1, accuracy: 1e-9)
    }

    func testAngleDifferenceIsAcute() {
        XCTAssertEqual(LineGeometry.angleDifference(0.1, Double.pi - 0.1), 0.2, accuracy: 1e-9)
        XCTAssertEqual(LineGeometry.angleDifference(0, Double.pi / 2), Double.pi / 2, accuracy: 1e-9)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HoughLineDetectorTests`
Expected: FAIL — `DetectedLine` / `LineGeometry` not found.

- [ ] **Step 3: Implement the model + helpers**

Create `Sources/LumoraKit/SurfaceDetection/CV/DetectedLine.swift`:

```swift
import CoreGraphics
import Foundation

/// A straight line segment in working-image pixel coordinates.
public struct DetectedLine: Equatable {
    public var p1: CGPoint
    public var p2: CGPoint
    public var angle: Double   // orientation in [0, π)
    public var length: Double

    public init(p1: CGPoint, p2: CGPoint, angle: Double, length: Double) {
        self.p1 = p1; self.p2 = p2; self.angle = angle; self.length = length
    }

    /// Build from endpoints, deriving `angle` (in [0, π)) and `length`.
    public init(p1: CGPoint, p2: CGPoint) {
        self.p1 = p1
        self.p2 = p2
        let dx = Double(p2.x - p1.x), dy = Double(p2.y - p1.y)
        self.length = (dx * dx + dy * dy).squareRoot()
        self.angle = LineGeometry.normalizeAngle(atan2(dy, dx))
    }
}

public enum LineGeometry {
    /// Fold an angle into [0, π) (a line and its 180°-rotation are the same line).
    public static func normalizeAngle(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: .pi)
        if x < 0 { x += .pi }
        // Guard the boundary: values numerically equal to π fold to 0.
        if x >= .pi { x -= .pi }
        return x
    }

    /// Acute difference between two orientations, in [0, π/2].
    public static func angleDifference(_ a: Double, _ b: Double) -> Double {
        let d = abs(normalizeAngle(a) - normalizeAngle(b))
        return min(d, .pi - d)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HoughLineDetectorTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/DetectedLine.swift \
        Tests/LumoraTests/HoughLineDetectorTests.swift
git commit -m "feat(detect): DetectedLine model + angle helpers

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Hough accumulator

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/HoughLineDetector.swift`
- Test: `Tests/LumoraTests/HoughLineDetectorTests.swift`

**Interfaces:**
- Consumes: `EdgeMap`.
- Produces (internal, for `@testable`):
  - `struct HoughLineDetector.Config` (see below; defaults tuned for ~720px working images).
  - `struct HoughAccumulator { let thetaCount: Int; let rhoCount: Int; let rhoMin: Double; var votes: [Int]; func vote(_ theta: Int, _ rho: Int) -> Int }`.
  - `static func accumulate(_ edges: EdgeMap, config: Config) -> HoughAccumulator` — for each edge pixel and each theta, increments the `(theta, rho)` cell where `rho = x·cosθ + y·sinθ`.

- [ ] **Step 1: Write the failing test**

Add to `HoughLineDetectorTests`:

```swift
    /// EdgeMap with a single horizontal line of edge pixels at row `y0`.
    private func horizontalLineEdges(w: Int, h: Int, y0: Int, x0: Int, x1: Int) -> EdgeMap {
        var e = [Bool](repeating: false, count: w * h)
        for x in x0...x1 { e[y0 * w + x] = true }
        return EdgeMap(width: w, height: h, edges: e)
    }

    func testAccumulatorPeaksAtHorizontalLine() {
        let w = 60, h = 40, y0 = 20
        let edges = horizontalLineEdges(w: w, h: h, y0: y0, x0: 10, x1: 50)
        let cfg = HoughLineDetector.Config()
        let acc = HoughLineDetector.accumulate(edges, config: cfg)

        // Find the max cell.
        var best = -1, bestIdx = 0
        for i in acc.votes.indices where acc.votes[i] > best { best = acc.votes[i]; bestIdx = i }
        let theta = bestIdx / acc.rhoCount
        let rhoIdx = bestIdx % acc.rhoCount
        let thetaDeg = Double(theta) * cfg.thetaStepDeg
        let rho = acc.rhoMin + Double(rhoIdx) * cfg.rhoStep

        // A horizontal line has a vertical normal → θ ≈ 90°, ρ ≈ y0.
        XCTAssertEqual(thetaDeg, 90, accuracy: 2 * cfg.thetaStepDeg)
        XCTAssertEqual(rho, Double(y0), accuracy: 2 * cfg.rhoStep)
        XCTAssertGreaterThan(best, 30, "the whole segment should vote for one cell")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HoughLineDetectorTests/testAccumulatorPeaksAtHorizontalLine`
Expected: FAIL — `HoughLineDetector` not found.

- [ ] **Step 3: Implement Config + accumulator**

Create `Sources/LumoraKit/SurfaceDetection/CV/HoughLineDetector.swift`:

```swift
import CoreGraphics
import Foundation

/// Deterministic Hough line-segment detector: accumulator → peak NMS →
/// segment extraction along each peak. Pure Swift.
public enum HoughLineDetector {
    public struct Config {
        public var thetaStepDeg: Double   // accumulator angular resolution
        public var rhoStep: Double        // accumulator distance resolution (px)
        public var minVotes: Int          // peak must have ≥ this many votes
        public var peakNMSHalfWindow: Int // suppress peaks within this cell radius
        public var maxLines: Int          // cap on peaks processed
        public var lineTolerance: Double  // px distance for an edge point to belong to a line
        public var maxGap: Double         // px gap along a line bridged into one segment
        public var minLength: Double      // discard shorter segments
        public init(thetaStepDeg: Double = 1, rhoStep: Double = 1, minVotes: Int = 20,
                    peakNMSHalfWindow: Int = 8, maxLines: Int = 200,
                    lineTolerance: Double = 1.5, maxGap: Double = 4, minLength: Double = 15) {
            self.thetaStepDeg = thetaStepDeg
            self.rhoStep = rhoStep
            self.minVotes = minVotes
            self.peakNMSHalfWindow = peakNMSHalfWindow
            self.maxLines = maxLines
            self.lineTolerance = lineTolerance
            self.maxGap = maxGap
            self.minLength = minLength
        }
    }

    struct HoughAccumulator {
        let thetaCount: Int
        let rhoCount: Int
        let rhoMin: Double
        var votes: [Int]
        let cosT: [Double]
        let sinT: [Double]
        func vote(_ theta: Int, _ rho: Int) -> Int { votes[theta * rhoCount + rho] }
    }

    static func accumulate(_ edges: EdgeMap, config: Config) -> HoughAccumulator {
        let w = edges.width, h = edges.height
        let thetaCount = Int((180.0 / config.thetaStepDeg).rounded())
        var cosT = [Double](repeating: 0, count: thetaCount)
        var sinT = [Double](repeating: 0, count: thetaCount)
        for t in 0..<thetaCount {
            let rad = Double(t) * config.thetaStepDeg * .pi / 180
            cosT[t] = cos(rad); sinT[t] = sin(rad)
        }
        let diag = (Double(w * w + h * h)).squareRoot()
        let rhoMin = -diag
        let rhoCount = Int((2 * diag / config.rhoStep).rounded()) + 1
        var votes = [Int](repeating: 0, count: thetaCount * rhoCount)

        for y in 0..<h {
            for x in 0..<w where edges.edges[y * w + x] {
                let fx = Double(x), fy = Double(y)
                for t in 0..<thetaCount {
                    let rho = fx * cosT[t] + fy * sinT[t]
                    var ri = Int(((rho - rhoMin) / config.rhoStep).rounded())
                    if ri < 0 { ri = 0 } else if ri >= rhoCount { ri = rhoCount - 1 }
                    votes[t * rhoCount + ri] += 1
                }
            }
        }
        return HoughAccumulator(thetaCount: thetaCount, rhoCount: rhoCount, rhoMin: rhoMin,
                                votes: votes, cosT: cosT, sinT: sinT)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HoughLineDetectorTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/HoughLineDetector.swift \
        Tests/LumoraTests/HoughLineDetectorTests.swift
git commit -m "feat(detect): Hough accumulator

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Peaks + segment extraction → `detect`

**Files:**
- Modify: `Sources/LumoraKit/SurfaceDetection/CV/HoughLineDetector.swift`
- Test: `Tests/LumoraTests/HoughLineDetectorTests.swift`

**Interfaces:**
- Produces: `HoughLineDetector.detect(_ edges: EdgeMap, config: Config = .init()) -> [DetectedLine]` — finds accumulator peaks (≥ `minVotes`, non-max-suppressed within `peakNMSHalfWindow`), then for each peak gathers edge points within `lineTolerance` of the line, sorts them along the line direction, splits into runs at gaps > `maxGap`, and emits runs with `length ≥ minLength`.

- [ ] **Step 1: Write the failing test**

Add to `HoughLineDetectorTests`:

```swift
    func testDetectsSingleHorizontalSegment() {
        let w = 60, h = 40
        let edges = horizontalLineEdges(w: w, h: h, y0: 20, x0: 10, x1: 50)
        let lines = HoughLineDetector.detect(edges)
        XCTAssertEqual(lines.count, 1, "one segment expected")
        let l = lines[0]
        XCTAssertEqual(LineGeometry.angleDifference(l.angle, 0), 0, accuracy: 0.05, "horizontal")
        XCTAssertEqual(l.length, 40, accuracy: 3)
        XCTAssertEqual(min(l.p1.y, l.p2.y), 20, accuracy: 1)
    }

    func testDetectsTwoPerpendicularSegments() {
        let w = 60, h = 60
        var e = [Bool](repeating: false, count: w * h)
        for x in 10...50 { e[30 * w + x] = true } // horizontal
        for y in 10...50 { e[y * w + 30] = true } // vertical
        let lines = HoughLineDetector.detect(EdgeMap(width: w, height: h, edges: e))
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        // Some pair is ~perpendicular.
        var foundPerp = false
        for i in 0..<lines.count { for j in (i + 1)..<lines.count {
            if abs(LineGeometry.angleDifference(lines[i].angle, lines[j].angle) - .pi / 2) < 0.1 { foundPerp = true }
        } }
        XCTAssertTrue(foundPerp, "expected a perpendicular pair")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter HoughLineDetectorTests/testDetectsSingleHorizontalSegment`
Expected: FAIL — `detect` not found.

- [ ] **Step 3: Implement peaks + extraction**

Add to the `HoughLineDetector` enum in `HoughLineDetector.swift`:

```swift
    public static func detect(_ edges: EdgeMap, config: Config = .init()) -> [DetectedLine] {
        let acc = accumulate(edges, config: config)
        let peaks = peaks(acc, config: config)

        // Cache edge point coordinates once.
        let w = edges.width, h = edges.height
        var pts: [(Double, Double)] = []
        for y in 0..<h { for x in 0..<w where edges.edges[y * w + x] { pts.append((Double(x), Double(y))) } }

        var out: [DetectedLine] = []
        for peak in peaks {
            let ct = acc.cosT[peak.theta], st = acc.sinT[peak.theta]
            let rho = acc.rhoMin + Double(peak.rhoIdx) * config.rhoStep
            // Points on this line, projected onto the line direction (-sinθ, cosθ).
            var proj: [(t: Double, x: Double, y: Double)] = []
            for (px, py) in pts {
                let dist = abs(px * ct + py * st - rho)
                if dist <= config.lineTolerance {
                    proj.append((t: -px * st + py * ct, x: px, y: py))
                }
            }
            if proj.count < 2 { continue }
            proj.sort { $0.t < $1.t }
            // Split into runs at gaps > maxGap; emit runs ≥ minLength.
            var runStart = 0
            for i in 1...proj.count {
                let broken = i == proj.count || (proj[i].t - proj[i - 1].t) > config.maxGap
                if broken {
                    let a = proj[runStart], b = proj[i - 1]
                    let line = DetectedLine(p1: CGPoint(x: a.x, y: a.y), p2: CGPoint(x: b.x, y: b.y))
                    if line.length >= config.minLength { out.append(line) }
                    runStart = i
                }
            }
        }
        return out
    }

    struct Peak { let theta: Int; let rhoIdx: Int; let votes: Int }

    /// Local-maxima peaks ≥ minVotes, greedily non-max-suppressed within
    /// `peakNMSHalfWindow` cells (in both θ and ρ), strongest first.
    static func peaks(_ acc: HoughAccumulator, config: Config) -> [Peak] {
        var candidates: [Peak] = []
        for t in 0..<acc.thetaCount {
            for r in 0..<acc.rhoCount {
                let v = acc.votes[t * acc.rhoCount + r]
                if v >= config.minVotes { candidates.append(Peak(theta: t, rhoIdx: r, votes: v)) }
            }
        }
        candidates.sort { $0.votes > $1.votes }
        var accepted: [Peak] = []
        for c in candidates {
            if accepted.count >= config.maxLines { break }
            var suppressed = false
            for a in accepted where abs(a.theta - c.theta) <= config.peakNMSHalfWindow
                && abs(a.rhoIdx - c.rhoIdx) <= config.peakNMSHalfWindow {
                suppressed = true; break
            }
            if !suppressed { accepted.append(c) }
        }
        return accepted
    }
```

Note: `θ` wraps at 180° (θ=0 and θ=179 are nearly the same orientation), so the NMS window does not wrap. In practice a near-vertical line votes around θ≈0 and the duplicate near θ≈179 differs in ρ sign; `LineMerger` (Task 4) cleans up any residual duplicates, so this is acceptable.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HoughLineDetectorTests`
Expected: PASS (6 tests). If `testDetectsSingleHorizontalSegment` finds >1 line (the vote blob split into duplicate peaks), raise `peakNMSHalfWindow` until a clean single line results; if it finds 0, lower `minVotes`/`minLength`.

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/HoughLineDetector.swift \
        Tests/LumoraTests/HoughLineDetectorTests.swift
git commit -m "feat(detect): Hough peaks + segment extraction

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: `LineMerger`

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/LineMerger.swift`
- Test: `Tests/LumoraTests/LineMergerTests.swift`

**Interfaces:**
- Consumes: `DetectedLine`, `LineGeometry`.
- Produces: `enum LineMerger { struct Config { var angleTol: Double; var distTol: Double; var gapTol: Double }; static func merge(_ lines: [DetectedLine], config: Config = .init()) -> [DetectedLine] }` — union-find groups lines that are near-parallel (`angleDifference ≤ angleTol`), close (perpendicular distance ≤ `distTol`), and overlapping-or-near along their shared direction (gap ≤ `gapTol`); each group is refit to one segment spanning the group's extent.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/LineMergerTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class LineMergerTests: XCTestCase {
    func testMergesTwoNearlyCollinearSegments() {
        // Same row, slight vertical jitter, small gap → one line.
        let a = DetectedLine(p1: CGPoint(x: 0, y: 20), p2: CGPoint(x: 25, y: 20))
        let b = DetectedLine(p1: CGPoint(x: 27, y: 21), p2: CGPoint(x: 50, y: 21))
        let merged = LineMerger.merge([a, b])
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].length, 50, accuracy: 3)
    }

    func testKeepsSeparateParallelLinesApart() {
        // Two horizontals far apart vertically → stay two.
        let a = DetectedLine(p1: CGPoint(x: 0, y: 5), p2: CGPoint(x: 40, y: 5))
        let b = DetectedLine(p1: CGPoint(x: 0, y: 35), p2: CGPoint(x: 40, y: 35))
        XCTAssertEqual(LineMerger.merge([a, b]).count, 2)
    }

    func testKeepsPerpendicularLinesApart() {
        let a = DetectedLine(p1: CGPoint(x: 0, y: 20), p2: CGPoint(x: 40, y: 20))
        let b = DetectedLine(p1: CGPoint(x: 20, y: 0), p2: CGPoint(x: 20, y: 40))
        XCTAssertEqual(LineMerger.merge([a, b]).count, 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LineMergerTests`
Expected: FAIL — `LineMerger` not found.

- [ ] **Step 3: Implement `LineMerger`**

Create `Sources/LumoraKit/SurfaceDetection/CV/LineMerger.swift`:

```swift
import CoreGraphics
import Foundation

/// Merge near-parallel, close, overlapping line segments into single lines.
public enum LineMerger {
    public struct Config {
        public var angleTol: Double  // max acute angle difference (radians)
        public var distTol: Double   // max perpendicular distance (px)
        public var gapTol: Double    // max along-direction gap to still merge (px)
        public init(angleTol: Double = 0.17, distTol: Double = 6, gapTol: Double = 12) {
            self.angleTol = angleTol; self.distTol = distTol; self.gapTol = gapTol
        }
    }

    public static func merge(_ lines: [DetectedLine], config: Config = .init()) -> [DetectedLine] {
        let n = lines.count
        if n <= 1 { return lines }
        var parent = Array(0..<n)
        func find(_ i: Int) -> Int { var r = i; while parent[r] != r { parent[r] = parent[parent[r]]; r = parent[r] }; return r }
        func union(_ i: Int, _ j: Int) { parent[find(i)] = find(j) }

        for i in 0..<n { for j in (i + 1)..<n where mergeable(lines[i], lines[j], config) { union(i, j) } }

        var groups: [Int: [DetectedLine]] = [:]
        for i in 0..<n { groups[find(i), default: []].append(lines[i]) }
        return groups.values.map { refit($0) }
    }

    static func mergeable(_ a: DetectedLine, _ b: DetectedLine, _ c: Config) -> Bool {
        if LineGeometry.angleDifference(a.angle, b.angle) > c.angleTol { return false }
        // Perpendicular distance from b's midpoint to a's infinite line.
        let mid = CGPoint(x: (b.p1.x + b.p2.x) / 2, y: (b.p1.y + b.p2.y) / 2)
        if perpendicularDistance(mid, a) > c.distTol { return false }
        // Along-direction overlap/gap using a's direction.
        let dir = direction(a)
        let (a0, a1) = project(a, onto: dir)
        let (b0, b1) = project(b, onto: dir)
        let gap = max(max(a0, b0) - min(a1, b1), 0) // 0 if intervals overlap
        return gap <= c.gapTol
    }

    static func direction(_ l: DetectedLine) -> (Double, Double) {
        let dx = Double(l.p2.x - l.p1.x), dy = Double(l.p2.y - l.p1.y)
        let n = (dx * dx + dy * dy).squareRoot()
        return n > 0 ? (dx / n, dy / n) : (1, 0)
    }

    static func project(_ l: DetectedLine, onto dir: (Double, Double)) -> (Double, Double) {
        let t1 = Double(l.p1.x) * dir.0 + Double(l.p1.y) * dir.1
        let t2 = Double(l.p2.x) * dir.0 + Double(l.p2.y) * dir.1
        return (min(t1, t2), max(t1, t2))
    }

    static func perpendicularDistance(_ p: CGPoint, _ l: DetectedLine) -> Double {
        let dir = direction(l)
        let vx = Double(p.x - l.p1.x), vy = Double(p.y - l.p1.y)
        let along = vx * dir.0 + vy * dir.1
        let cx = vx - along * dir.0, cy = vy - along * dir.1
        return (cx * cx + cy * cy).squareRoot()
    }

    /// Refit a group to one segment: the extent of all endpoints along the
    /// longest member's direction, anchored at that member's p1.
    static func refit(_ group: [DetectedLine]) -> DetectedLine {
        if group.count == 1 { return group[0] }
        let base = group.max { $0.length < $1.length }!
        let dir = direction(base)
        let anchor = base.p1
        var lo = Double.greatestFiniteMagnitude, hi = -Double.greatestFiniteMagnitude
        for l in group {
            for p in [l.p1, l.p2] {
                let t = Double(p.x - anchor.x) * dir.0 + Double(p.y - anchor.y) * dir.1
                lo = min(lo, t); hi = max(hi, t)
            }
        }
        let p1 = CGPoint(x: anchor.x + CGFloat(dir.0 * lo), y: anchor.y + CGFloat(dir.1 * lo))
        let p2 = CGPoint(x: anchor.x + CGFloat(dir.0 * hi), y: anchor.y + CGFloat(dir.1 * hi))
        return DetectedLine(p1: p1, p2: p2)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LineMergerTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/LineMerger.swift \
        Tests/LumoraTests/LineMergerTests.swift
git commit -m "feat(detect): LineMerger (near-parallel/close/overlapping)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: `LineIntersector`

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/LineIntersector.swift`
- Test: `Tests/LumoraTests/LineIntersectorTests.swift`

**Interfaces:**
- Consumes: `DetectedLine`, `LineGeometry`.
- Produces: `enum LineIntersector { struct Config { var minAngle: Double; var margin: Double }; static func intersections(_ lines: [DetectedLine], width: Int, height: Int, config: Config = .init()) -> [CGPoint] }` — pairwise infinite-line intersections; discards pairs whose acute angle < `minAngle` (near-parallel) and points outside `[-margin·w … (1+margin)·w] × [-margin·h … (1+margin)·h]`.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/LineIntersectorTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class LineIntersectorTests: XCTestCase {
    func testHorizontalAndVerticalCrossAtExpectedPoint() {
        let hor = DetectedLine(p1: CGPoint(x: 0, y: 20), p2: CGPoint(x: 40, y: 20))
        let ver = DetectedLine(p1: CGPoint(x: 25, y: 0), p2: CGPoint(x: 25, y: 40))
        let pts = LineIntersector.intersections([hor, ver], width: 40, height: 40)
        XCTAssertEqual(pts.count, 1)
        XCTAssertEqual(Double(pts[0].x), 25, accuracy: 1e-6)
        XCTAssertEqual(Double(pts[0].y), 20, accuracy: 1e-6)
    }

    func testParallelLinesProduceNoIntersection() {
        let a = DetectedLine(p1: CGPoint(x: 0, y: 10), p2: CGPoint(x: 40, y: 10))
        let b = DetectedLine(p1: CGPoint(x: 0, y: 30), p2: CGPoint(x: 40, y: 30))
        XCTAssertTrue(LineIntersector.intersections([a, b], width: 40, height: 40).isEmpty)
    }

    func testOutOfFrameIntersectionDiscarded() {
        // Two nearly-horizontal lines meeting far to the right, outside the frame.
        let a = DetectedLine(p1: CGPoint(x: 0, y: 10), p2: CGPoint(x: 40, y: 12))
        let b = DetectedLine(p1: CGPoint(x: 0, y: 30), p2: CGPoint(x: 40, y: 28))
        XCTAssertTrue(LineIntersector.intersections([a, b], width: 40, height: 40).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter LineIntersectorTests`
Expected: FAIL — `LineIntersector` not found.

- [ ] **Step 3: Implement `LineIntersector`**

Create `Sources/LumoraKit/SurfaceDetection/CV/LineIntersector.swift`:

```swift
import CoreGraphics
import Foundation

/// Candidate corners from pairwise line intersections.
public enum LineIntersector {
    public struct Config {
        public var minAngle: Double // discard near-parallel pairs (radians)
        public var margin: Double   // allow intersections slightly outside the frame
        public init(minAngle: Double = 0.35, margin: Double = 0.05) {
            self.minAngle = minAngle; self.margin = margin
        }
    }

    public static func intersections(_ lines: [DetectedLine], width: Int, height: Int,
                                     config: Config = .init()) -> [CGPoint] {
        let w = Double(width), h = Double(height)
        let minX = -config.margin * w, maxX = (1 + config.margin) * w
        let minY = -config.margin * h, maxY = (1 + config.margin) * h
        var out: [CGPoint] = []
        for i in 0..<lines.count {
            for j in (i + 1)..<lines.count {
                if LineGeometry.angleDifference(lines[i].angle, lines[j].angle) < config.minAngle { continue }
                guard let p = intersect(lines[i], lines[j]) else { continue }
                let px = Double(p.x), py = Double(p.y)
                if px < minX || px > maxX || py < minY || py > maxY { continue }
                out.append(p)
            }
        }
        return out
    }

    /// Infinite-line intersection from two segments' endpoints (nil if parallel).
    static func intersect(_ a: DetectedLine, _ b: DetectedLine) -> CGPoint? {
        let x1 = Double(a.p1.x), y1 = Double(a.p1.y), x2 = Double(a.p2.x), y2 = Double(a.p2.y)
        let x3 = Double(b.p1.x), y3 = Double(b.p1.y), x4 = Double(b.p2.x), y4 = Double(b.p2.y)
        let denom = (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
        if abs(denom) < 1e-9 { return nil }
        let pre = x1 * y2 - y1 * x2, post = x3 * y4 - y3 * x4
        let px = (pre * (x3 - x4) - (x1 - x2) * post) / denom
        let py = (pre * (y3 - y4) - (y1 - y2) * post) / denom
        return CGPoint(x: px, y: py)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LineIntersectorTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS — ~122 tests (110 + 12 new), 0 failures.

- [ ] **Step 6: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/LineIntersector.swift \
        Tests/LumoraTests/LineIntersectorTests.swift
git commit -m "feat(detect): LineIntersector (candidate corners)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Eyeball overlay — lines + intersections on the synthetic room

**Files:**
- Test: `Tests/LumoraTests/HoughLineDetectorTests.swift` (add one opt-in artifact test)

**Interfaces:**
- Consumes: `ImagePreprocessor.grayscale`, `CannyEdgeDetector.detect`, `HoughLineDetector.detect`, `LineMerger.merge`, `LineIntersector.intersections`.
- Produces: no library symbols — writes a PNG for human review.

- [ ] **Step 1: Add the artifact test**

Add to `HoughLineDetectorTests` (add `import ImageIO` and `import UniformTypeIdentifiers` at the top of the file):

```swift
    func testWritesHoughOverlayArtifactWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["HOUGH_OVERLAY"] == "1" else {
            throw XCTSkip("set HOUGH_OVERLAY=1 to write the overlay artifact")
        }
        let w = 320, h = 240
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.82, green: 0.80, blue: 0.76, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.55, green: 0.52, blue: 0.48, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h / 3))
        ctx.setFillColor(CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)); ctx.fill(CGRect(x: 110, y: 120, width: 110, height: 70))
        let room = ctx.makeImage()!

        let gray = ImagePreprocessor.grayscale(from: room, maxDimension: 320)
        let edges = CannyEdgeDetector.detect(gray)
        let lines = LineMerger.merge(HoughLineDetector.detect(edges))
        let corners = LineIntersector.intersections(lines, width: gray.width, height: gray.height)

        // Draw the room dimmed, then lines (green) and intersections (red).
        let out = CGContext(data: nil, width: gray.width, height: gray.height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        out.draw(room, in: CGRect(x: 0, y: 0, width: gray.width, height: gray.height))
        out.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.45)); out.fill(CGRect(x: 0, y: 0, width: gray.width, height: gray.height))
        out.setStrokeColor(CGColor(red: 0.2, green: 1, blue: 0.3, alpha: 1)); out.setLineWidth(1.5)
        // CGContext is y-up; our pixel coords are y-down, so flip y when drawing.
        let H = CGFloat(gray.height)
        for l in lines {
            out.move(to: CGPoint(x: l.p1.x, y: H - l.p1.y))
            out.addLine(to: CGPoint(x: l.p2.x, y: H - l.p2.y))
        }
        out.strokePath()
        out.setFillColor(CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 1))
        for c in corners { out.fillEllipse(in: CGRect(x: c.x - 3, y: H - c.y - 3, width: 6, height: 6)) }

        let img = out.makeImage()!
        let dir = ProcessInfo.processInfo.environment["HOUGH_OVERLAY_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent("hough_overlay.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, img, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        print("HOUGH_OVERLAY written to: \(url.path) — lines: \(lines.count), corners: \(corners.count)")
    }
```

- [ ] **Step 2: Run the artifact test**

Run: `HOUGH_OVERLAY=1 swift test --filter HoughLineDetectorTests/testWritesHoughOverlayArtifactWhenRequested`
Expected: PASS; prints the PNG path and line/corner counts.

- [ ] **Step 3: Eyeball the artifact**

Open/Read the printed `hough_overlay.png`. Confirm: green lines trace the screen rectangle's 4 sides and the wall/floor seam; red dots sit at the rectangle's 4 corners (and the seam/rectangle crossings). Tune `HoughLineDetector.Config`/`LineMerger.Config` if sides are missing (lower `minVotes`/`minLength`) or duplicated (raise `peakNMSHalfWindow` or `LineMerger` tolerances).

- [ ] **Step 4: Confirm default `swift test` still skips it**

Run: `swift test --filter HoughLineDetectorTests`
Expected: the artifact test reports **skipped**; the others PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/LumoraTests/HoughLineDetectorTests.swift
git commit -m "test(detect): Hough lines + intersections overlay artifact (opt-in)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (Stage 2 slice of the design doc):**
- Line detection (Hough), classify by angle → Tasks 2–3 (`DetectedLine.angle`). ✅
- Ignore short lines → Task 3 (`minLength`). ✅
- Merge similar lines (parallel/close/overlapping) → Task 4. ✅
- Find intersections → candidate corners; discard invalid/impossible → Task 5 (near-parallel + out-of-frame discard). ✅
- Deterministic, pure Swift → all tasks. ✅
- Eyeball overlay verification → Task 6. ✅

**Placeholder scan:** No TBD/TODO; every code step is complete; notes are concrete tuning/import instructions. ✅

**Type consistency:** `DetectedLine`/`LineGeometry` (Task 1) consumed unchanged by Hough (2–3), `LineMerger` (4), `LineIntersector` (5), overlay (6). `EdgeMap` (Stage 1) consumed by `accumulate`/`detect`. `HoughLineDetector.detect → [DetectedLine]` fed into `LineMerger.merge → [DetectedLine]` fed into `LineIntersector.intersections → [CGPoint]`. Signatures match across tasks. ✅

**Scope check:** Lines + merge + intersections only. Contours, polygons, validation, ranking, and integration are later stages. ✅
```

