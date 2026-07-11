import LumoraKit
import SwiftUI

/// The sidebar list of defined surfaces. Rows can be renamed inline by
/// double-clicking the name or via the context menu.
struct SurfaceListView: View {
    @EnvironmentObject var store: ProjectStore
    @State private var editingID: Surface.ID?
    @State private var editingLineID: LightLine.ID?
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        List {
            Section("Surfaces") {
                ForEach(store.surfaces) { surface in
                    row(for: surface)
                        .listRowBackground(surface.id == store.selectedID ? Color.accentColor.opacity(0.15) : nil)
                        .contentShape(Rectangle())
                        .onTapGesture { store.selectSurface(surface.id) }
                        .contextMenu {
                            Button("Rename") { beginEditing(surface.id) }
                            Button("Delete", role: .destructive) { store.delete(surface.id) }
                        }
                }
            }

            Section("Light Lines") {
                ForEach(store.lightLines) { line in
                    lineRow(for: line)
                        .listRowBackground(line.id == store.selectedLineID ? Color.accentColor.opacity(0.15) : nil)
                        .contentShape(Rectangle())
                        .onTapGesture { store.selectLine(line.id) }
                        .contextMenu {
                            Button("Rename") { beginEditingLine(line.id) }
                            Button("Delete", role: .destructive) { store.deleteLine(line.id) }
                        }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func row(for surface: Surface) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "square.on.square.dashed")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                if editingID == surface.id {
                    TextField("Name", text: nameBinding(surface.id))
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFieldFocused)
                        .onSubmit { editingID = nil }
                        .onExitCommand { editingID = nil }
                } else {
                    Text(surface.name)
                        .onTapGesture(count: 2) { beginEditing(surface.id) }
                    Text(surface.media.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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

    private func beginEditing(_ id: Surface.ID) {
        store.selectSurface(id)
        editingID = id
        DispatchQueue.main.async { nameFieldFocused = true }
    }

    /// A binding to a surface's name that writes back through the store.
    private func nameBinding(_ id: Surface.ID) -> Binding<String> {
        Binding(
            get: { store.surfaces.first { $0.id == id }?.name ?? "" },
            set: { newValue in store.update(id) { $0.name = newValue } }
        )
    }

    @ViewBuilder
    private func lineRow(for line: LightLine) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                if editingLineID == line.id {
                    TextField("Name", text: lineNameBinding(line.id))
                        .textFieldStyle(.roundedBorder)
                        .focused($nameFieldFocused)
                        .onSubmit { editingLineID = nil }
                        .onExitCommand { editingLineID = nil }
                } else {
                    Text(line.name)
                        .onTapGesture(count: 2) { beginEditingLine(line.id) }
                    Text("\(line.joints.count) joint\(line.joints.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                store.updateLine(line.id) { $0.isVisible.toggle() }
            } label: {
                Image(systemName: line.isVisible ? "eye" : "eye.slash")
                    .foregroundStyle(line.isVisible ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func beginEditingLine(_ id: LightLine.ID) {
        store.selectLine(id)
        editingLineID = id
        DispatchQueue.main.async { nameFieldFocused = true }
    }

    private func lineNameBinding(_ id: LightLine.ID) -> Binding<String> {
        Binding(
            get: { store.lightLines.first { $0.id == id }?.name ?? "" },
            set: { newValue in store.updateLine(id) { $0.name = newValue } }
        )
    }
}
