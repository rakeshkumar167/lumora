import LumoraKit
import SwiftUI

/// The sidebar list of defined surfaces.
struct SurfaceListView: View {
    @EnvironmentObject var store: ProjectStore

    var body: some View {
        List(selection: $store.selectedID) {
            Section("Surfaces") {
                ForEach(store.surfaces) { surface in
                    row(for: surface)
                        .tag(surface.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                store.delete(surface.id)
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(for surface: Surface) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "square.on.square.dashed")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(surface.name)
                Text(surface.media.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                store.update(surface.id) { $0.isVisible.toggle() }
            } label: {
                Image(systemName: surface.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(surface.isVisible ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
