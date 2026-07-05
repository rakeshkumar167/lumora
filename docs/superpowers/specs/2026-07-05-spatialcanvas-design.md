# SpatialCanvas — Requirements & Design

**Date:** 2026-07-05
**Status:** Approved design, pre-implementation
**Platform:** Native macOS app (Xcode, Swift)

## 1. Overview

SpatialCanvas is a macOS desktop application for creating projection-mapped experiences by treating a room as a digital canvas. The user photographs a room, traces projection surfaces (walls, doors, tables, custom shapes) over the photo, assigns media to each surface, previews the composition live, and projects it fullscreen through a projector connected as a second display.

**Primary user:** hobbyist creating projection art at home (holiday displays, room ambiance, creative experiments). Ease of use is prioritized over professional features.

**Developer context:** the author is new to Swift/macOS development. The design favors high-level Apple frameworks, zero third-party dependencies, and a deliberately boring toolchain.

## 2. Functional Requirements (MVP)

### FR-1 Room canvas
- Import a room photo (JPEG, PNG, HEIC) or capture one via the Mac's camera / Continuity Camera.
- The photo is a reference backdrop for drawing surfaces only; it never appears in projector output.
- The canvas supports zoom and pan while editing.

### FR-2 Surface definition
- Create surfaces by clicking points on the room canvas:
  - **Quad surfaces** (4 corners) — walls, doors, tables, windows; media is perspective-warped to fit.
  - **Polygon surfaces** (N points) — custom shapes; media is clipped to the outline.
- Adjust surfaces by dragging corner handles; move, rotate, and scale whole surfaces.
- Surface management: rename, reorder (z-order), show/hide, lock, duplicate, delete.
- Surfaces are listed in a sidebar; selecting one in the list or on the canvas highlights it in both.

### FR-3 Perspective correction
- Media on a quad surface renders as if projected square-on: the app computes the homography mapping the media rectangle to the drawn quad.
- Polygon surfaces render media in the polygon's bounding box, clipped to the polygon path.

### FR-4 Media library
- Import video files (anything AVFoundation plays: MP4, MOV; animated GIF is converted to video on import) and images (JPEG, PNG, HEIC).
- Built-in generative effects (initial set of four): **color wash**, **gradient sweep**, **particles**, **breathing glow**. Each has editable parameters (color(s), speed, density where applicable).
- Library shows thumbnails; media is assigned to a surface by drag-and-drop or via the properties panel.
- Imported media files are copied into the project package so projects are self-contained.

### FR-5 Per-surface playback settings
- Video: loop on/off, mute/volume, playback speed (0.25×–2×).
- All media: fill mode (stretch / aspect-fill / aspect-fit), opacity, brightness.
- Effects: per-effect parameters as defined in FR-4.

### FR-6 Live preview
- The room canvas continuously shows the composited output — media actually playing, warped, and clipped — overlaid on the room photo.
- Preview and projector output are driven by the same players/animations so they never drift.

### FR-7 Projection mode
- One click sends the composition fullscreen to the projector (second display). Background is pure black everywhere media isn't.
- The editing UI stays live on the main display; edits reflect on the projector in real time.
- Esc (with projector window focused) or an on-screen button exits projection mode.
- If no second display is present, the button is disabled with an explanatory tooltip; a "project in a window" debug option allows testing without a projector.

### FR-8 Projects
- Save/open a project document preserving: room photo, all surface geometry and transforms, media assignments, playback settings, and z-order.
- Standard macOS document behaviors: autosave, Recent Files, rename, duplicate, version browsing (free via the document model).

## 3. Non-Functional Requirements

- **NFR-1 Stability:** projection mode runs 4+ hours without crashes, memory growth, or playback stalls.
- **NFR-2 Responsiveness:** editing interactions (dragging handles, changing properties) reflect in preview and projector output by the next rendered frame (~16 ms at 60 Hz); no beachballs during media import (thumbnailing is async).
- **NFR-3 Output quality:** projector output renders at the display's native resolution; video plays at native frame rate.
- **NFR-4 Zero dependencies:** Apple frameworks only. No SPM/CocoaPods packages in the MVP.
- **NFR-5 Sandboxed:** the app is sandboxed with user-selected-file and camera entitlements only.

