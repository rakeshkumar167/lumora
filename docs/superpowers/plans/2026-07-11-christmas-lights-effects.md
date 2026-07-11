# Christmas Lights Effect Set Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Christmas Lights" effect category with four effects — a decorated tree with twinkling lights (confined to the tree) and three sagging string-light variations (chasing, multi-colored, twinkling).

**Architecture:** Correctness-critical strand geometry + the festive palette live in `LumoraKit` (pure, unit-tested). The app renders all four in a new `christmasEffects` group in `EffectView` (`SurfaceContentView.swift`), driven by the global `time`, using the established `Canvas` + blur/plusLighter glow pattern. The tree image is bundled and its light points are masked to the tree via luminance sampling.

**Tech Stack:** Swift 5.9, SwiftUI (`Canvas`, `ImageRenderer`), AppKit (`NSImage`, `NSBitmapImageRep`), XCTest. Swift Package: `swift build`, `swift test`, `swift run Lumora`.

## Global Constraints

- Platform: macOS 14+. `LumoraKit` is **UI-free**: import only `Foundation` / `CoreGraphics`. No SwiftUI/AppKit in LumoraKit.
- Effects follow the existing `EffectKind` + `EffectView` pattern: a `Canvas`/gradient driven by `time`, warpable.
- Glow recipe: `ctx.drawLayer { $0.addFilter(.blur(radius:)); $0.blendMode = .plusLighter; … }`.
- `time` is a **global monotonic clock** (never reset per view). These effects are stateless/looping (no fill-from-zero), so they use `time` directly with per-element phase offsets — no `.onAppear` start capture needed.
- All four effects use a **fixed festive palette**; `usesColor` and `usesAccent` are `false` for all four.
- Festive palette (exact values): red `(0.85, 0.11, 0.14)`, green `(0.11, 0.58, 0.24)`, gold `(0.95, 0.76, 0.22)`, blue `(0.16, 0.42, 0.90)`, warmWhite `(1.0, 0.93, 0.80)`.
- Tree glints must appear **only on the tree**, never the dark background.
- Commit after each task. Commit messages end with:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`

---

### Task 1: EffectKind cases + festive palette + strand geometry (LumoraKit, TDD)

Add the four effect kinds, the `.christmas` category, and the pure `ChristmasLights` geometry/palette. Unit-tested.

**Files:**
- Modify: `Sources/LumoraKit/EffectKind.swift`
- Create: `Sources/LumoraKit/ChristmasLights.swift`
- Create: `Tests/LumoraTests/ChristmasLightsTests.swift`

**Interfaces:**
- Consumes: `RGBAColor` (LumoraKit).
- Produces (used by the app task):
  - `EffectKind.christmasTree`, `.chasingLights`, `.multiColorLights`, `.twinklingLights`
  - `EffectCategory.christmas`
  - `enum ChristmasLights { static let palette: [RGBAColor]; struct Strand { let bulbs: [CGPoint] }; static func strands(in size: CGSize) -> [Strand] }`

- [ ] **Step 1: Write the failing tests**

Create `Tests/LumoraTests/ChristmasLightsTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import LumoraKit

final class ChristmasLightsTests: XCTestCase {
    func testPaletteHasFiveDistinctColors() {
        let p = ChristmasLights.palette
        XCTAssertEqual(p.count, 5)
        XCTAssertEqual(Set(p).count, 5)
    }

    func testStrandCountScalesWithHeightMinTwo() {
        let few = ChristmasLights.strands(in: CGSize(width: 400, height: 120))
        let many = ChristmasLights.strands(in: CGSize(width: 400, height: 900))
        XCTAssertGreaterThanOrEqual(few.count, 2)
        XCTAssertGreaterThan(many.count, few.count)
    }

    func testBulbCountScalesWithWidthMinThree() {
        let narrow = ChristmasLights.strands(in: CGSize(width: 120, height: 400))
        let wide = ChristmasLights.strands(in: CGSize(width: 1200, height: 400))
        XCTAssertGreaterThanOrEqual(narrow[0].bulbs.count, 3)
        XCTAssertGreaterThan(wide[0].bulbs.count, narrow[0].bulbs.count)
    }

