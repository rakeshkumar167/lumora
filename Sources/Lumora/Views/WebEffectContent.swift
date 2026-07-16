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
        // Required so bundled ES-module effect pages can `import` sibling
        // `file://` modules — WKWebView otherwise denies fetch()/import() of
        // file:// siblings as cross-origin, even within the loadFileURL
        // allowingReadAccessTo sandbox.
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
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

        func load(_ resource: String, into webView: WKWebView) {
            guard resource != currentResource else { return }
            currentResource = resource
            guard let url = WebEffect.url(forResource: resource) else {
                assertionFailure("Missing bundled web effect: \(resource).html")
                return
            }
            // Grant read access to the whole `Web` directory so the page can
            // load sibling vendored libraries (three.min.js, p5.min.js).
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
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
        default: return nil
        }
    }

    /// The bundled page's file URL under the copied `Web/` resource directory.
    static func url(forResource name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "html", subdirectory: "Web")
    }
}
