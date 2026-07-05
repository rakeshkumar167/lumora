import AppKit
import LumoraKit
import SwiftUI
import UniformTypeIdentifiers

/// The main workspace: surface list | room canvas | properties panel.
struct WorkspaceView: View {
    @EnvironmentObject var store: ProjectStore
    @Environment(\.openWindow) private var openWindow

    private var lumoraType: UTType { UTType(filenameExtension: "lumora") ?? .json }

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
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor))
            }
            .frame(minWidth: 500)

            PropertiesPanelView()
                .frame(minWidth: 250, idealWidth: 270, maxWidth: 320)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Pointer", selection: $store.tool) {
                Image(systemName: "cursorarrow").tag(EditTool.arrow)
                Image(systemName: "hand.raised.fill").tag(EditTool.hand)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Arrow: drag corners to warp the surface. Hand: drag inside to move the whole surface.")

            Divider().frame(height: 16)

            Button {
                store.addSurface()
            } label: {
                Label("Add Surface", systemImage: "plus.square.on.square")
            }

            Divider().frame(height: 16)

            Button {
                openProject()
            } label: {
                Label("Open", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button {
                saveProject()
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(store.surfaces.isEmpty)

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

    // MARK: - Save / Open

    /// Write the current surfaces to a `.lumora` JSON document.
    private func saveProject() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [lumoraType]
        panel.nameFieldStringValue = "Untitled.lumora"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(store.makeProject()).write(to: url)
        } catch {
            presentError("Could not save project", error)
        }
    }

    /// Load surfaces from a `.lumora` JSON document, replacing the current set.
    private func openProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [lumoraType]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let project = try JSONDecoder().decode(Project.self, from: data)
            store.load(project)
        } catch {
            presentError("Could not open project", error)
        }
    }

    private func presentError(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