    func testStrandSagsDownwardEndsPinned() {
        let size = CGSize(width: 600, height: 400)
        let strand = ChristmasLights.strands(in: size)[0]
        let first = strand.bulbs.first!, last = strand.bulbs.last!, mid = strand.bulbs[strand.bulbs.count / 2]
        // Ends share the pin height; the middle dips below (larger y = lower).
        XCTAssertEqual(first.y, last.y, accuracy: 1.0)
        XCTAssertGreaterThan(mid.y, first.y + 1)
    }

    func testAllBulbsInsideBounds() {
        let size = CGSize(width: 600, height: 400)
        for strand in ChristmasLights.strands(in: size) {
            for b in strand.bulbs {
                XCTAssertGreaterThanOrEqual(b.x, 0); XCTAssertLessThanOrEqual(b.x, size.width)
                XCTAssertGreaterThanOrEqual(b.y, 0); XCTAssertLessThanOrEqual(b.y, size.height)
            }
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ChristmasLightsTests`
Expected: FAIL to compile — `cannot find 'ChristmasLights' in scope`.

- [ ] **Step 3: Create `ChristmasLights.swift`**

```swift
import CoreGraphics
import Foundation

/// Pure geometry + palette for the Christmas string-light effects. Size-driven,
/// no UI. Bulb positions are returned in the given pixel space (top-left origin,
/// larger y is lower). Deterministic — any twinkle randomness lives in the
/// renderer as a per-bulb phase, so geometry is stable frame-to-frame.
public enum ChristmasLights {
    /// Classic festive palette: red, green, gold, blue, warm-white.
    public static let palette: [RGBAColor] = [
        RGBAColor(r: 0.85, g: 0.11, b: 0.14),
        RGBAColor(r: 0.11, g: 0.58, b: 0.24),
        RGBAColor(r: 0.95, g: 0.76, b: 0.22),
        RGBAColor(r: 0.16, g: 0.42, b: 0.90),
        RGBAColor(r: 1.00, g: 0.93, b: 0.80),
    ]

    /// One hung strand: bulb centers left→right along a downward-sagging arc.
    public struct Strand {
        public let bulbs: [CGPoint]
        public init(bulbs: [CGPoint]) { self.bulbs = bulbs }
    }

    private static let rowSpacing: CGFloat = 90
    private static let bulbSpacing: CGFloat = 55
    private static let insetFraction: CGFloat = 0.06

    /// Horizontal sagging strands stacked down the surface. Count scales with
    /// height (min 2); bulbs-per-strand scales with width (min 3).
    public static func strands(in size: CGSize) -> [Strand] {
        guard size.width > 0, size.height > 0 else { return [] }
        let strandCount = max(2, Int((size.height / rowSpacing).rounded()))
        let bulbCount = max(3, Int((size.width / bulbSpacing).rounded()))
        let sag = 0.35 * rowSpacing
        let inset = size.width * insetFraction
        let left = inset, right = size.width - inset

        var result: [Strand] = []
        for s in 0..<strandCount {
            // Base (pin) height for this strand, evenly distributed.
            let y0 = size.height * (CGFloat(s) + 0.5) / CGFloat(strandCount)
            var bulbs: [CGPoint] = []
            for i in 0..<bulbCount {
                let t = CGFloat(i) / CGFloat(bulbCount - 1)      // 0…1
                let x = left + (right - left) * t
                let y = y0 + sag * 4 * t * (1 - t)               // 0 at ends, max mid
                bulbs.append(CGPoint(x: x, y: y))
            }
            result.append(Strand(bulbs: bulbs))
        }
        return result
    }
}
```

- [ ] **Step 4: Add the EffectKind cases + category**

In `Sources/LumoraKit/EffectKind.swift`:

- Add cases after `case digitalClock`:
```swift
    case christmasTree
    case chasingLights
    case multiColorLights
    case twinklingLights
```
- `usesColor`: add these four to the `false`-returning switch case list (the first `case` group that returns `false`):
```swift
        case .colorWash, .rainbowSweep, .colorBars, .starfieldWarp, .aurora, .tvStatic, .prismFalls,
             .voronoi, .vectorGrid, .livingTexture, .fire, .bubbles, .fireworks,
             .christmasTree, .chasingLights, .multiColorLights, .twinklingLights:
            return false
```
- `usesAccent`: they must return `false`. They are NOT in the `true` list, and the `default` returns `false`, so no change is needed — but confirm none are added to the `usesAccent` `true` list.
- `displayName`: add
```swift
        case .christmasTree: return "Christmas Tree"
        case .chasingLights: return "Chasing Lights"
        case .multiColorLights: return "Multi-Colored Lights"
        case .twinklingLights: return "Twinkling Lights"
```
- `category`: add a new group before the closing brace of the switch:
```swift
        case .christmasTree, .chasingLights, .multiColorLights, .twinklingLights:
            return .christmas
```
- Add `.christmas` to the `EffectCategory` enum (after `.clocks`):
```swift
    case christmas
```
- Add its `displayName`:
```swift
        case .christmas: return "Christmas Lights"
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ChristmasLightsTests`
Expected: PASS (5 tests). Then `swift build` to confirm the enum edits compile.

- [ ] **Step 6: Commit**

```bash
git add Sources/LumoraKit/EffectKind.swift Sources/LumoraKit/ChristmasLights.swift Tests/LumoraTests/ChristmasLightsTests.swift
git commit -m "$(cat <<'EOF'
Add Christmas effect kinds, festive palette, and strand geometry

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Bundle the tree image + on-tree light mask (app)

Move the tree image into the resource bundle and build the luminance mask that confines glints to the tree.

**Files:**
- Move: `Sources/Effects-data/christmas-tree.png` → `Sources/Lumora/Resources/christmas-tree.png`
- Create: `Sources/Lumora/Views/ChristmasTreeAsset.swift`

**Interfaces:**
- Consumes: `Bundle.module`.
- Produces:
  - `enum ChristmasTreeAsset { static let image: NSImage?; static let litPoints: [CGPoint] }`
  - `litPoints` are normalized (0…1, top-left origin) on-tree bright points.

- [ ] **Step 1: Move the image into Resources**

```bash
git mv Sources/Effects-data/christmas-tree.png Sources/Lumora/Resources/christmas-tree.png
rmdir Sources/Effects-data 2>/dev/null || true
```
(If `git mv` fails because the file is only staged/untracked, use `mkdir -p Sources/Lumora/Resources && mv Sources/Effects-data/christmas-tree.png Sources/Lumora/Resources/` then `git add`.)

- [ ] **Step 2: Create the asset + mask helper**

Create `Sources/Lumora/Views/ChristmasTreeAsset.swift`:

```swift
import AppKit
import CoreGraphics
import Foundation

/// The bundled Christmas-tree image and the set of normalized on-tree points
/// where twinkle glints may appear. The image sits on a dark vignetted
/// background, so a luminance threshold on a downsampled grid cleanly excludes
/// the background — glints only spawn on the tree. Computed once, lazily.
enum ChristmasTreeAsset {
    static let image: NSImage? = {
        guard let url = Bundle.module.url(forResource: "christmas-tree", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    /// Normalized (0…1, top-left) bright on-tree points, sampled on a grid.
    static let litPoints: [CGPoint] = computeLitPoints()

    private static func computeLitPoints() -> [CGPoint] {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return fallbackTrianglePoints()
        }
        let cols = 48, rows = 72
        // Draw the image into a small RGBA buffer we can read.
        let bytesPerRow = cols * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * rows)
        guard let ctx = CGContext(data: &data, width: cols, height: rows, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return fallbackTrianglePoints()
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cols, height: rows))

        var points: [CGPoint] = []
        for row in 0..<rows {
            for col in 0..<cols {
                let i = row * bytesPerRow + col * 4
                let r = Double(data[i]), g = Double(data[i + 1]), b = Double(data[i + 2])
                let lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
                // Bright foliage / ornaments / lights pass; dark vignette fails.
                if lum > 0.34 {
                    // CGContext origin is bottom-left; flip row to top-left.
                    let nx = (Double(col) + 0.5) / Double(cols)
                    let ny = (Double(rows - 1 - row) + 0.5) / Double(rows)
                    points.append(CGPoint(x: nx, y: ny))
                }
            }
        }
        return points.isEmpty ? fallbackTrianglePoints() : points
    }

    /// A triangular tree-shaped fallback if the image can't be read.
    private static func fallbackTrianglePoints() -> [CGPoint] {
        var pts: [CGPoint] = []
        let apexX = 0.5, top = 0.08, bottom = 0.82
        for ny in stride(from: top, through: bottom, by: 0.03) {
            let frac = (ny - top) / (bottom - top)          // 0 at apex → 1 at base
            let halfWidth = 0.40 * frac
            for nx in stride(from: apexX - halfWidth, through: apexX + halfWidth, by: 0.05) {
                pts.append(CGPoint(x: nx, y: ny))
            }
        }
        return pts
    }
}
```

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 4: Offscreen verification of the mask**

Create `scripts/verify_tree_mask.swift` — loads the bundled image path directly, replicates the luminance sampling, and renders the image with the kept points overlaid as small dots, so the mask visibly hugs the tree.

```swift
// Run: swift scripts/verify_tree_mask.swift
import AppKit

let path = "Sources/Lumora/Resources/christmas-tree.png"
guard let img = NSImage(contentsOfFile: path),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("no image"); exit(1) }
let cols = 48, rows = 72, bpr = cols * 4
var data = [UInt8](repeating: 0, count: bpr * rows)
let ctx = CGContext(data: &data, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: bpr,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cols, height: rows))
var pts: [CGPoint] = []
for row in 0..<rows { for col in 0..<cols {
    let i = row*bpr + col*4
    let lum = (0.299*Double(data[i]) + 0.587*Double(data[i+1]) + 0.114*Double(data[i+2]))/255.0
    if lum > 0.34 { pts.append(CGPoint(x: (Double(col)+0.5)/Double(cols), y: (Double(rows-1-row)+0.5)/Double(rows))) }
}}
print("kept \(pts.count) / \(cols*rows) cells")

let W = cg.width, H = cg.height
let bmp = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let g = NSGraphicsContext(bitmapImageRep: bmp)!.cgContext
g.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
g.setFillColor(NSColor.cyan.cgColor)
for p in pts { // p is top-left normalized; device is bottom-up
    let x = p.x*Double(W), y = Double(H)*(1-p.y)
    g.fillEllipse(in: CGRect(x: x-3, y: y-3, width: 6, height: 6))
}
if let png = bmp.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: "/tmp/tree_mask.png")); print("wrote /tmp/tree_mask.png")
}
```

Run: `swift scripts/verify_tree_mask.swift`, then Read `/tmp/tree_mask.png`.
Expected: cyan dots cover the tree (foliage/ornaments) and are absent from the dark background corners. If dots bleed into the background, raise the `0.34` threshold; if the tree is sparse, lower it. Record the final threshold in the report.

- [ ] **Step 5: Commit**

```bash
git add Sources/Lumora/Resources/christmas-tree.png Sources/Lumora/Views/ChristmasTreeAsset.swift scripts/verify_tree_mask.swift
git add -u Sources/Effects-data 2>/dev/null || true
git commit -m "$(cat <<'EOF'
Bundle Christmas tree image and build on-tree light mask

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Render the four effects (app)

Add the `christmasEffects` renderer group and dispatch the four kinds to it.

**Files:**
- Modify: `Sources/Lumora/Views/SurfaceContentView.swift`
- Verify: `scripts/verify_christmas.swift` (create; offscreen render of all four)

**Interfaces:**
- Consumes: `ChristmasLights.strands(in:)`, `ChristmasLights.palette` (Task 1); `ChristmasTreeAsset.image`, `.litPoints` (Task 2).
- Produces: rendering only (no new public API).

- [ ] **Step 1: Dispatch the four kinds**

In `EffectView.body`'s outer `switch kind`, add a case routing the four Christmas kinds to a new group:

```swift
        case .christmasTree, .chasingLights, .multiColorLights, .twinklingLights:
            christmasEffects
```

- [ ] **Step 2: Implement `christmasEffects`**

Add this `@ViewBuilder` var alongside the other effect groups in `EffectView`. It reads `time`; colors come from `ChristmasLights.palette` (ignores `color`/`accent`).

```swift
    @ViewBuilder private var christmasEffects: some View {
        switch kind {
        case .christmasTree:
            Canvas { ctx, size in
                // Dark backing so unlit margins read as night, not white.
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(red: 0.02, green: 0.03, blue: 0.02)))
                // Aspect-fit the tree image centered.
                if let img = ChristmasTreeAsset.image {
                    let resolved = ctx.resolve(Image(nsImage: img))
                    let is = img.size
                    let scale = min(size.width / is.width, size.height / is.height)
                    let w = is.width * scale, h = is.height * scale
                    let ox = (size.width - w) / 2, oy = (size.height - h) / 2
                    ctx.draw(resolved, in: CGRect(x: ox, y: oy, width: w, height: h))
                    drawTreeGlints(ctx, imageRect: CGRect(x: ox, y: oy, width: w, height: h))
                } else {
                    // Fallback: glints over the whole surface region.
                    drawTreeGlints(ctx, imageRect: CGRect(origin: .zero, size: size))
                }
            }

        case .chasingLights, .multiColorLights, .twinklingLights:
            Canvas { ctx, size in
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(red: 0.03, green: 0.04, blue: 0.07)))
                let strands = ChristmasLights.strands(in: size)
                for strand in strands {
                    // Wire through the bulbs.
                    var wire = Path()
                    wire.addLines(strand.bulbs)
                    ctx.stroke(wire, with: .color(Color.white.opacity(0.12)), lineWidth: 1.5)
                    for (i, b) in strand.bulbs.enumerated() {
                        let (col, bright) = bulbState(index: i, count: strand.bulbs.count)
                        drawBulb(ctx, at: b, color: col, brightness: bright)
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    /// Twinkle glints on the tree: soft glowing dots that pulse on their own
    /// phase, only at the precomputed on-tree points.
    private func drawTreeGlints(_ ctx: GraphicsContext, imageRect: CGRect) {
        let points = ChristmasTreeAsset.litPoints
        guard !points.isEmpty else { return }
        // A subset twinkles at once; step through deterministically by index.
        let palette = ChristmasLights.palette
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 3))
            layer.blendMode = .plusLighter
            for (i, p) in points.enumerated() {
                // Per-point phase → staggered pulsing.
                let phase = Double(i) * 0.7
                let pulse = 0.5 + 0.5 * sin(time * 2.2 + phase)
                guard pulse > 0.55 else { continue }          // only lit ones drawn
                let intensity = (pulse - 0.55) / 0.45
                // Warm-white/gold dominate; occasional colored sparkle.
                let col: Color = (i % 5 == 0) ? palette[i % palette.count].color
                                              : (i % 2 == 0 ? palette[4].color : palette[2].color)
                let c = CGPoint(x: imageRect.minX + p.x * imageRect.width,
                                y: imageRect.minY + p.y * imageRect.height)
                let r = 2.0 + 4.0 * intensity
                layer.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(col.opacity(0.35 + 0.65 * intensity)))
            }
        }
    }

    /// Per-bulb color + brightness for the three string variations.
    private func bulbState(index i: Int, count: Int) -> (Color, Double) {
        let palette = ChristmasLights.palette
        switch kind {
        case .chasingLights:
            // A bright band runs along the strand; color cycles slowly.
            let pos = Double(i) / Double(max(count - 1, 1))
            let head = (time * 0.5).truncatingRemainder(dividingBy: 1)
            let d = abs(pos - head)
            let wrapped = min(d, 1 - d)
            let bright = max(0, 1 - wrapped * 6)              // narrow lit band
            let col = palette[(i + Int(time)) % palette.count].color
            return (col, 0.15 + 0.85 * bright)
        case .multiColorLights:
            // Steady alternating palette with a gentle per-bulb shimmer.
            let col = palette[i % palette.count].color
            let shimmer = 0.75 + 0.25 * sin(time * 1.5 + Double(i) * 0.9)
            return (col, shimmer)
        case .twinklingLights:
            // Smooth pseudo-random fade per bulb.
            let seed = Double((i * 2654435761) % 1000) / 1000.0
            let tw = 0.5 + 0.5 * sin(time * 1.8 + seed * 6.283)
            let col = palette[i % palette.count].color
            return (col, 0.1 + 0.9 * pow(tw, 2))
        default:
            return (palette[i % palette.count].color, 1)
        }
    }

    /// A glowing bulb: bright core + soft plusLighter halo.
    private func drawBulb(_ ctx: GraphicsContext, at p: CGPoint, color: Color, brightness: Double) {
        let coreR = 4.0
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 6))
            layer.blendMode = .plusLighter
            let haloR = coreR + 6 * brightness
            layer.fill(Path(ellipseIn: CGRect(x: p.x - haloR, y: p.y - haloR, width: 2 * haloR, height: 2 * haloR)),
                       with: .color(color.opacity(0.5 * brightness)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - coreR, y: p.y - coreR, width: 2 * coreR, height: 2 * coreR)),
                 with: .color(color.opacity(0.4 + 0.6 * brightness)))
    }
