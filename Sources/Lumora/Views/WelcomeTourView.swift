import AppKit
import LumoraKit
import SwiftUI

/// First-launch welcome tour: a paged sheet that walks through each area of the
/// workspace using real screenshots (`Resources/tour-*.png`, retaken with
/// `scripts/capture_tour_screenshots.swift`) and, for effects, live renders.
struct WelcomeTourView: View {
    /// UserDefaults key; set once the tour has been closed (finished or skipped).
    static let seenKey = "hasSeenWelcomeTour"

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0

    private let pages = TourPage.all

    var body: some View {
        let page = pages[index]
        VStack(spacing: 0) {
            artwork(page.artwork)
                .frame(height: 330)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor))
                .clipped()

            VStack(spacing: 8) {
                Label(page.title, systemImage: page.icon)
                    .font(.title2.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                Text(page.body)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .frame(maxHeight: .infinity, alignment: .top)

            footer
        }
        .frame(width: 640, height: 530)
        .id(index)
        .transition(.opacity)
    }

    private var footer: some View {
        HStack {
            Button("Skip Tour") { dismiss() }
                .buttonStyle(.link)
                .opacity(index == pages.count - 1 ? 0 : 1)
                .keyboardShortcut(.cancelAction)

            Spacer()

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { i in
                    Circle()
                        .fill(i == index ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if index > 0 {
                    Button("Back") { withAnimation { index -= 1 } }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                }
                if index < pages.count - 1 {
                    Button("Next") { withAnimation { index += 1 } }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Get Started") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.bar)
    }

    @ViewBuilder
    private func artwork(_ art: TourPage.Artwork) -> some View {
        switch art {
        case .welcome:
            ZStack {
                LiveEffectCycle(kinds: [.aurora], showsName: false)
                if let icon = AppAssets.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
                }
            }
        case .screenshots(let names):
            VStack(spacing: 14) {
                ForEach(names, id: \.self) { name in
                    if let img = TourPage.image(name) {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12)))
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
                    }
                }
            }
            .padding(22)
        case .effects:
            HStack(spacing: 18) {
                if let img = TourPage.image("tour-media") {
                    Image(nsImage: img)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12)))
                }
                Image(systemName: "arrow.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                LiveEffectCycle(kinds: [.kaleidoscope, .fireworks, .hauntedNight, .diyaLamps, .webFlowers, .webLiquid], showsName: true)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            }
            .padding(22)
        }
    }
}

/// Plays real Lumora effects, cross-fading to the next one every few seconds.
private struct LiveEffectCycle: View {
    let kinds: [EffectKind]
    let showsName: Bool
    private let secondsPerEffect = 5.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let i = Int(t / secondsPerEffect) % kinds.count
            let kind = kinds[i]
            EffectView(kind: kind, color: .cyan, accent: .magenta, time: t)
                .background(Color.black)
                .id(kind)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.6), value: kind)
                .overlay(alignment: .bottomLeading) {
                    if showsName {
                        Text(kind.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.55), in: Capsule())
                            .padding(10)
                    }
                }
        }
    }
}

private struct TourPage {
    enum Artwork {
        case welcome
        case screenshots([String])
        case effects
    }

    let icon: String
    let title: String
    let body: String
    let artwork: Artwork

    static func image(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    static let all: [TourPage] = [
        TourPage(icon: "sparkles", title: "Welcome to Lumora",
                 body: "Map your space. Play your vision. Draw surfaces over the walls and objects in your room, choose what plays on each one, then send it to your projector.",
                 artwork: .welcome),
        TourPage(icon: "square.on.square.dashed", title: "Surfaces & Tools",
                 body: "Click Add Surface to drop a new shape on the canvas. Arrow: drag the corner handles to warp it onto a real object, or the knob to rotate. Hand: drag a surface to move it. Pen: click to draw glowing light lines. Add Line starts a new one.",
                 artwork: .screenshots(["tour-canvas"])),
        TourPage(icon: "viewfinder.rectangular", title: "Detect Surfaces",
                 body: "Lumora projects four corner markers. Photograph your room with all of them visible, choose the photo, and keep the flat surfaces it finds. This is experimental and works best on large, well-lit surfaces.",
                 artwork: .screenshots(["tour-toolbar"])),
        TourPage(icon: "slider.horizontal.3", title: "Properties",
                 body: "The left panel edits whatever is selected: name, shape (quad, polygon or ellipse), rotation, visibility, opacity, and layer order. Below that, Media sets what plays: a solid color, an effect, an image, or a video.",
                 artwork: .screenshots(["tour-properties"])),
        TourPage(icon: "wand.and.stars", title: "Choose What Plays",
                 body: "Set Type to Effect, then pick from 130+ effects grouped into categories like Particles & Nature, Clocks, Diwali, and WebGL. Every effect has its own controls (colors, speed, rainbow, audio-reactive), and the surface updates live as you adjust them.",
                 artwork: .effects),
        TourPage(icon: "list.bullet", title: "Surfaces List",
                 body: "Every surface and light line in the scene appears on the right. Click to select, double-click to rename, and use the eye to hide or show one.",
                 artwork: .screenshots(["tour-surfaces"])),
        TourPage(icon: "film.stack", title: "Scenes",
                 body: "Build several scenes and they play in sequence. Click + to add one, set how long each plays, reorder with the arrows, and press ▶ to preview the whole sequence in the editor.",
                 artwork: .screenshots(["tour-scenes-list", "tour-scenes-controls"])),
        TourPage(icon: "play.rectangle.fill", title: "Project & Save",
                 body: "Project (⌘P) sends everything full-screen to your second display or projector. Click Stop to end. Save your work as a .lumora file with ⌘S and reopen it with ⌘O. You can replay this tour any time from Help → Welcome Tour.",
                 artwork: .screenshots(["tour-project", "tour-saveopen"])),
    ]
}
