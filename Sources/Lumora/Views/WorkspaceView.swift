import SwiftUI

/// The main workspace: surface list | room canvas | properties panel.
struct WorkspaceView: View {
    @EnvironmentObject var store: ProjectStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HSplitView {
            SurfaceListView()
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

            VStack(spacing: 0) {
                toolbar
                Divider()
                ScrollView([.horizontal, .vertical]) {
                    RoomCanvasView()
                        .padding(28)
                }
                .background(Color(nsColor: .underPageBackgroundColor))
            }
            .frame(minWidth: 500)

            PropertiesPanelView()
                .frame(minWidth: 250, idealWidth: 270, maxWidth: 320)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Button {
                store.addSurface()
            } label: {
                Label("Add Surface", systemImage: "plus.square.on.square")
            }

            Spacer()

            Text("\(store.surfaces.count) surface\(store.surfaces.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                openWindow(id: "projection")
            } label: {
                Label("Project", systemImage: "play.rectangle.fill")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("p", modifiers: [.command])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