## 4. Non-Goals (MVP)

The architecture leaves room for these; the MVP code does not attempt them:

- AI-based surface detection
- Camera-based automatic projector calibration
- Multi-projector output and synchronization
- Edge blending
- Timeline-based animation / sequencing
- Audio-reactive or sensor-driven interactivity
- NDI/Syphon input/output

## 5. Approaches Considered

### A. SwiftUI + Core Animation compositing — **chosen**
Editing UI in SwiftUI. Each surface is a CALayer subtree (AVPlayerLayer for video, content layer for images, CAEmitterLayer/CAGradientLayer for effects), perspective-warped via a CATransform3D computed from the quad homography. Fastest to MVP, most beginner-friendly, no shader code; video decode, looping, and particles come from Apple frameworks. Trade-off: edge blending and multi-projector sync will eventually need Metal — mitigated by hiding rendering behind a `SurfaceRenderer` protocol.

### B. Custom Metal renderer — rejected for MVP
One Metal pipeline drawing perspective-textured quads; video via AVPlayerItemVideoOutput → CVMetalTextureCache. The right long-term engine, but a steep hill for a Swift newcomer: weeks of texture plumbing before the first mapped video. Revisit as a second `SurfaceRenderer` backend when edge blending or multi-projector support becomes real.

### C. Web-hybrid (WKWebView/Tauri + WebGL) — rejected
Easy quad warping in WebGL and a large ecosystem, but fights the native-Xcode goal, complicates multi-display fullscreen and video performance, and teaches web-GL instead of macOS.

## 6. Architecture

```
┌────────────────────────────────────────────────┐
│  UI (SwiftUI)                                  │
│  WorkspaceView: canvas, surface list,          │
│  media library, properties panel               │
├────────────────────────────────────────────────┤
│  App State (@Observable models)                │
│  ProjectStore, SelectionState, PlaybackState   │
├────────────────────────────────────────────────┤
│  Rendering (protocol: SurfaceRenderer)         │
│  CoreAnimationRenderer: CALayer tree,          │
│  homography → CATransform3D, AVPlayerLayer,    │
│  CAEmitterLayer effects                        │
├────────────────────────────────────────────────┤
│  Services                                      │
│  MediaLibrary, ProjectPersistence (document),  │
│  DisplayManager (detect projector, fullscreen) │
└────────────────────────────────────────────────┘
```

### Key decisions

- **One composition, two windows.** The renderer builds a single CALayer composition. The projector window — a borderless NSWindow placed on the second display at native resolution — hosts the live composition. The editor preview shows the same composition scaled inside the room-photo canvas. Video layers on both sides are driven by shared AVPlayer instances so preview and output never drift.
- **Geometry core is pure Swift.** `Surface` (id, name, points in normalized room-space, transform, media assignment, playback settings) and the homography math (unit square → arbitrary quad as CATransform3D) have no UI imports. Pure functions, fully unit-testable.
- **Coordinates are normalized.** Surface points are stored in normalized room-photo space (0–1). Rendering maps them to preview pixels or projector pixels at draw time, so the same geometry serves both.
- **Renderer is swappable.** `SurfaceRenderer` is the seam for a future Metal backend; the editor and models never touch CALayer types directly.

### Components

| Component | Responsibility | Depends on |
|---|---|---|
| `WorkspaceView` and child views | Editing UI, drawing/adjusting surfaces, panels | App State |
| `ProjectStore` | Owns the document model; all mutations flow through it (undo support) | Models |
| `Surface`, `MediaAsset`, `PlaybackSettings` | Value types describing the project | — |
| `Homography` | Quad ↔ rect projective math → CATransform3D | — |
| `SurfaceRenderer` (protocol) + `CoreAnimationRenderer` | Turn project state into a live composition | Models, AVFoundation, QuartzCore |
| `EffectLayerFactory` | Builds the four generative effect layers from parameters | QuartzCore |
| `MediaLibrary` | Import, copy-into-project, thumbnails, relinking | AVFoundation, CoreImage |
| `DisplayManager` | Enumerate displays, own the projection NSWindow, handle hot-plug | AppKit |
| `ProjectDocument` | Encode/decode the `.spatialcanvas` package | Models |

### Data flow

