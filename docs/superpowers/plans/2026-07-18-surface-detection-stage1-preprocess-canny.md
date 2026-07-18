# Surface Detection — Stage 1: Preprocessing + Canny (Implementation Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first stage of the classical-CV surface-detection pipeline in pure Swift: a grayscale image preprocessor (grayscale extraction, Gaussian blur, bilateral smoothing) and a Canny edge detector (Sobel gradient → non-max suppression → auto-threshold hysteresis).

**Architecture:** New value types (`GrayImage`, `GradientField`, `EdgeMap`) plus stateless enums (`ImagePreprocessor`, `Sobel`, `CannyEdgeDetector`) under `Sources/LumoraKit/SurfaceDetection/CV/`. All pure Swift + CoreGraphics (for CGImage rasterization) + `Foundation`/`Darwin` math. No OpenCV, no Vision, no Accelerate required in this stage. Every unit is exercised by synthetic `CGImage`/`GrayImage` fixtures (matching the existing `SurfaceDetectorTests` convention — no external sample photos).

**Tech Stack:** Swift, XCTest, CoreGraphics, SwiftPM. Target: `LumoraKit`; tests: `LumoraTests` (depends on `LumoraKit`).

## Global Constraints

- **Pure Swift only** — no OpenCV, CoreML, Vision, or ML. CoreGraphics is allowed solely to rasterize a `CGImage` into a pixel buffer.
- **macOS-native types** — `CGImage` input, no `UIImage`/`UIColor`.
- **Top-left origin, no vertical flip.** A `CGContext` bitmap already stores row 0 as the TOP scanline; do NOT apply a `translateBy`/`scaleBy` flip when drawing a `CGImage` into a context — that mirrors the raster vertically (a real bug fixed previously in `SurfaceDetector.pixelsTopLeft`). Index buffers as `pixels[y*width + x]` with `y = 0` at the top.
- **Verification uses synthetic fixtures** built in-test (see `SurfaceDetectorTests.syntheticRoom`), plus asymmetric fixtures (differ top↔bottom AND left↔right) so a flip/mirror bug cannot hide.
- All new types are `public` (consumed by later pipeline stages); helper methods may be `internal` for `@testable` access.
- `swift test` must stay green (currently 100 tests) and grow with the new tests.

---

## File Structure

- `Sources/LumoraKit/SurfaceDetection/CV/GrayImage.swift` (create) — `GrayImage` value type.
- `Sources/LumoraKit/SurfaceDetection/CV/ImagePreprocessor.swift` (create) — grayscale extraction, Gaussian blur, bilateral.
- `Sources/LumoraKit/SurfaceDetection/CV/Sobel.swift` (create) — `GradientField` + Sobel gradients.
- `Sources/LumoraKit/SurfaceDetection/CV/CannyEdgeDetector.swift` (create) — `EdgeMap` + full Canny.
- `Tests/LumoraTests/ImagePreprocessorTests.swift` (create)
- `Tests/LumoraTests/SobelTests.swift` (create)
- `Tests/LumoraTests/CannyEdgeDetectorTests.swift` (create)

---

### Task 1: `GrayImage` + grayscale extraction

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/GrayImage.swift`
- Create: `Sources/LumoraKit/SurfaceDetection/CV/ImagePreprocessor.swift`
- Test: `Tests/LumoraTests/ImagePreprocessorTests.swift`

**Interfaces:**
- Produces:
  - `struct GrayImage { let width: Int; let height: Int; var pixels: [Float] }` — row-major, length `width*height`, values `0...1`; `func at(_ x: Int, _ y: Int) -> Float`.
  - `enum ImagePreprocessor { static func grayscale(from image: CGImage, maxDimension: Int) -> GrayImage }` — downscales so the longer side ≤ `maxDimension` (never upscales), rasterizes into a device-gray buffer (top-left origin), returns normalized floats.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/ImagePreprocessorTests.swift`:

```swift
import XCTest
import CoreGraphics
@testable import LumoraKit

final class ImagePreprocessorTests: XCTestCase {
    /// Build a device-gray CGImage from a per-pixel fill. Row 0 is the TOP row
    /// (matches the no-flip raster convention used throughout the pipeline).
    static func grayCGImage(width w: Int, height h: Int, fill: (Int, Int) -> UInt8) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { bytes[y * w + x] = fill(x, y) } }
        let cs = CGColorSpaceCreateDeviceGray()
        let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w, space: cs,
                            bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        return ctx.makeImage()!
    }

    func testGrayscaleRecoversAsymmetricPattern() {
        // White only in the top-left quadrant: catches both H and V flips.
        let img = Self.grayCGImage(width: 4, height: 4) { x, y in (x < 2 && y < 2) ? 255 : 0 }
        let g = ImagePreprocessor.grayscale(from: img, maxDimension: 4)
        XCTAssertEqual(g.width, 4)
        XCTAssertEqual(g.height, 4)
        XCTAssertGreaterThan(g.at(0, 0), 0.9, "top-left should be white")
        XCTAssertLessThan(g.at(3, 3), 0.1, "bottom-right should be black")
        XCTAssertLessThan(g.at(3, 0), 0.1, "top-right should be black")
        XCTAssertLessThan(g.at(0, 3), 0.1, "bottom-left should be black")
    }

    func testGrayscaleDownscalesToMaxDimension() {
        let img = Self.grayCGImage(width: 8, height: 4) { _, _ in 128 }
        let g = ImagePreprocessor.grayscale(from: img, maxDimension: 4)
        XCTAssertEqual(g.width, 4)
        XCTAssertEqual(g.height, 2)
        XCTAssertEqual(g.pixels.count, 8)
    }

    func testGrayscaleNeverUpscales() {
        let img = Self.grayCGImage(width: 4, height: 4) { _, _ in 200 }
        let g = ImagePreprocessor.grayscale(from: img, maxDimension: 100)
        XCTAssertEqual(g.width, 4)
        XCTAssertEqual(g.height, 4)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ImagePreprocessorTests`
Expected: FAIL — compile error (`GrayImage` / `ImagePreprocessor` not found).

- [ ] **Step 3: Write `GrayImage`**

Create `Sources/LumoraKit/SurfaceDetection/CV/GrayImage.swift`:

```swift
import Foundation

/// A single-channel image: row-major float pixels in `0...1`, top-left origin.
public struct GrayImage: Equatable {
    public let width: Int
    public let height: Int
    public var pixels: [Float]

    public init(width: Int, height: Int, pixels: [Float]) {
        precondition(pixels.count == width * height, "pixel count must equal width*height")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Value at (x, y); callers must pass in-bounds coordinates.
    @inlinable public func at(_ x: Int, _ y: Int) -> Float { pixels[y * width + x] }
}
```

- [ ] **Step 4: Write `ImagePreprocessor.grayscale`**

Create `Sources/LumoraKit/SurfaceDetection/CV/ImagePreprocessor.swift`:

```swift
import CoreGraphics

/// Classical-CV preprocessing: rasterize + smooth a room photo into a
/// noise-reduced grayscale buffer for edge detection. Pure Swift + CoreGraphics.
public enum ImagePreprocessor {
    /// Downscale (never upscale) so the longer side ≤ `maxDimension`, then
    /// rasterize into a device-gray, top-left-origin buffer normalized to 0...1.
    public static func grayscale(from image: CGImage, maxDimension: Int) -> GrayImage {
        let longSide = max(image.width, image.height)
        let scale = longSide > maxDimension ? Double(maxDimension) / Double(longSide) : 1.0
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))

        let cs = CGColorSpaceCreateDeviceGray()
        var bytes = [UInt8](repeating: 0, count: w * h)
        // No flip: CGContext bitmap row 0 is already the TOP scanline.
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return GrayImage(width: w, height: h, pixels: [Float](repeating: 0, count: w * h))
        }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var pixels = [Float](repeating: 0, count: w * h)
        for i in 0..<(w * h) { pixels[i] = Float(bytes[i]) / 255.0 }
        return GrayImage(width: w, height: h, pixels: pixels)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter ImagePreprocessorTests`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/GrayImage.swift \
        Sources/LumoraKit/SurfaceDetection/CV/ImagePreprocessor.swift \
        Tests/LumoraTests/ImagePreprocessorTests.swift