```

> Note: `time`, `kind`, `color`, `accent` are `EffectView` members already in scope for these methods. If the compiler flags the private methods being outside the struct, keep them inside the `EffectView` struct body (same scope as the other `@ViewBuilder` groups).

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 4: Offscreen render all four**

Create `scripts/verify_christmas.swift` that renders each of the four effects at two time values (t=0.0 and t=1.3) into a montage PNG, so the tree glints and the three string variations are visible and clearly animate. Reuse the app types is not possible from a script, so replicate the render minimally OR — simpler and authoritative — drive the real views via `ImageRenderer` in a tiny SwiftUI harness that imports the effect through the app is not linkable; instead render a faithful standalone copy of the strand geometry + bulbs and the tree image with glints.

```swift
// Run: swift scripts/verify_christmas.swift
import AppKit
import SwiftUI

// Standalone faithful copy for visual sanity (mirrors ChristmasLights + renderer).
let palette: [Color] = [
    Color(red: 0.85, green: 0.11, blue: 0.14), Color(red: 0.11, green: 0.58, blue: 0.24),
    Color(red: 0.95, green: 0.76, blue: 0.22), Color(red: 0.16, green: 0.42, blue: 0.90),
    Color(red: 1.0, green: 0.93, blue: 0.80),
]
func strands(_ size: CGSize) -> [[CGPoint]] {
    let rs: CGFloat = 90, bs: CGFloat = 55
    let sc = max(2, Int((size.height/rs).rounded())), bc = max(3, Int((size.width/bs).rounded()))
    let sag = 0.35*rs, inset = size.width*0.06, left = inset, right = size.width-inset
    return (0..<sc).map { s in
        let y0 = size.height*(CGFloat(s)+0.5)/CGFloat(sc)
        return (0..<bc).map { i -> CGPoint in
            let t = CGFloat(i)/CGFloat(bc-1)
            return CGPoint(x: left+(right-left)*t, y: y0+sag*4*t*(1-t))
        }
    }
}

