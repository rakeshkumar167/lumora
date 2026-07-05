import AppKit
import Combine
import LumoraKit
import SwiftUI

/// Owns the editable project state. All surface mutations flow through here.
final class ProjectStore: ObservableObject {
    @Published var surfaces: [Surface]
    @Published var selectedID: Surface.ID?

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
        surface.media = .effect(.colorWash, .amber, .red)
        surfaces.append(surface)
        selectedID = surface.id
    }

    func delete(_ id: Surface.ID) {
        surfaces.removeAll { $0.id == id }
        if selectedID == id { selectedID = surfaces.first?.id }
    }

    func update(_ id: Surface.ID, _ mutate: (inout Surface) -> Void) {
        guard let i = surfaces.firstIndex(where: { $0.id == id }) else { return }
        mutate(&surfaces[i])
    }
}