git commit -m "feat(detect): GrayImage + grayscale extraction

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Separable Gaussian blur

**Files:**
- Modify: `Sources/LumoraKit/SurfaceDetection/CV/ImagePreprocessor.swift`
- Test: `Tests/LumoraTests/ImagePreprocessorTests.swift`

**Interfaces:**
- Produces: `ImagePreprocessor.gaussianBlur(_ img: GrayImage, sigma: Float) -> GrayImage` — separable Gaussian with clamp-to-edge borders; kernel radius `= max(1, round(sigma*3))`; preserves dimensions and (approximately) a uniform image.

- [ ] **Step 1: Write the failing test**

Add to `ImagePreprocessorTests`:

```swift
    func testGaussianBlurPreservesUniformImage() {
        let g = GrayImage(width: 5, height: 5, pixels: [Float](repeating: 0.5, count: 25))
        let b = ImagePreprocessor.gaussianBlur(g, sigma: 1.0)
        XCTAssertEqual(b.width, 5)
        XCTAssertEqual(b.height, 5)
        for v in b.pixels { XCTAssertEqual(v, 0.5, accuracy: 1e-4) }
    }

    func testGaussianBlurSpreadsAnImpulse() {
        var px = [Float](repeating: 0, count: 25)
        px[2 * 5 + 2] = 1.0 // center impulse
        let g = GrayImage(width: 5, height: 5, pixels: px)
        let b = ImagePreprocessor.gaussianBlur(g, sigma: 1.0)
        XCTAssertLessThan(b.at(2, 2), 1.0, "center energy should spread out")
        XCTAssertGreaterThan(b.at(2, 1), 0.0, "neighbor should receive energy")
        XCTAssertGreaterThan(b.at(1, 2), 0.0, "neighbor should receive energy")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ImagePreprocessorTests/testGaussianBlurPreservesUniformImage`
Expected: FAIL — `gaussianBlur` not found.

- [ ] **Step 3: Implement `gaussianBlur`**

Add to `ImagePreprocessor` (inside the enum) in `ImagePreprocessor.swift`:

```swift
    /// Separable Gaussian blur with clamp-to-edge borders.
    public static func gaussianBlur(_ img: GrayImage, sigma: Float) -> GrayImage {
        let radius = max(1, Int((sigma * 3).rounded()))
        var kernel = [Float](repeating: 0, count: 2 * radius + 1)
        var sum: Float = 0
        for i in -radius...radius {
            let v = expf(-Float(i * i) / (2 * sigma * sigma))
            kernel[i + radius] = v
            sum += v
        }
        for i in kernel.indices { kernel[i] /= sum }

        let w = img.width, h = img.height
        var tmp = [Float](repeating: 0, count: w * h)
        // Horizontal pass.
        for y in 0..<h {
            for x in 0..<w {
                var acc: Float = 0
                for k in -radius...radius {
                    let xx = min(max(x + k, 0), w - 1)
                    acc += img.pixels[y * w + xx] * kernel[k + radius]
                }
                tmp[y * w + x] = acc
            }
        }
        // Vertical pass.
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                var acc: Float = 0
                for k in -radius...radius {
                    let yy = min(max(y + k, 0), h - 1)
                    acc += tmp[yy * w + x] * kernel[k + radius]
                }
                out[y * w + x] = acc
            }
        }
        return GrayImage(width: w, height: h, pixels: out)
    }
```

Note: `expf` comes from the C math library, available via the `CoreGraphics` import (which transitively imports `Darwin`). If the compiler cannot find `expf`, add `import Foundation` at the top of the file.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ImagePreprocessorTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/ImagePreprocessor.swift \
        Tests/LumoraTests/ImagePreprocessorTests.swift