struct StringView: View {
    let time: Double; let mode: Int  // 0 chase, 1 multi, 2 twinkle
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red:0.03,green:0.04,blue:0.07)))
            for strand in strands(size) {
                var wire = Path(); wire.addLines(strand)
                ctx.stroke(wire, with: .color(.white.opacity(0.12)), lineWidth: 1.5)
                for (i, b) in strand.enumerated() {
                    let (col, br) = state(i, strand.count)
                    ctx.drawLayer { l in
                        l.addFilter(.blur(radius: 6)); l.blendMode = .plusLighter
                        let r = 4.0 + 6*br
                        l.fill(Path(ellipseIn: CGRect(x: b.x-r, y: b.y-r, width: 2*r, height: 2*r)), with: .color(col.opacity(0.5*br)))
                    }
                    ctx.fill(Path(ellipseIn: CGRect(x: b.x-4, y: b.y-4, width: 8, height: 8)), with: .color(col.opacity(0.4+0.6*br)))
                }
            }
        }
    }
    func state(_ i: Int, _ n: Int) -> (Color, Double) {
        switch mode {
        case 0:
            let pos = Double(i)/Double(max(n-1,1)), head = (time*0.5).truncatingRemainder(dividingBy: 1)
            let d = abs(pos-head), w = min(d, 1-d); return (palette[(i+Int(time))%5], 0.15+0.85*max(0,1-w*6))
        case 1:
            return (palette[i%5], 0.75+0.25*sin(time*1.5+Double(i)*0.9))
        default:
            let seed = Double((i*2654435761)%1000)/1000.0
            return (palette[i%5], 0.1+0.9*pow(0.5+0.5*sin(time*1.8+seed*6.283),2))
        }
    }
}

