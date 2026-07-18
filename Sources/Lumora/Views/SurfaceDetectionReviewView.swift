import AppKit
import LumoraKit
import SwiftUI

/// Sheet that previews auto-detected surfaces on the room photo and lets the
/// user keep/discard each — drag corner handles to fix up the outline, and add
/// their own surfaces — before adding them to the canvas.
struct SurfaceDetectionReviewView: View {
    let image: NSImage
    let surfaces: [DetectedSurface]
    let onAdd: ([[CGPoint]]) -> Void
    let onCancel: () -> Void

    /// One reviewable outline — either detected or user-added. Single source of
    /// truth the whole view drives off, so manual and detected quads behave
    /// identically.
    private struct ReviewItem: Identifiable {
        let id = UUID()
        var corners: [CGPoint]   // normalized, top-left origin, TL,TR,BR,BL
        var keep: Bool
        let label: String        // "62%" for detected, "Manual" for added
        let systemImage: String
    }

    @State private var items: [ReviewItem]

    init(image: NSImage, surfaces: [DetectedSurface],
         onAdd: @escaping ([[CGPoint]]) -> Void, onCancel: @escaping () -> Void) {
        self.image = image
        self.surfaces = surfaces
        self.onAdd = onAdd
        self.onCancel = onCancel
        _items = State(initialValue: surfaces.map { s in
            ReviewItem(corners: s.polygon, keep: true,
                       label: "\(Int(s.confidence * 100))%",
                       systemImage: s.isQuad ? "rectangle.dashed" : "hexagon")
        })
    }

    private let palette: [Color] = [.red, .green, .blue, .orange, .purple, .teal, .yellow, .pink]
    private var keptCount: Int { items.filter(\.keep).count }

    /// A default rectangle centered on the photo (~40% of each dimension).
    private static func centeredRect() -> [CGPoint] {
        [CGPoint(x: 0.30, y: 0.30), CGPoint(x: 0.70, y: 0.30),
         CGPoint(x: 0.70, y: 0.70), CGPoint(x: 0.30, y: 0.70)]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(items.isEmpty ? "No surfaces detected"
                     : "\(items.count) surface\(items.count == 1 ? "" : "s")")
                    .font(.headline)
                if !items.isEmpty {
                    Text("· drag corners to adjust")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()

            GeometryReader { geo in
                let fit = aspectFit(imageSize: image.size, in: geo.size)
                ZStack {
                    Image(nsImage: image).resizable().scaledToFit()
                    Canvas { ctx, _ in
                        for (i, item) in items.enumerated() where item.keep {
                            let col = palette[i % palette.count]
                            let pts = item.corners.map { point($0, in: fit) }
                            var path = Path()
                            path.move(to: pts[0]); for p in pts.dropFirst() { path.addLine(to: p) }; path.closeSubpath()
                            ctx.fill(path, with: .color(col.opacity(0.16)))
                            ctx.stroke(path, with: .color(col), lineWidth: 3)
                        }
                    }
                    ForEach(items.indices, id: \.self) { i in
                        if items[i].keep {
                            ForEach(items[i].corners.indices, id: \.self) { j in
                                handle(item: i, corner: j, fit: fit)
                            }
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(minHeight: 340)
            .background(Color.black.opacity(0.06))

            if !items.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items.indices, id: \.self) { i in
                            Toggle(isOn: keepBinding(i)) {
                                Label("\(i + 1) · \(items[i].label)", systemImage: items[i].systemImage)
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
                Button {
                    items.append(ReviewItem(corners: Self.centeredRect(), keep: true,
                                            label: "Manual",
                                            systemImage: "plus.rectangle.on.rectangle"))
                } label: {
                    Label("Add Surface", systemImage: "plus")
                }
                Spacer()
                Button("Add \(keptCount) Surface\(keptCount == 1 ? "" : "s")") {
                    let selected = items.filter(\.keep).map(\.corners)
                    onAdd(selected)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(keptCount == 0)
            }
            .padding()
        }
        .frame(width: 760, height: 660)
    }

    private func handle(item i: Int, corner j: Int, fit: CGRect) -> some View {
        let col = palette[i % palette.count]
        return Circle()
            .fill(col)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .frame(width: 13, height: 13)
            .frame(width: 28, height: 28)          // generous hit target
            .contentShape(Circle())
            .position(point(items[i].corners[j], in: fit))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard fit.width > 0, fit.height > 0 else { return }
                        items[i].corners[j] = CGPoint(
                            x: min(max((value.location.x - fit.minX) / fit.width, 0), 1),
                            y: min(max((value.location.y - fit.minY) / fit.height, 0), 1))
                    }
            )
    }

    private func point(_ normalized: CGPoint, in fit: CGRect) -> CGPoint {
        CGPoint(x: fit.minX + normalized.x * fit.width,
                y: fit.minY + normalized.y * fit.height)
    }

    private func keepBinding(_ i: Int) -> Binding<Bool> {
        Binding(get: { items[i].keep }, set: { items[i].keep = $0 })
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
