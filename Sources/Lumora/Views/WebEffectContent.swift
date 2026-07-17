import LumoraKit
import SwiftUI
import WebKit

/// Hosts a curated, bundled JS/WebGL effect page inside a `WKWebView`. The
/// parent `SurfaceContentView` perspective-warps it via `.projectionEffect`
/// exactly like `VideoContent`/`ImageContent`, so web effects align on angled
/// surface quads. The page self-animates via `requestAnimationFrame`; Lumora's
/// global clock is not bridged in (a future add).
///
/// Each web effect is a fixed page bundled under `Sources/Lumora/Web/` (copied
/// verbatim so a page can reference its sibling `lib/*.js`). The background is
/// transparent so the effect overlays other surfaces.
struct WebEffectContent: NSViewRepresentable {
    /// The bundled page's base name (no extension), e.g. "plasma".
    let resource: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Serve bundled pages + their sibling ES modules over the custom
        // `lumora-effect://` scheme. One shared origin keeps module imports
        // same-origin (so WKWebView permits them) while leaving the file://
        // sandbox intact.
        if let handler = context.coordinator.schemeHandler {
            config.setURLSchemeHandler(handler, forURLScheme: WebEffectSchemeHandler.scheme)
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        // Transparent background so the effect overlays other surfaces.
        webView.setValue(false, forKey: "drawsBackground")
        webView.wantsLayer = true
        webView.layer?.backgroundColor = .clear
        // Not interactive — it's a display surface.
        webView.setValue(false, forKey: "allowsBackForwardNavigationGestures")
        context.coordinator.load(resource, into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(resource, into: webView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Tracks the currently-loaded resource so redraws/resizes don't reload the
    /// page (mirrors `PlayerContainerView.load`'s `url != currentURL` guard).
    final class Coordinator {
        private var currentResource: String?

        /// Serves the bundled `Web/` directory over `lumora-effect://`. Created
        /// once from the bundle's Web root; `nil` only if the bundle is missing
        /// its Web resources (which would fail the load anyway).
        lazy var schemeHandler: WebEffectSchemeHandler? = {
            guard let webRoot = WebEffect.webRootURL else { return nil }
            return WebEffectSchemeHandler(root: webRoot)
        }()

        func load(_ resource: String, into webView: WKWebView) {
            guard resource != currentResource else { return }
            currentResource = resource
            guard WebEffect.url(forResource: resource) != nil else {
                assertionFailure("Missing bundled web effect: \(resource).html")
                return
            }
            // Load via the custom scheme so sibling ES-module imports resolve
            // same-origin against the WebEffectSchemeHandler's Web root.
            guard let url = URL(string: "\(WebEffectSchemeHandler.scheme)://local/\(resource).html") else { return }
            webView.load(URLRequest(url: url))
        }
    }
}

/// Maps a web-category `EffectKind` to its bundled page resource name, and
/// resolves that page's file URL in the app bundle. Kept in the app layer (not
/// `LumoraKit`) so the pure core stays free of bundle/resource concerns.
enum WebEffect {
    /// The bundled page base name for a web-category effect kind, or `nil` if
    /// the kind isn't a web effect.
    static func resource(for kind: EffectKind) -> String? {
        switch kind {
        case .webPlasma: return "plasma"
        case .webParticles3D: return "particles3d"
        case .webFlow: return "flow"
        case .webZoomingSpiral: return "zoomingSpiral"
        case .webSpaceGlobe: return "spaceGlobe"
        case .webSnowfall: return "snowfall"
        case .webStarfall: return "starfall"
        case .webCoralBlooms: return "coralBlooms"
        case .webStorm: return "storm"
        case .webMorphingBall: return "morphingBall"
        case .webLiveClouds: return "liveClouds"
        case .webDiscoBalls: return "discoBalls"
        case .webBlackHole: return "blackHole"
        default: return nil
        }
    }

    /// The bundled page's file URL under the copied `Web/` resource directory.
    static func url(forResource name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Web")
    }

    /// The bundled `Web/` resource directory, used as the scheme handler's root
    /// so it can serve every page plus its sibling `lib/*` modules. Derived from
    /// the smoke-test page's URL (any bundled page's parent is the Web root).
    static var webRootURL: URL? {
        url(forResource: "_smoketest")?.deletingLastPathComponent()
    }
}
