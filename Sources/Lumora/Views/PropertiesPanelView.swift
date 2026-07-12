import LumoraKit
import SwiftUI
import UniformTypeIdentifiers

/// Edits the selected surface: name, opacity, visibility, and media assignment.
struct PropertiesPanelView: View {
    @EnvironmentObject var store: ProjectStore

    var body: some View {
        Group {
            if let lineBinding = store.selectedLineBinding() {
                LightLineEditor(line: lineBinding)
            } else if let binding = store.selectedBinding() {
                editor(binding)
            } else {
                ContentUnavailableView(
                    "Nothing Selected",
                    systemImage: "square.dashed",
                    description: Text("Select or add a surface or light line to edit it.")
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
                Stepper(value: surface.zIndex, in: -999...999) {
                    Text("Layer (z-index): \(surface.wrappedValue.zIndex)")
                }
            }

            Section("Media") {
                MediaEditor(media: surface.media,
                            marquee: surface.marquee,
                            christmas: surface.christmasLights,
                            game: surface.gameOfLife,
                            leaves: surface.fallingLeaves,
                            treeImage: surface.christmasTreeImage)
            }
        }
        .formStyle(.grouped)
    }
}

/// Picks the media kind and its parameters for a surface.
private struct MediaEditor: View {
    @Binding var media: MediaAssignment
    @Binding var marquee: MarqueeConfig?
    @Binding var christmas: ChristmasLightsConfig?
    @Binding var game: GameOfLifeConfig?
    @Binding var leaves: FallingLeavesConfig?
    @Binding var treeImage: Int
    @ObservedObject private var weather = WeatherStore.shared

    /// String-light effects that take a bulb/sag config (the tree does not).
    private static let stringLightKinds: Set<EffectKind> =
        [.chasingLights, .multiColorLights, .twinklingLights, .warmBulbs]

    /// Raster image formats accepted by the image pickers. All decode via
    /// ImageIO / NSImage, so no conversion is needed (WebP, HEIF, BMP, AVIF).
    private static let imageTypes: [UTType] = {
        var t: [UTType] = [.png, .jpeg, .heic, .heif, .gif, .tiff, .bmp, .webP]
        if let avif = UTType("public.avif") { t.append(avif) }
        return t
    }()

