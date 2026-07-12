import SwiftUI

/// In-app help shown from the Help menu. A concise, scrollable overview of the
/// workspace and how to use it.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                section("Getting started", [
                    ("square.on.square.dashed", "Add a surface", "Click Add Surface, then drag its corners (Arrow tool) to match a wall, screen, or object in your room."),
                    ("viewfinder.rectangular", "Detect surfaces", "Import a room photo and Lumora proposes large flat quads automatically — keep the ones you want and they drop onto the canvas as editable surfaces."),
                    ("play.rectangle.fill", "Project", "Sends the composition full-screen to a second display or projector. Click again to stop; closing the editor also stops projection."),
                ])

                section("Tools", [
                    ("cursorarrow", "Arrow", "Warp a surface by dragging its corner handles; drag the knob to rotate."),
                    ("hand.raised.fill", "Hand", "Drag anywhere inside a surface to move the whole thing."),
                    ("pencil.line", "Pen", "Click to drop and connect light-line joints."),
                ])

                section("Panels", [
                    ("slider.horizontal.3", "Properties (left)", "Edit the selected surface: shape, rotation, opacity, layer order (z-index), and its media — a solid color, a generative effect, an image, or video."),
                    ("list.bullet", "Surfaces (right)", "Every surface in the scene. Select, rename, and toggle visibility here."),
                ])

                section("Effects & customization", [
                    ("sparkles", "Effects", "Pick from grouped categories. Most take a primary and accent color."),
                    ("textformat", "Marquee Text", "Set custom text, font, size, and an optional rainbow sweep."),
                    ("lightbulb.fill", "Christmas string lights", "Control the number of bulbs, the number of sags, and bulb size; they stay pinned to the top of the surface."),
                    ("square.grid.3x3", "Canvas grid", "A faint alignment grid helps you line things up — it is never sent to the projector."),
                ])

                Text("Tip: surfaces and light lines are saved in a .lumora file via ⌘S, and reopened with ⌘O.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 460, minHeight: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if let icon = AppAssets.icon {
                    Image(nsImage: icon).resizable().frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lumora Help").font(.title.bold())
                    Text("Map your space. Play your vision.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func section(_ title: String, _ rows: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .kerning(0.8)
            ForEach(rows, id: \.1) { icon, name, detail in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundStyle(.tint)
                        .frame(width: 22, alignment: .center)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.body.weight(.medium))
                        Text(detail).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}
