import AppKit
import Combine
import LumoraKit
import SwiftUI

/// How mouse drags on the selected surface behave in the canvas.
enum EditTool: String, CaseIterable, Identifiable {
    case arrow   // drag corner handles to warp the surface
    case hand    // drag anywhere inside to move the whole surface
    case pen     // click to drop/connect joints of the selected light line
    var id: String { rawValue }
}

/// Owns the editable project state. All surface mutations flow through here.
final class ProjectStore: ObservableObject {
    @Published var surfaces: [Surface]
    @Published var selectedID: Surface.ID?
    @Published var tool: EditTool = .arrow
    @Published var lightLines: [LightLine] = []
    @Published var selectedLineID: LightLine.ID?

    let roomImage: NSImage
    let canvasSize: CGSize

    init(surfaces: [Surface], roomImage: NSImage, canvasSize: CGSize) {
        self.surfaces = surfaces
        self.roomImage = roomImage
        self.canvasSize = canvasSize
        self.selectedID = surfaces.first?.id
    }

    /// A ready-to-demo project: a generated room with two animated surfaces
    /// already mapped onto the back wall and the (perspective) left wall.
    static func sample() -> ProjectStore {
        let size = CGSize(width: 960, height: 600)
        let image = SampleContent.roomImage(size: size)

        let surface1 = Surface(
            name: "Surface 1",
            points: [
                CGPoint(x: 0.400, y: 0.250),
                CGPoint(x: 0.680, y: 0.250),
                CGPoint(x: 0.680, y: 0.650),
                CGPoint(x: 0.400, y: 0.650),
            ],
            media: .effect(.breathingGlow, .teal, .blue)
        )

        // Kept as a perspective (non-rectangular) quad to show corner warping.
        let surface2 = Surface(
            name: "Surface 2",
            points: [
                CGPoint(x: 0.080, y: 0.230),
                CGPoint(x: 0.320, y: 0.300),
                CGPoint(x: 0.320, y: 0.620),
                CGPoint(x: 0.080, y: 0.780),
            ],
            media: .effect(.gradientSweep, .magenta, .violet)
        )

        return ProjectStore(surfaces: [surface1, surface2], roomImage: image, canvasSize: size)
    }

    var selected: Surface? { surfaces.first { $0.id == selectedID } }

    /// A binding to the currently selected surface, for the properties panel.
    func selectedBinding() -> Binding<Surface>? {
        guard let id = selectedID, surfaces.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.surfaces.first { $0.id == id } ?? Surface.defaultRect(name: "") },
            set: { newValue in
                if let i = self.surfaces.firstIndex(where: { $0.id == id }) {
                    self.surfaces[i] = newValue
                }
            }
        )
    }

    func addSurface() {
        var surface = Surface.defaultRect(name: "Surface \(surfaces.count + 1)")
        surface.media = .effect(.grid, .cyan, RGBAColor(r: 0.05, g: 0.06, b: 0.09))
        surfaces.append(surface)
        selectSurface(surface.id)
    }

    // MARK: - Save / Open

    /// The current editable state as a saveable document.
    func makeProject() -> Project { Project(surfaces: surfaces, lightLines: lightLines) }

    /// Replace all surfaces and light lines with those from a loaded project.
    func load(_ project: Project) {
        surfaces = project.surfaces
        lightLines = project.lightLines
        selectedID = surfaces.first?.id
        selectedLineID = nil
    }

    /// Change a surface's shape, preserving its location/size (bounding box).
    func setShape(_ id: Surface.ID, to shape: SurfaceShape, sides: Int = 6) {
        update(id) { s in
            let b = Surface.bounds(of: s.points)
            switch shape {
            case .quad, .ellipse:
                s.points = Surface.rectCorners(b)
            case .polygon:
                s.points = Surface.polygonCorners(b, sides: sides)
            }
            s.shape = shape
        }
    }

    /// Rebuild a polygon surface with a new vertex count (regular polygon in
    /// its current bounds).
    func setPolygonSides(_ id: Surface.ID, _ sides: Int) {
        update(id) { s in
            let b = Surface.bounds(of: s.points)
            s.points = Surface.polygonCorners(b, sides: min(max(sides, 3), 12))
        }
    }

    func delete(_ id: Surface.ID) {
        surfaces.removeAll { $0.id == id }
        if selectedID == id { selectedID = surfaces.first?.id }
    }

    func update(_ id: Surface.ID, _ mutate: (inout Surface) -> Void) {
        guard let i = surfaces.firstIndex(where: { $0.id == id }) else { return }
        mutate(&surfaces[i])
    }

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
            if let last = lastJointID, last != joint.id, line.joints.contains(where: { $0.id == last }) {
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
            // Verify both joints belong to this line before connecting them.
            guard line.joints.contains(where: { $0.id == last }),
                  line.joints.contains(where: { $0.id == jointID }) else { return }
            // Avoid duplicate segments between the same pair.
            let exists = line.segments.contains {
                ($0.a == last && $0.b == jointID) || ($0.a == jointID && $0.b == last)
            }
            if !exists { line.segments.append(LightLine.Segment(a: last, b: jointID)) }
        }
    }
}