User edit → `ProjectStore` mutation (undoable) → observers fire → SwiftUI views update **and** `CoreAnimationRenderer` patches the affected layer(s). Renderer updates are incremental (only the changed surface), not full rebuilds.

## 7. Data Model & Persistence

`.spatialcanvas` is a document **package** (a folder Finder treats as one file):

```
MyRoom.spatialcanvas/
├── project.json        # schema-versioned project state
├── room.heic           # room reference photo
└── media/
    ├── <uuid>.mov
    └── <uuid>.png
```

`project.json` (schema `version: 1`) holds: room photo reference, ordered surface array (id, name, type quad|polygon, normalized points, transform, visibility/lock, media assignment by asset id or effect definition, playback settings), and media asset table (id, original filename, relative path).

- Media files are **copied** into the package on import (self-contained projects; hobbyist-scale sizes are acceptable).
- Schema is versioned from day one so future features can migrate.

## 8. Error Handling

| Situation | Behavior |
|---|---|
| Media file missing/corrupt on open | Surface shows a striped placeholder; properties panel offers "Relink…" |
| Unplayable file dragged in | Import rejected with a message naming the file and why |
| Projector unplugged during projection | Exit projection mode gracefully, return to editor with a notice |
| Second display absent | Projection button disabled with tooltip; "project in a window" available for testing |
| Save failure (disk full, permissions) | Standard NSDocument error presentation; project state kept in memory |

## 9. Xcode Project Spec

| Item | Choice |
|---|---|
| Project name | `SpatialCanvas` — macOS App template, Swift |
| Interface / lifecycle | SwiftUI, `DocumentGroup`-based document app |
| Language mode | Swift 5.10+, strict concurrency enabled |
| Minimum deployment | macOS 14 (Sonoma) |
| Signing | Personal team; App Sandbox on |
| Entitlements | `com.apple.security.files.user-selected.read-write`, `com.apple.security.device.camera` |
| Document type | `.spatialcanvas`, package = YES, UTI `com.lumora.spatialcanvas.project` (conforms to `com.apple.package`) |
| Frameworks | SwiftUI, AppKit, AVFoundation, AVKit, QuartzCore, CoreImage — all Apple, no external dependencies |
| Build phases | Standard only — no run scripts, no package managers |

### Source layout

```
SpatialCanvas.xcodeproj
├── SpatialCanvas/                    (app target)
│   ├── App/                          SpatialCanvasApp, DocumentGroup setup
│   ├── Models/                       Surface, MediaAsset, ProjectDocument,
│   │                                 PlaybackSettings, geometry math
│   ├── Rendering/                    SurfaceRenderer protocol,
│   │                                 CoreAnimationRenderer, Homography,
│   │                                 EffectLayerFactory
│   ├── Views/                        WorkspaceView, RoomCanvasView,
│   │                                 SurfaceListView, MediaLibraryView,
│   │                                 PropertiesPanelView, ProjectionWindow
│   ├── Services/                     MediaLibrary, DisplayManager,
│   │                                 ThumbnailGenerator
│   └── Resources/                    effect definitions, assets
└── SpatialCanvasTests/               (unit test target)
```

## 10. Testing Strategy

- **Unit tests (the bulk):** homography math (known quads → known transforms, round-trips), surface geometry (hit-testing, handle-drag math, normalization), `project.json` encode/decode round-trips, media relinking logic. All pure Swift, fast, no UI.
- **Manual test checklist:** warp correctness on a real wall, projector hot-plug/unplug, projection-mode soak run (4+ hours with mixed video/image/effects), media import edge cases (huge video, unsupported codec).
- Scripted UI tests of CALayer output are deliberately out of scope for the MVP — poor cost/benefit at this stage.

## 11. Future Roadmap Hooks

How the architecture accommodates the stated future capabilities without MVP code paying for them:

- **AI surface detection** → a producer of `Surface` values; plugs in ahead of `ProjectStore`, no rendering changes.
- **Projector calibration / edge blending / multi-projector** → a second `SurfaceRenderer` backend (Metal) plus `DisplayManager` growth; editor and models unchanged.
- **Timelines** → `PlaybackSettings` grows a schedule; renderer already receives settings changes incrementally.
- **Interactivity/sensors** → external inputs mutate `ProjectStore` the same way UI edits do.