git commit -m "feat(detect): separable Gaussian blur

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Bilateral (edge-preserving) smoothing

**Files:**
- Modify: `Sources/LumoraKit/SurfaceDetection/CV/ImagePreprocessor.swift`
- Test: `Tests/LumoraTests/ImagePreprocessorTests.swift`

**Interfaces:**
- Produces: `ImagePreprocessor.bilateral(_ img: GrayImage, radius: Int, sigmaSpatial: Float, sigmaRange: Float) -> GrayImage` — edge-preserving smoothing: a hard step edge stays sharp (min≈0, max≈1) where a Gaussian would blur it toward mid-gray.

- [ ] **Step 1: Write the failing test**

Add to `ImagePreprocessorTests`:

```swift
    func testBilateralPreservesAStepEdge() {
        // Left half black, right half white — a hard vertical edge.
        let w = 8, h = 4
        var px = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { px[y * w + x] = x < w / 2 ? 0 : 1 } }
        let g = GrayImage(width: w, height: h, pixels: px)

        let bil = ImagePreprocessor.bilateral(g, radius: 2, sigmaSpatial: 2.0, sigmaRange: 0.1)
        // Edge-preserving: dark side stays dark, bright side stays bright.
        XCTAssertLessThan(bil.at(0, 2), 0.1)
        XCTAssertGreaterThan(bil.at(7, 2), 0.9)

        // Contrast: a Gaussian of similar spatial extent smears the boundary.
        let gauss = ImagePreprocessor.gaussianBlur(g, sigma: 2.0)
        XCTAssertGreaterThan(bil.at(7, 2) - bil.at(0, 2),
                             gauss.at(7, 2) - gauss.at(0, 2),
                             "bilateral keeps more edge contrast than Gaussian")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ImagePreprocessorTests/testBilateralPreservesAStepEdge`
Expected: FAIL — `bilateral` not found.

- [ ] **Step 3: Implement `bilateral`**

Add to `ImagePreprocessor`:

```swift
    /// Edge-preserving smoothing: neighbors are weighted by both spatial
    /// distance (`sigmaSpatial`) and intensity difference (`sigmaRange`), so
    /// strong edges are preserved while flat noise is averaged out.
    public static func bilateral(_ img: GrayImage, radius: Int,
                                 sigmaSpatial: Float, sigmaRange: Float) -> GrayImage {
        let w = img.width, h = img.height
        let s2 = 2 * sigmaSpatial * sigmaSpatial
        let r2 = 2 * sigmaRange * sigmaRange
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let center = img.pixels[y * w + x]
                var acc: Float = 0, wsum: Float = 0
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let xx = min(max(x + dx, 0), w - 1)
                        let yy = min(max(y + dy, 0), h - 1)
                        let v = img.pixels[yy * w + xx]
                        let dI = v - center
                        let weight = expf(-Float(dx * dx + dy * dy) / s2) * expf(-(dI * dI) / r2)
                        acc += v * weight
                        wsum += weight
                    }
                }
                out[y * w + x] = wsum > 0 ? acc / wsum : center
            }
        }
        return GrayImage(width: w, height: h, pixels: out)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ImagePreprocessorTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/ImagePreprocessor.swift \
        Tests/LumoraTests/ImagePreprocessorTests.swift
git commit -m "feat(detect): bilateral edge-preserving smoothing

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Sobel gradients

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/Sobel.swift`
- Test: `Tests/LumoraTests/SobelTests.swift`

**Interfaces:**
- Consumes: `GrayImage`.
- Produces:
  - `struct GradientField { let width: Int; let height: Int; var magnitude: [Float]; var orientation: [Float] }` — row-major; `orientation` in radians = `atan2(gy, gx)`.
  - `enum Sobel { static func gradients(_ img: GrayImage) -> GradientField }` — 3×3 Sobel with clamp-to-edge borders.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/SobelTests.swift`:

```swift
import XCTest
@testable import LumoraKit