    /// Curated fonts offered for the Marquee Text effect. Empty family name =
    /// the system monospaced default.
    private static let marqueeFonts: [(label: String, family: String)] = [
        ("Monospaced (default)", ""),
        ("Helvetica Neue", "Helvetica Neue"),
        ("Avenir Next", "Avenir Next"),
        ("Futura", "Futura"),
        ("Georgia", "Georgia"),
        ("Courier New", "Courier New"),
        ("Menlo", "Menlo"),
        ("Impact", "Impact"),
        ("Chalkboard SE", "Chalkboard SE"),
        ("Marker Felt", "Marker Felt"),
        ("Snell Roundhand", "Snell Roundhand"),
    ]

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
            if effectKind == .digitalClock || effectKind == .weatherWidget {
                Picker("City", selection: Binding(
                    get: { weather.selectedCity },
                    set: { weather.selectedCity = $0 }
                )) {
                    ForEach(Cities.all) { Text($0.name).tag($0) }
                }
            }
            if effectKind == .marqueeText {
                marqueeControls
            }
            if effectKind == .christmasTree {
                Picker("Tree", selection: $treeImage) {
                    Text("Classic").tag(0)
                    Text("Red & Green").tag(1)
                    Text("Blue & Gold").tag(2)
                }
            }
            if Self.stringLightKinds.contains(effectKind) {
                stringLightControls
            }
            if effectKind == .gameOfLife {
                gameOfLifeControls
            }
            if effectKind == .fallingLeaves {
                let cfg = leaves ?? FallingLeavesConfig()
                VStack(alignment: .leading) {
                    Text("Leaf Size: \(Int(cfg.leafScale * 100))%").font(.caption)
                    Slider(
                        value: Binding(
                            get: { cfg.leafScale },
                            set: { var c = cfg; c.leafScale = $0; leaves = c }
                        ),
                        in: 0.4...4.0
                    )
                }
            }
            if effectKind.usesColor {
                Text("Color").font(.caption).foregroundStyle(.secondary)
                colorControls(current: primary) { media = .effect(effectKind, $0, accent) }
            }
            if effectKind == .marqueeText {
                // Marquee's text color uses the primary "Color" swatch above,
                // unless Rainbow is on.
                let cfg = marquee ?? MarqueeConfig()
                if cfg.rainbow {
                    Text("Rainbow is on — palette color is ignored.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
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

        case .contourTrace(let cfg):
            Text("Images (traced in order)").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(cfg.images.enumerated()), id: \.offset) { idx, url in
                HStack {
                    Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button {
                        var c = cfg; c.images.remove(at: idx); media = .contourTrace(c)
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .disabled(cfg.images.count <= 1)
                }
            }
            Button("Add Image(s)…") { addContourImages(to: cfg) }
            Toggle("Rainbow", isOn: Binding(
                get: { cfg.rainbow },
                set: { var c = cfg; c.rainbow = $0; media = .contourTrace(c) }
            ))
            if !cfg.rainbow {
                Text("Pen Color").font(.caption).foregroundStyle(.secondary)
                colorControls(current: cfg.penColor) { var c = cfg; c.penColor = $0; media = .contourTrace(c) }
            }
            Toggle("Keep on after trace", isOn: Binding(
                get: { cfg.alwaysOn },
                set: { var c = cfg; c.alwaysOn = $0; media = .contourTrace(c) }
            ))
            if !cfg.alwaysOn {
                Stepper(
                    value: Binding(get: { cfg.holdSeconds },
                                   set: { var c = cfg; c.holdSeconds = $0; media = .contourTrace(c) }),
                    in: 1...600, step: 5
                ) {
                    Text("Hold \(Int(cfg.holdSeconds))s before repeat").font(.caption)
                }
            }
            Text("Trace Speed").font(.caption).foregroundStyle(.secondary)
            Slider(
                value: Binding(get: { cfg.speed }, set: { var c = cfg; c.speed = $0; media = .contourTrace(c) }),
                in: 0.05...4
            )
        }
    }

    /// Custom text, font, size, and rainbow controls for the Marquee Text effect.
    @ViewBuilder
    private var marqueeControls: some View {
        let cfg = marquee ?? MarqueeConfig()
        TextField("Text", text: Binding(
            get: { cfg.text },
            set: { var c = cfg; c.text = $0; marquee = c }
        ), prompt: Text("Surface name"))
        Picker("Font", selection: Binding(
            get: { cfg.fontName },
            set: { var c = cfg; c.fontName = $0; marquee = c }
        )) {
            ForEach(Self.marqueeFonts, id: \.family) { Text($0.label).tag($0.family) }
        }
        VStack(alignment: .leading) {
            Text("Font Size \(Int(cfg.fontSize))").font(.caption)
            Slider(value: Binding(
                get: { cfg.fontSize },
                set: { var c = cfg; c.fontSize = $0; marquee = c }
            ), in: 12...200)
        }
        Toggle("Rainbow", isOn: Binding(
            get: { cfg.rainbow },
            set: { var c = cfg; c.rainbow = $0; marquee = c }
        ))
    }

    /// Bulb-count and sag-count controls for the Christmas string-light effects.
    @ViewBuilder
    private var stringLightControls: some View {
        let cfg = christmas ?? ChristmasLightsConfig()
        VStack(alignment: .leading) {
            Text("Bulbs: \(cfg.bulbCount)").font(.caption)
            Slider(
                value: Binding(
                    get: { Double(cfg.bulbCount) },
                    set: { var c = cfg; c.bulbCount = Int($0.rounded()); christmas = c }
                ),
                in: 5...80, step: 1
            )
        }
        Stepper(
            value: Binding(
                get: { cfg.sagCount },
                set: { var c = cfg; c.sagCount = $0; christmas = c }
            ),
            in: 1...8
        ) {
            Text("Sags: \(cfg.sagCount)").font(.caption)
        }
        VStack(alignment: .leading) {
            Text("Bulb Size: \(Int(cfg.bulbScale * 100))%").font(.caption)
            Slider(
                value: Binding(
                    get: { cfg.bulbScale },
                    set: { var c = cfg; c.bulbScale = $0; christmas = c }
                ),
                in: 0.3...3.0
            )
        }
    }

    /// Playback-speed control for the Game of Life effect. (The pattern is
    /// pre-baked at a fixed grid, so cell size follows the surface.)
    @ViewBuilder
    private var gameOfLifeControls: some View {
        let cfg = game ?? GameOfLifeConfig()
        VStack(alignment: .leading) {
            Text("Speed: \(String(format: "%.1f", cfg.genPerSecond)) gen/s").font(.caption)
            Slider(
                value: Binding(
                    get: { cfg.genPerSecond },
                    set: { var c = cfg; c.genPerSecond = $0; game = c }
                ),
                in: 0.5...15
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 11), spacing: 4) {
            ForEach(RGBAColor.palette, id: \.self) { swatch in
                RoundedRectangle(cornerRadius: 3)
                    .fill(swatch.color)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3).stroke(
                            swatch == current ? Color.primary : Color.black.opacity(0.2),
                            lineWidth: swatch == current ? 2 : 1
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
        panel.allowedContentTypes = Self.imageTypes
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
        panel.allowedContentTypes = Self.imageTypes
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            media = .laserTrace(url, color, 1.0)
        }
    }

    private func chooseContourImage(keeping color: RGBAColor = .green) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.imageTypes
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            media = .contourTrace(ContourTraceConfig(images: panel.urls, penColor: color))
        }
    }

