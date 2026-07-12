import AppKit
import LumoraKit
import SwiftUI

/// Sheet that previews auto-detected surfaces on the room photo and lets the
/// user keep/discard each before adding them to the canvas.
struct SurfaceDetectionReviewView: View {
    let image: NSImage
    let quads: [DetectedQuad]
    let onAdd: ([[CGPoint]]) -> Void
    let onCancel: () -> Void

    @State private var keep: [Bool]

    init(image: NSImage, quads: [DetectedQuad],
         onAdd: @escaping ([[CGPoint]]) -> Void, onCancel: @escaping () -> Void) {
        self.image = image
        self.quads = quads
        self.onAdd = onAdd
        self.onCancel = onCancel
        _keep = State(initialValue: Array(repeating: true, count: quads.count))
    }

    private let palette: [Color] = [.red, .green, .blue, .orange, .purple, .teal, .yellow, .pink]
    private var keptCount: Int { keep.filter { $0 }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(quads.isEmpty ? "No surfaces detected"
                     : "Detected \(quads.count) surface\(quads.count == 1 ? "" : "s")")
                    .font(.headline)
                Spacer()
            }
            .padding()

            GeometryReader { geo in
                let fit = aspectFit(imageSize: image.size, in: geo.size)
                ZStack {
                    Image(nsImage: image).resizable().scaledToFit()
                    Canvas { ctx, _ in
                        for (i, q) in quads.enumerated() where i < keep.count && keep[i] {
                            let col = palette[i % palette.count]
                            let pts = q.corners.map {
                                CGPoint(x: fit.minX + Double($0.x) * fit.width,
                                        y: fit.minY + Double($0.y) * fit.height)
                            }
                            var path = Path()
                            path.move(to: pts[0]); for p in pts.dropFirst() { path.addLine(to: p) }; path.closeSubpath()
                            ctx.fill(path, with: .color(col.opacity(0.16)))
                            ctx.stroke(path, with: .color(col), lineWidth: 3)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(minHeight: 340)
            .background(Color.black.opacity(0.06))

            if !quads.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(quads.indices, id: \.self) { i in
                            Toggle(isOn: binding(i)) {
                                Label("\(i + 1) · \(Int(quads[i].areaFraction * 100))%",
                                      systemImage: quads[i].source == .plane ? "rectangle.dashed" : "tv")
                            }
                            .toggleStyle(.button)
                            .tint(palette[i % palette.count])
                        }
                    }
                    .padding()
                }
            }

            Divider()
            HStack {
                Button("Cancel", role: .cancel) { onCancel() }
                Spacer()
                Button("Add \(keptCount) Surface\(keptCount == 1 ? "" : "s")") {
                    let selected = quads.enumerated()
                        .filter { $0.offset < keep.count && keep[$0.offset] }
                        .map { $0.element.corners }
                    onAdd(selected)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(keptCount == 0)
            }
            .padding()
        }
        .frame(width: 760, height: 660)
    }

    private func binding(_ i: Int) -> Binding<Bool> {
        Binding(get: { keep[i] }, set: { keep[i] = $0 })
    }

    private func aspectFit(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }
}