func render<V: View>(_ v: V, _ size: CGSize, _ path: String) {
    MainActor.assumeIsolated {
        let r = ImageRenderer(content: v.frame(width: size.width, height: size.height)); r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: path)); print("wrote \(path)") }
    }
}
let size = CGSize(width: 560, height: 360)
render(StringView(time: 0.0, mode: 0), size, "/tmp/xmas_chase.png")
render(StringView(time: 1.3, mode: 0), size, "/tmp/xmas_chase2.png")
render(StringView(time: 0.6, mode: 1), size, "/tmp/xmas_multi.png")
render(StringView(time: 0.6, mode: 2), size, "/tmp/xmas_twinkle.png")
```

Run: `swift scripts/verify_christmas.swift`, then Read the PNGs.
Expected: strands sag downward, bulbs glow with the festive palette; chase shows a moving lit band (t=0 vs t=1.3 differ); multi shows steady alternating colors; twinkle shows scattered on/off bulbs. (The tree effect is verified via `verify_tree_mask.png` in Task 2 plus the running app in Task 4.)

- [ ] **Step 5: Commit**

```bash
git add Sources/Lumora/Views/SurfaceContentView.swift scripts/verify_christmas.swift
git commit -m "$(cat <<'EOF'
Render Christmas tree and string-light effects

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: App smoke test + backlog update

