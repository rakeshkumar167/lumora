import AppKit
import LumoraKit
import SwiftUI

/// Sheet that previews auto-detected surfaces on the room photo and lets the
/// user keep/discard each — and drag corner handles to fix up the detected
/// outline — before adding them to the canvas.
struct SurfaceDetectionReviewView: View {
    let image: NSImage
    let quads: [DetectedQuad]
    let onAdd: ([[CGPoint]]) -> Void
    let onCancel: () -> Void

    @State private var keep: [Bool]
    /// Editable copies of the detected corners (normalized, top-left origin).
    @State private var corners: [[CGPoint]]

    init(image: NSImage, quads: [DetectedQuad],
         onAdd: @escaping ([[CGPoint]]) -> Void, onCancel: @escaping () -> Void) {
        self.image = image
        self.quads = quads
        self.onAdd = onAdd
        self.onCancel = onCancel
        _keep = State(initialValue: Array(repeating: true, count: quads.count))
        _corners = State(initialValue: quads.map(\.corners))
    }

    private let palette: [Color] = [.red, .green, .blue, .orange, .purple, .teal, .yellow, .pink]
    private var keptCount: Int { keep.filter { $0 }.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(quads.isEmpty ? "No surfaces detected"
                     : "Detected \(quads.count) surface\(quads.count == 1 ? "" : "s")")
                    .font(.headline)
                if !quads.isEmpty {
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
                        for (i, quad) in corners.enumerated() where i < keep.count && keep[i] {
                            let col = palette[i % palette.count]
                            let pts = quad.map { point($0, in: fit) }
                            var path = Path()
                            path.move(to: pts[0]); for p in pts.dropFirst() { path.addLine(to: p) }; path.closeSubpath()
                            ctx.fill(path, with: .color(col.opacity(0.16)))
                            ctx.stroke(path, with: .color(col), lineWidth: 3)
                        }
                    }
                    ForEach(corners.indices, id: \.self) { i in
                        if i < keep.count && keep[i] {
                            ForEach(corners[i].indices, id: \.self) { j in
                                handle(quad: i, corner: j, fit: fit)
                            }
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
                    let selected = corners.enumerated()
                        .filter { $0.offset < keep.count && keep[$0.offset] }
                        .map { $0.element }
                    onAdd(selected)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(keptCount == 0)
            }
            .padding()
        }
        .frame(width: 760, height: 660)
    }

    private func handle(quad i: Int, corner j: Int, fit: CGRect) -> some View {
        let col = palette[i % palette.count]
        return Circle()
            .fill(col)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .frame(width: 13, height: 13)
            .frame(width: 28, height: 28)          // generous hit target
            .contentShape(Circle())
            .position(point(corners[i][j], in: fit))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard fit.width > 0, fit.height > 0 else { return }
                        corners[i][j] = CGPoint(
                            x: min(max((value.location.x - fit.minX) / fit.width, 0), 1),
                            y: min(max((value.location.y - fit.minY) / fit.height, 0), 1))
                    }
            )
    }

    private func point(_ normalized: CGPoint, in fit: CGRect) -> CGPoint {
        CGPoint(x: fit.minX + normalized.x * fit.width,
                y: fit.minY + normalized.y * fit.height)
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
