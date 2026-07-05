import LumoraKit
import SwiftUI
import UniformTypeIdentifiers

/// Edits the selected surface: name, opacity, visibility, and media assignment.
struct PropertiesPanelView: View {
    @EnvironmentObject var store: ProjectStore

    var body: some View {
        Group {
            if let binding = store.selectedBinding() {
                editor(binding)
            } else {
                ContentUnavailableView(
                    "No Surface Selected",
                    systemImage: "square.dashed",
                    description: Text("Select or add a surface to edit its media and geometry.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func editor(_ surface: Binding<Surface>) -> some View {
        Form {
            Section("Surface") {
                TextField("Name", text: surface.name)
                Toggle("Visible", isOn: surface.isVisible)
                VStack(alignment: .leading) {
                    Text("Opacity \(Int(surface.wrappedValue.opacity * 100))%")
                        .font(.caption)
                    Slider(value: surface.opacity, in: 0...1)
                }
            }

            Section("Media") {
                MediaEditor(media: surface.media)
            }
        }
        .formStyle(.grouped)
    }
}

/// Picks the media kind and its parameters for a surface.
private struct MediaEditor: View {
    @Binding var media: MediaAssignment

    private enum Kind: String, CaseIterable, Identifiable {
        case none, color, effect, image, video
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    private var kind: Kind {
        switch media {
        case .none: return .none
        case .color: return .color
        case .effect: return .effect
        case .image: return .image
        case .video: return .video
        }
    }

    var body: some View {
        Picker("Type", selection: Binding(
            get: { kind },
            set: { setKind($0) }
        )) {
            ForEach(Kind.allCases) { Text($0.label).tag($0) }
        }

        switch media {
        case .none:
            EmptyView()

        case .color(let c):
            colorControls(current: c) { media = .color($0) }

        case .effect(let effectKind, let primary, let accent):
            Picker("Effect", selection: Binding(
                get: { effectKind },
                set: { media = .effect($0, primary, accent) }
            )) {
                ForEach(EffectKind.allCases) { Text($0.displayName).tag($0) }
            }
            if effectKind.usesColor {
                Text("Color").font(.caption).foregroundStyle(.secondary)
                colorControls(current: primary) { media = .effect(effectKind, $0, accent) }
            }
            if effectKind.usesAccent {
                Text("Accent Color").font(.caption).foregroundStyle(.secondary)
                colorControls(current: accent) { media = .effect(effectKind, primary, $0) }
            }

        case .image(let url):
            LabeledContent("File", value: url.lastPathComponent)
            Button("Choose Image…") { chooseImage() }

        case .video(let url):
            LabeledContent("File", value: url.lastPathComponent)
            Button("Choose Video…") { chooseVideo() }
        }
    }

    private func setKind(_ newKind: Kind) {
        switch newKind {
        case .none: media = .none
        case .color: media = .color(.teal)
        case .effect: media = .effect(.colorWash, .amber, .red)
        case .image: chooseImage()
        case .video: chooseVideo()
        }
    }

    /// Preset swatches plus a full color picker for any custom color.
    @ViewBuilder
    private func colorControls(current: RGBAColor, apply: @escaping (RGBAColor) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 28), spacing: 8)], spacing: 8) {
            ForEach(RGBAColor.palette, id: \.self) { swatch in
                Circle()
                    .fill(swatch.color)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle().stroke(
                            swatch == current ? Color.primary : Color.black.opacity(0.2),
                            lineWidth: swatch == current ? 2.5 : 1
                        )
                    )
                    .onTapGesture { apply(swatch) }
            }
        }

        ColorPicker(
            "Custom Color",
            selection: Binding(
                get: { current.color },
                set: { apply(RGBAColor($0)) }
            ),
            supportsOpacity: true
        )
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            media = .image(url)
        }
    }

    private func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .quickTimeMovie, .mpeg4Movie]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            media = .video(url)
        }
    }
}
