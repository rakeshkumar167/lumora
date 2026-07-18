# Surface Detection Pipeline (Swift, No AI/ML)

## Goal

Implement a reusable Swift module that analyzes a room photograph and
detects large visible surfaces as editable polygons.

This is intended for a projection mapping application. The system should
**not attempt to recognize objects** (wall, TV, door, etc.). It should
simply identify planar regions bounded by visible edges.

The user can later edit, rename, and assign content to each detected
polygon.

The implementation must use **only classical computer vision** (OpenCV +
Apple frameworks if useful). No CoreML, Vision object detection, AI, or
neural networks.

------------------------------------------------------------------------

# Architecture

``` text
SurfaceDetector
│
├── ImagePreprocessor
├── EdgeDetector
├── LineDetector
├── ContourDetector
├── PolygonExtractor
├── PolygonMerger
├── SurfaceFilter
├── SurfaceTracker
└── SurfaceRenderer
```

Each component should have a single responsibility.

------------------------------------------------------------------------

# Surface Model

``` swift
struct Surface {
    let id: UUID
    var polygon: [CGPoint]
    var area: Double
    var centroid: CGPoint
    var confidence: Double
    var color: UIColor
    var isEditable: Bool
}
```

The detector returns:

``` swift
[Surface]
```

------------------------------------------------------------------------

# Processing Pipeline

## 1. Image Preprocessing

-   Convert `UIImage` → OpenCV `Mat`
-   Convert to grayscale
-   Apply Gaussian Blur
-   Apply Bilateral Filter

Goal: reduce noise while preserving edges.

------------------------------------------------------------------------

## 2. Edge Detection

Use **Canny Edge Detection**.

-   Automatically tune thresholds based on image brightness.
-   Output: binary edge map.

------------------------------------------------------------------------

## 3. Line Detection

Use **Probabilistic Hough Transform**.

Detect:

-   Vertical lines
-   Horizontal lines
-   Long diagonal lines

Ignore short lines.

``` swift
struct Line {
    var p1: CGPoint
    var p2: CGPoint
    var angle: Double
    var length: Double
}
```

------------------------------------------------------------------------

## 4. Merge Similar Lines

Merge lines that are:

-   Nearly parallel
-   Close together
-   Overlapping

This simplifies room geometry.

------------------------------------------------------------------------

## 5. Find Intersections

Compute intersections between merged lines.

These become candidate corners.

Discard invalid or impossible intersections.

------------------------------------------------------------------------

## 6. Contour Detection

Use OpenCV:

``` cpp
findContours()
```

Experiment with:

-   `RETR_TREE`
-   `RETR_EXTERNAL`

Choose the mode that produces the best room geometry.

------------------------------------------------------------------------

## 7. Polygon Approximation

Convert contours into polygons using:

``` cpp
approxPolyDP()
```

Simplify contours while preserving shape.

------------------------------------------------------------------------

## 8. Polygon Validation

Reject polygons that are:

-   Too small
-   Self-intersecting
-   Outside the image
-   Extremely thin
-   Highly irregular

Make thresholds configurable.

------------------------------------------------------------------------

## 9. Merge Adjacent Polygons

Merge polygons when:

-   They share an edge
-   Edges are nearly collinear
-   Average color is similar
-   Combined polygon remains valid

Goal: merge fragmented wall sections into a single surface.

------------------------------------------------------------------------

## 10. Detect Nested Polygons

Keep nested polygons separate.

Examples:

-   TV inside wall
-   Window inside wall
-   Mirror inside wall

Do not merge these.

------------------------------------------------------------------------

## 11. Compute Surface Properties

For every polygon compute:

-   Area
-   Perimeter
-   Centroid
-   Bounding box
-   Aspect ratio
-   Orientation
-   Average color

------------------------------------------------------------------------

## 12. Confidence Score

Generate a confidence value (0.0--1.0) using:

-   Polygon closure
-   Edge strength
-   Contour consistency
-   Straightness

------------------------------------------------------------------------

## 13. Sort Surfaces

Return largest polygons first.

Typical order:

1.  Floor
2.  Walls
3.  Large furniture
4.  TV
5.  Doors
6.  Smaller objects

No semantic labels are assigned.

------------------------------------------------------------------------

# Editing Support

Every polygon should support:

-   Move vertex
-   Insert vertex
-   Delete vertex
-   Move entire polygon
-   Merge polygons
-   Split polygons

Editing should not require rerunning detection.

------------------------------------------------------------------------

# Video Tracking

When processing video:

-   Use Lucas-Kanade Optical Flow or feature tracking.
-   Track polygon vertices between frames.
-   Only rerun full detection if tracking confidence drops.

------------------------------------------------------------------------

# Rendering

Render each surface using a separate `CAShapeLayer`.

Support:

-   Stroke
-   Fill
-   Opacity
-   Selection
-   Dragging
-   Corner handles

------------------------------------------------------------------------

# Public API

``` swift
class SurfaceDetector {
    func detect(in image: UIImage) -> [Surface]
}

class SurfaceTracker {
    func process(frame: UIImage) -> [Surface]
}
```

------------------------------------------------------------------------

# Performance Targets

Platform:

-   macOS
-   iPadOS
-   iOS

Image size:

-   1920 × 1080

Goals:

-   Detection: under 150 ms
-   Tracking: 30 FPS

------------------------------------------------------------------------

# Allowed Libraries

-   OpenCV
-   CoreGraphics
-   QuartzCore
-   Accelerate
-   AVFoundation

Do **not** use:

-   CoreML
-   Vision object recognition
-   Segment Anything
-   Neural networks
-   AI models

------------------------------------------------------------------------

# Code Quality Requirements

-   Modular architecture
-   Small, testable classes
-   Configurable thresholds
-   Clear separation of image processing, geometry, and rendering
-   Well-documented algorithms
-   Extensible design for future geometry improvements

------------------------------------------------------------------------

# Expected Outcome

The library should detect large planar regions from indoor photographs
using only classical computer vision. It should produce editable polygon
overlays suitable for projection mapping, while remaining deterministic,
offline, and free of any AI or machine learning dependencies.