    private func addContourImages(to cfg: ContourTraceConfig) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.imageTypes
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            var c = cfg; c.images += panel.urls; media = .contourTrace(c)
        }
    }
}

/// Edits the selected light line: name, colors, thickness, glow, and timing.
private struct LightLineEditor: View {
    @Binding var line: LightLine

    var body: some View {
        Form {
            Section("Light Line") {
                TextField("Name", text: $line.name)
                Toggle("Visible", isOn: $line.isVisible)
                VStack(alignment: .leading) {
                    Text("Opacity \(Int(line.opacity * 100))%").font(.caption)
                    Slider(value: $line.opacity, in: 0...1)
                }
                LabeledContent("Joints", value: "\(line.joints.count)")
                LabeledContent("Source", value: line.sourceJointID == nil ? "None (right-click a joint)" : "Set")
            }

            Section("Appearance") {
                Text("Line Color").font(.caption).foregroundStyle(.secondary)
                colorControls(current: line.style.color) { line.style.color = $0 }
                Text("Glow / Tracer Color").font(.caption).foregroundStyle(.secondary)
                colorControls(current: line.style.glowColor) { line.style.glowColor = $0 }

                VStack(alignment: .leading) {
                    Text("Thickness \(String(format: "%.1f", line.style.thickness))").font(.caption)
                    Slider(value: $line.style.thickness, in: 1...10)
                }
                VStack(alignment: .leading) {
                    Text("Glow Radius \(Int(line.style.glowRadius))").font(.caption)
                    Slider(value: $line.style.glowRadius, in: 2...30)
                }
            }

            Section("Timing") {
                VStack(alignment: .leading) {
                    Text("Fill Duration \(String(format: "%.1f", line.style.fillDuration))s").font(.caption)
                    Slider(value: $line.style.fillDuration, in: 0.5...10)
                }
                VStack(alignment: .leading) {
                    Text("Hold Duration \(String(format: "%.1f", line.style.holdDuration))s").font(.caption)
                    Slider(value: $line.style.holdDuration, in: 0...5)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Preset swatches plus a full color picker (mirrors MediaEditor.colorControls).
    @ViewBuilder
    private func colorControls(current: RGBAColor, apply: @escaping (RGBAColor) -> Void) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 11), spacing: 4) {
            ForEach(RGBAColor.palette, id: \.self) { swatch in
                RoundedRectangle(cornerRadius: 3)
                    .fill(swatch.color)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3).stroke(
                            swatch == current ? Color.primary : Color.black.opacity(0.2),
                            lineWidth: swatch == current ? 2 : 1
                        )
                    )
                    .onTapGesture { apply(swatch) }
            }
        }
        ColorPicker(
            "Custom Color",
            selection: Binding(get: { current.color }, set: { apply(RGBAColor($0)) }),
            supportsOpacity: true
        )
    }
}