Confirm the effects appear in the picker and render live, and record the feature.

**Files:**
- Modify: `docs/BACKLOG.md`

- [ ] **Step 1: Build and launch**

Run: `swift build` then `swift run Lumora` (background), confirm `pgrep -xl Lumora`, then quit with `pkill -x Lumora`.
Confirm no crash on launch.

- [ ] **Step 2: Manual verification note**

In the running app: add a surface → Properties → Media type Effect → Category "Christmas Lights" → each of the four effects renders (tree with twinkles confined to the tree; three sagging string variations). This step is for the human operator (subagents/CLI can't drive the GUI); note it in the report as operator-verify.

- [ ] **Step 3: Update the backlog**

In `docs/BACKLOG.md`, bump the effect total and add a "Christmas Lights" line under the effects-done section noting the four new effects (`christmasTree`, `chasingLights`, `multiColorLights`, `twinklingLights`) and the new `.christmas` category.

- [ ] **Step 4: Commit**

```bash
git add docs/BACKLOG.md
git commit -m "$(cat <<'EOF'
Note Christmas Lights effects in backlog

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

- **Spec coverage:** tree effect (Task 2 mask + Task 3 render), three string variations (Task 1 geometry + Task 3 render), festive palette (Task 1), `.christmas` category + `usesColor/usesAccent=false` (Task 1), resource bundling (Task 2), tests (Task 1) + offscreen verification (Tasks 2, 3) + app smoke (Task 4). Covered.
- **Placeholders:** none — all code is concrete.
- **Type consistency:** `ChristmasLights.strands(in:)`/`Strand.bulbs`/`palette` and `ChristmasTreeAsset.image`/`litPoints` are used with the same signatures across Tasks 1–3. `EffectKind` case names match everywhere.
