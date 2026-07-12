import AppKit
import LumoraKit
import SwiftUI
import UniformTypeIdentifiers

/// The main workspace: surface list | room canvas | properties panel.
struct WorkspaceView: View {
    @EnvironmentObject var store: ProjectStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var reviewImage: NSImage?
    @State private var reviewQuads: [DetectedQuad] = []
    @State private var showReview = false
    @State private var detecting = false

    private var lumoraType: UTType { UTType(filenameExtension: "lumora") ?? .json }

    var body: some View {
        HSplitView {
            PropertiesPanelView()
                .frame(minWidth: 250, idealWidth: 270, maxWidth: 320)

            VStack(spacing: 0) {
                toolbar
                Divider()
                RoomCanvasView()
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .underPageBackgroundColor))
            }
            .frame(minWidth: 360)

            SurfaceListView()
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
        }
        .sheet(isPresented: $showReview) {
            if let img = reviewImage {
                SurfaceDetectionReviewView(
                    image: img,
                    quads: reviewQuads,
                    onAdd: { corners in
                        store.addDetectedSurfaces(corners)
                        showReview = false
                    },
                    onCancel: { showReview = false }
                )
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Pointer", selection: $store.tool) {
                Image(systemName: "cursorarrow").tag(EditTool.arrow)
                Image(systemName: "hand.raised.fill").tag(EditTool.hand)
                Image(systemName: "pencil.line").tag(EditTool.pen)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Arrow: warp surface corners. Hand: move a surface. Pen: click to drop/connect light-line joints.")

            Divider().frame(height: 16)

            Button {
                store.addSurface()
            } label: {
                Label("Add Surface", systemImage: "plus.square.on.square")
            }

            Button {
                store.addLine()
            } label: {
                Label("Add Line", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            }

            Button {
                detectSurfaces()
            } label: {
                Label("Detect Surfaces", systemImage: "viewfinder.rectangular")
            }
            .disabled(detecting)
            .help("Import a room photo and auto-detect large flat surfaces as editable quads.")

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
                if store.projecting {
                    dismissWindow(id: "projection")
                } else {
                    openWindow(id: "projection")
                }
            } label: {
                Label(store.projecting ? "Stop" : "Project",
                      systemImage: store.projecting ? "stop.rectangle.fill" : "play.rectangle.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(store.projecting ? .red : .accentColor)
            .keyboardShortcut("p", modifiers: [.command])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Pick a room photo, run detection off the main thread, then present the
    /// keep/discard review sheet.
    private func detectSurfaces() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let nsImage = NSImage(contentsOf: url),
              let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        detecting = true
        Task {
            let quads = SurfaceDetector.detect(in: cg)
            await MainActor.run {
                reviewImage = nsImage
                reviewQuads = quads
                detecting = false
                showReview = true
            }
        }
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
