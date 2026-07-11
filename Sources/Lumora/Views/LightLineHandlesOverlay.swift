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
