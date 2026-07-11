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

                Picker("Shape", selection: Binding(
                    get: { surface.wrappedValue.shape },
                    set: { store.setShape(surface.wrappedValue.id, to: $0) }
                )) {
                    ForEach(SurfaceShape.allCases) { Text($0.displayName).tag($0) }
                }

                if surface.wrappedValue.shape == .polygon {
                    Stepper(
                        value: Binding(
                            get: { surface.wrappedValue.points.count },
                            set: { store.setPolygonSides(surface.wrappedValue.id, $0) }
                        ),
                        in: 3...12
                    ) {
                        Text("Sides: \(surface.wrappedValue.points.count)")
                    }
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Rotation \(Int((surface.wrappedValue.rotation * 180 / .pi).rounded()))°")
                            .font(.caption)
                        Spacer()
                        Button("Reset") { surface.rotation.wrappedValue = 0 }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                    Slider(
                        value: Binding(
                            get: { surface.wrappedValue.rotation * 180 / .pi },
                            set: { surface.rotation.wrappedValue = $0 * .pi / 180 }
                        ),
                        in: -180...180
                    )
                }

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
    @ObservedObject private var weather = WeatherStore.shared

    private enum Kind: String, CaseIterable, Identifiable {
        case none, color, effect, image, video, laserTrace, contourTrace
        var id: String { rawValue }
        var label: String {
            switch self {
            case .laserTrace: return "Laser Trace"
            case .contourTrace: return "Contour Trace"
            default: return rawValue.capitalized
            }
        }
    }

    private var kind: Kind {
        switch media {
        case .none: return .none
        case .color: return .color
        case .effect: return .effect
        case .image: return .image
        case .video: return .video
        case .laserTrace: return .laserTrace
        case .contourTrace: return .contourTrace
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
                ForEach(EffectCategory.allCases) { category in
                    Section(category.displayName) {
                        ForEach(category.effects) { Text($0.displayName).tag($0) }
                    }
                }
            }
            if effectKind == .digitalClock {
                Picker("City", selection: Binding(
                    get: { weather.selectedCity },
                    set: { weather.selectedCity = $0 }
                )) {
                    ForEach(Cities.all) { Text($0.name).tag($0) }
                }
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

        case .laserTrace(let url, let laserColor, let speed):
            LabeledContent("File", value: url.lastPathComponent)
            Button("Choose Image…") { chooseLaserImage(keeping: laserColor) }
            Text("Laser Color").font(.caption).foregroundStyle(.secondary)
            colorControls(current: laserColor) { media = .laserTrace(url, $0, speed) }
            Text("Trace Speed").font(.caption).foregroundStyle(.secondary)
            Slider(
                value: Binding(get: { speed }, set: { media = .laserTrace(url, laserColor, $0) }),
                in: 0.05...4
            )

        case .contourTrace(let url, let penColor, let speed):
            LabeledContent("File", value: url.lastPathComponent)
            Button("Choose Image…") { chooseContourImage(keeping: penColor) }
            Text("Pen Color").font(.caption).foregroundStyle(.secondary)
            colorControls(current: penColor) { media = .contourTrace(url, $0, speed) }
            Text("Trace Speed").font(.caption).foregroundStyle(.secondary)
            Slider(
                value: Binding(get: { speed }, set: { media = .contourTrace(url, penColor, $0) }),
                in: 0.05...4
            )
        }
    }

    private func setKind(_ newKind: Kind) {
        switch newKind {
        case .none: media = .none
        case .color: media = .color(.teal)
        case .effect: media = .effect(.colorWash, .amber, .red)
        case .image: chooseImage()
        case .video: chooseVideo()
        case .laserTrace: chooseLaserImage()
        case .contourTrace: chooseContourImage()
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

    private func chooseLaserImage(keeping color: RGBAColor = .green) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            media = .laserTrace(url, color, 1.0)
        }
    }

    private func chooseContourImage(keeping color: RGBAColor = .green) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            media = .contourTrace(url, color, 1.0)
        }
    }
}