final class SobelTests: XCTestCase {
    /// A vertical edge: left half 0, right half 1.
    private func verticalEdge(w: Int = 8, h: Int = 6) -> GrayImage {
        var px = [Float](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w { px[y * w + x] = x < w / 2 ? 0 : 1 } }
        return GrayImage(width: w, height: h, pixels: px)
    }

    func testGradientIsLargeOnTheEdgeColumn() {
        let g = Sobel.gradients(verticalEdge())
        // At the boundary (x = 3→4) magnitude is high; deep in a flat region it is ~0.
        let onEdge = g.magnitude[3 * 8 + 3]
        let flat = g.magnitude[3 * 8 + 0]
        XCTAssertGreaterThan(onEdge, 0.5)
        XCTAssertLessThan(flat, 1e-3)
    }

    func testOrientationOnVerticalEdgeIsHorizontal() {
        let g = Sobel.gradients(verticalEdge())
        // Gradient of a left-dark→right-bright edge points in +x: angle ≈ 0.
        let angle = g.orientation[3 * 8 + 3]
        XCTAssertEqual(angle, 0, accuracy: 0.2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SobelTests`
Expected: FAIL — `Sobel` / `GradientField` not found.

- [ ] **Step 3: Implement `Sobel`**

Create `Sources/LumoraKit/SurfaceDetection/CV/Sobel.swift`:

```swift
import Foundation

/// Gradient magnitude + orientation from a 3×3 Sobel operator.
public struct GradientField: Equatable {
    public let width: Int
    public let height: Int
    public var magnitude: [Float]
    public var orientation: [Float] // radians, atan2(gy, gx)
}

public enum Sobel {
    public static func gradients(_ img: GrayImage) -> GradientField {
        let w = img.width, h = img.height
        var mag = [Float](repeating: 0, count: w * h)
        var ori = [Float](repeating: 0, count: w * h)

        @inline(__always) func p(_ x: Int, _ y: Int) -> Float {
            img.pixels[min(max(y, 0), h - 1) * w + min(max(x, 0), w - 1)]
        }
        for y in 0..<h {
            for x in 0..<w {
                let gx = (p(x + 1, y - 1) + 2 * p(x + 1, y) + p(x + 1, y + 1))
                       - (p(x - 1, y - 1) + 2 * p(x - 1, y) + p(x - 1, y + 1))
                let gy = (p(x - 1, y + 1) + 2 * p(x, y + 1) + p(x + 1, y + 1))
                       - (p(x - 1, y - 1) + 2 * p(x, y - 1) + p(x + 1, y - 1))
                mag[y * w + x] = (gx * gx + gy * gy).squareRoot()
                ori[y * w + x] = atan2f(gy, gx)
            }
        }
        return GradientField(width: w, height: h, magnitude: mag, orientation: ori)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SobelTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/Sobel.swift \
        Tests/LumoraTests/SobelTests.swift
git commit -m "feat(detect): Sobel gradient field

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Canny edge detector

**Files:**
- Create: `Sources/LumoraKit/SurfaceDetection/CV/CannyEdgeDetector.swift`
- Test: `Tests/LumoraTests/CannyEdgeDetectorTests.swift`

**Interfaces:**
- Consumes: `GrayImage`, `ImagePreprocessor.gaussianBlur`, `Sobel.gradients`, `GradientField`.
- Produces:
  - `struct EdgeMap { let width: Int; let height: Int; var edges: [Bool] }` — row-major, `true` = edge pixel.
  - `struct CannyEdgeDetector.Config { var sigma: Float = 1.4; var highPercentile: Float = 0.85; var lowRatio: Float = 0.4 }`.
  - `enum CannyEdgeDetector { static func detect(_ img: GrayImage, config: Config = .init()) -> EdgeMap }` — blur → Sobel → non-max suppression → auto double-threshold (high = `highPercentile` of non-zero suppressed magnitudes, low = `high * lowRatio`) → hysteresis.

- [ ] **Step 1: Write the failing test**

Create `Tests/LumoraTests/CannyEdgeDetectorTests.swift`:

```swift
import XCTest
@testable import LumoraKit

final class CannyEdgeDetectorTests: XCTestCase {
    /// White rectangle (10,10)-(30,30) on a black 40×40 field.
    private func rectangleImage() -> GrayImage {
        let w = 40, h = 40
        var px = [Float](repeating: 0, count: w * h)
        for y in 10..<30 { for x in 10..<30 { px[y * w + x] = 1 } }
        return GrayImage(width: w, height: h, pixels: px)
    }

    private func hasEdgeNear(_ e: EdgeMap, _ cx: Int, _ cy: Int, radius: Int = 2) -> Bool {
        for dy in -radius...radius { for dx in -radius...radius {
            let x = cx + dx, y = cy + dy
            if x >= 0, x < e.width, y >= 0, y < e.height, e.edges[y * e.width + x] { return true }
        } }
        return false
    }

    func testDetectsRectangleBorderNotInterior() {
        let e = CannyEdgeDetector.detect(rectangleImage())
        XCTAssertTrue(e.edges.contains(true), "should find some edges")
        // Border midpoints (top, bottom, left, right of the rectangle).
        XCTAssertTrue(hasEdgeNear(e, 20, 10), "top border")
        XCTAssertTrue(hasEdgeNear(e, 20, 30), "bottom border")
        XCTAssertTrue(hasEdgeNear(e, 10, 20), "left border")
        XCTAssertTrue(hasEdgeNear(e, 30, 20), "right border")
        // No edges deep inside the flat rectangle or the flat background.
        XCTAssertFalse(hasEdgeNear(e, 20, 20, radius: 3), "interior is flat")
        XCTAssertFalse(hasEdgeNear(e, 2, 2, radius: 1), "far background is flat")
    }

    func testFlatImageHasNoEdges() {
        let flat = GrayImage(width: 20, height: 20, pixels: [Float](repeating: 0.5, count: 400))
        let e = CannyEdgeDetector.detect(flat)
        XCTAssertFalse(e.edges.contains(true), "a flat image has no edges")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CannyEdgeDetectorTests`
Expected: FAIL — `CannyEdgeDetector` / `EdgeMap` not found.

- [ ] **Step 3: Implement `CannyEdgeDetector`**

Create `Sources/LumoraKit/SurfaceDetection/CV/CannyEdgeDetector.swift`:

```swift
import Foundation

/// Binary edge map, row-major, top-left origin.
public struct EdgeMap: Equatable {
    public let width: Int
    public let height: Int
    public var edges: [Bool]
}

/// Canny edge detection: Gaussian blur → Sobel → non-max suppression →
/// auto double-threshold → hysteresis. Pure Swift.
public enum CannyEdgeDetector {
    public struct Config {
        /// Pre-blur sigma.
        public var sigma: Float
        /// High threshold = this percentile of the non-zero suppressed magnitudes.
        public var highPercentile: Float
        /// Low threshold = high * lowRatio.
        public var lowRatio: Float
        public init(sigma: Float = 1.4, highPercentile: Float = 0.85, lowRatio: Float = 0.4) {
            self.sigma = sigma
            self.highPercentile = highPercentile
            self.lowRatio = lowRatio
        }
    }

    public static func detect(_ img: GrayImage, config: Config = .init()) -> EdgeMap {
        let blurred = ImagePreprocessor.gaussianBlur(img, sigma: config.sigma)
        let g = Sobel.gradients(blurred)
        let w = g.width, h = g.height
        guard w >= 3, h >= 3 else { return EdgeMap(width: w, height: h, edges: [Bool](repeating: false, count: w * h)) }

        // --- Non-maximum suppression (thin edges to 1px along the gradient). ---
        var nms = [Float](repeating: 0, count: w * h)
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let m = g.magnitude[y * w + x]
                if m == 0 { continue }
                let (a, b) = neighborsAlongGradient(g.magnitude, w, x, y, g.orientation[y * w + x])
                if m >= a && m >= b { nms[y * w + x] = m }
            }
        }

        // --- Auto thresholds from the distribution of suppressed magnitudes. ---
        let high = percentile(nms, config.highPercentile)
        let low = high * config.lowRatio
        if high <= 0 { return EdgeMap(width: w, height: h, edges: [Bool](repeating: false, count: w * h)) }

        // --- Hysteresis: seed on strong pixels, grow through weak-connected ones. ---
        var edges = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        for i in 0..<(w * h) where nms[i] >= high {
            edges[i] = true
            stack.append(i)
        }
        while let idx = stack.popLast() {
            let x = idx % w, y = idx / w
            for dy in -1...1 {
                for dx in -1...1 {
                    let xx = x + dx, yy = y + dy
                    if xx >= 0, xx < w, yy >= 0, yy < h {
                        let j = yy * w + xx
                        if !edges[j], nms[j] >= low {
                            edges[j] = true
                            stack.append(j)
                        }
                    }
                }
            }
        }
        return EdgeMap(width: w, height: h, edges: edges)
    }

    /// The two magnitudes adjacent to (x,y) along the quantized gradient
    /// direction (0°/45°/90°/135°). Callers guarantee 1 ≤ x < w-1, 1 ≤ y < h-1.
    static func neighborsAlongGradient(_ mag: [Float], _ w: Int, _ x: Int, _ y: Int,
                                       _ angle: Float) -> (Float, Float) {
        var a = angle
        if a < 0 { a += .pi }
        let deg = a * 180 / .pi
        @inline(__always) func m(_ xx: Int, _ yy: Int) -> Float { mag[yy * w + xx] }
        if deg < 22.5 || deg >= 157.5 {          // 0°  — compare left / right
            return (m(x - 1, y), m(x + 1, y))
        } else if deg < 67.5 {                   // 45° — compare the two diagonals
            return (m(x - 1, y + 1), m(x + 1, y - 1))
        } else if deg < 112.5 {                  // 90° — compare up / down
            return (m(x, y - 1), m(x, y + 1))
        } else {                                 // 135°
            return (m(x - 1, y - 1), m(x + 1, y + 1))
        }
    }

    /// The value at percentile `p` (0...1) among the strictly-positive entries.
    static func percentile(_ values: [Float], _ p: Float) -> Float {
        let nonzero = values.filter { $0 > 0 }.sorted()
        if nonzero.isEmpty { return 0 }
        let idx = min(nonzero.count - 1, max(0, Int(Float(nonzero.count - 1) * p)))
        return nonzero[idx]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CannyEdgeDetectorTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS — 113 tests (100 existing + 13 new across the three suites).

> If the count differs slightly, that's fine — the requirement is 0 failures and that the new `ImagePreprocessorTests`/`SobelTests`/`CannyEdgeDetectorTests` all pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/LumoraKit/SurfaceDetection/CV/CannyEdgeDetector.swift \
        Tests/LumoraTests/CannyEdgeDetectorTests.swift
git commit -m "feat(detect): Canny edge detector (NMS + auto-threshold hysteresis)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 6: Eyeball overlay on the synthetic room

**Files:**
- Test: `Tests/LumoraTests/CannyEdgeDetectorTests.swift` (add one artifact-writing test)

**Interfaces:**
- Consumes: `ImagePreprocessor.grayscale`, `CannyEdgeDetector.detect`, `CGImage`.
- Produces: no new library symbols — writes a PNG artifact for human review.

- [ ] **Step 1: Add an artifact-writing test**

Add to `CannyEdgeDetectorTests` (reuses the synthetic-room idea from `SurfaceDetectorTests`; writes only when `CANNY_OVERLAY=1` so normal `swift test` is unaffected):

```swift
    func testWritesCannyOverlayArtifactWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["CANNY_OVERLAY"] == "1" else {
            throw XCTSkip("set CANNY_OVERLAY=1 to write the overlay artifact")
        }
        // Synthetic room: horizontal wall/floor split + a dark rectangular screen.
        let w = 320, h = 240
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.82, green: 0.80, blue: 0.76, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.55, green: 0.52, blue: 0.48, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h / 3)) // floor band
        ctx.setFillColor(CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)); ctx.fill(CGRect(x: 110, y: 120, width: 110, height: 70)) // screen
        let room = ctx.makeImage()!

        let gray = ImagePreprocessor.grayscale(from: room, maxDimension: 320)
        let e = CannyEdgeDetector.detect(gray)

        // Render edges as white-on-black into a PNG.
        var bytes = [UInt8](repeating: 0, count: e.width * e.height * 4)
        for i in 0..<(e.width * e.height) {
            let v: UInt8 = e.edges[i] ? 255 : 0
            bytes[i * 4] = v; bytes[i * 4 + 1] = v; bytes[i * 4 + 2] = v; bytes[i * 4 + 3] = 255
        }
        let outCtx = CGContext(data: &bytes, width: e.width, height: e.height, bitsPerComponent: 8,
                               bytesPerRow: e.width * 4, space: cs,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let outImg = outCtx.makeImage()!
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("canny_overlay.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, outImg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        print("CANNY_OVERLAY written to: \(url.path)")
        XCTAssertTrue(e.edges.contains(true))
    }
```

Note: `CGImageDestinationCreateWithURL` needs `import ImageIO` at the top of the test file (add it alongside the existing imports).

- [ ] **Step 2: Run the artifact test**

Run: `CANNY_OVERLAY=1 swift test --filter CannyEdgeDetectorTests/testWritesCannyOverlayArtifactWhenRequested`
Expected: PASS; console prints `CANNY_OVERLAY written to: /…/canny_overlay.png`.

- [ ] **Step 3: Eyeball the artifact**

Open/Read the printed `canny_overlay.png`. Confirm: crisp edges trace the screen rectangle border and the wall/floor horizontal seam; the flat wall, flat floor, and screen interior are (mostly) empty; edges are ~1px thin (NMS working). If the image is noisy or the borders are broken, tune `CannyEdgeDetector.Config` defaults (raise `highPercentile` to suppress noise, lower it to strengthen faint seams) and re-run.

- [ ] **Step 4: Confirm default `swift test` still skips the artifact**

Run: `swift test --filter CannyEdgeDetectorTests`
Expected: the artifact test reports **skipped**; the two assertion tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Tests/LumoraTests/CannyEdgeDetectorTests.swift
git commit -m "test(detect): Canny overlay eyeball artifact (opt-in)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage (Stage 1 slice of the design doc):**
- Preprocessing: grayscale + Gaussian blur + bilateral → Tasks 1–3. ✅
- Canny with auto-tuned thresholds → Task 5 (`highPercentile`/`lowRatio` auto from magnitude distribution). ✅
- Pure Swift, no OpenCV/Vision/ML → all tasks (CoreGraphics only for rasterization). ✅
- Top-left origin, no flip → Task 1 (explicit comment + asymmetric test). ✅
- Synthetic-fixture verification + offscreen overlay eyeball → Tasks 1–6. ✅
- macOS types (`CGImage`, no `UIImage`) → Task 1. ✅

**Placeholder scan:** No TBD/TODO; every code step shows complete code; the two notes (`expf` import fallback, `import ImageIO`) are concrete instructions, not placeholders. ✅

**Type consistency:** `GrayImage` (Task 1) is consumed unchanged by Gaussian/bilateral (2–3), `Sobel.gradients` (4), and `CannyEdgeDetector.detect` (5). `GradientField` (Task 4) is consumed by Canny (5). `EdgeMap` (Task 5) is the produced type Stage 2 will consume. `ImagePreprocessor.gaussianBlur` signature is identical where defined (2) and called (5). ✅

**Scope check:** Single stage — preprocessing + edges only; downstream stages (Hough, contours, polygons, ranking, integration) are separate plans per the design's staged delivery. ✅
```

