import Foundation
import WebKit

/// Serves bundled effect pages (and their sibling ES-module assets) over the
/// custom `lumora-effect://` scheme instead of `file://`. This keeps the
/// WKWebView file:// sandbox intact while still letting a page `import` sibling
/// modules: because every request shares one custom-scheme origin, module
/// imports are same-origin and WKWebView permits them — no
/// `allowUniversalAccessFromFileURLs` needed.
///
/// URLs are shaped `lumora-effect://local/<path>` and map onto files under a
/// single `root` directory (e.g. `lumora-effect://local/_smoketest.html` →
/// `<root>/_smoketest.html`, `./lib/three/three.module.js` →
/// `lumora-effect://local/lib/three/three.module.js`). Paths that escape the
/// root (traversal via `..`) or don't exist return an HTTP 404.
final class WebEffectSchemeHandler: NSObject, WKURLSchemeHandler {
    /// The scheme this handler serves. Register with
    /// `config.setURLSchemeHandler(_, forURLScheme: WebEffectSchemeHandler.scheme)`.
    static let scheme = "lumora-effect"

    /// Directory whose files are exposed under the scheme.
    private let root: URL

    /// Tasks currently in flight, so `stop(_:)` can suppress messaging a
    /// cancelled task. Keyed by object identity.
    private var activeTasks = Set<ObjectIdentifier>()

    init(root: URL) {
        self.root = root.standardizedFileURL
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        activeTasks.insert(id)

        guard let requestURL = urlSchemeTask.request.url,
              let fileURL = resolvedFileURL(for: requestURL),
              let data = try? Data(contentsOf: fileURL) else {
            respondNotFound(urlSchemeTask, requestURL: urlSchemeTask.request.url)
            return
        }

        guard activeTasks.contains(id) else { return }

        let response = HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.mimeType(for: fileURL.pathExtension),
                "Content-Length": String(data.count),
            ]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
        activeTasks.remove(id)
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        activeTasks.remove(ObjectIdentifier(urlSchemeTask))
    }

    /// Resolves a request URL's path against `root`, percent-decoding it and
    /// rejecting anything that escapes the root directory. Returns `nil` for
    /// out-of-bounds paths so the caller can 404.
    private func resolvedFileURL(for url: URL) -> URL? {
        // Use `url.path` (already percent-decoded) so `%20` etc. map correctly.
        var path = url.path
        if path.hasPrefix("/") { path.removeFirst() }
        let candidate = root.appendingPathComponent(path).standardizedFileURL
        // Reject traversal: the resolved path must stay within root.
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path == root.path || candidate.path.hasPrefix(rootPath) else {
            return nil
        }
        return candidate
    }

    private func respondNotFound(_ task: WKURLSchemeTask, requestURL: URL?) {
        let id = ObjectIdentifier(task)
        guard activeTasks.contains(id) else { return }
        let url = requestURL ?? URL(string: "\(Self.scheme)://local/")!
        let response = HTTPURLResponse(
            url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        task.didReceive(response)
        task.didFinish()
        activeTasks.remove(id)
    }

    /// Correct MIME per extension. A correct `text/javascript` for `.js`/`.mjs`
    /// is mandatory — WKWebView refuses to execute modules served with the
    /// wrong type.
    static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "js", "mjs": return "text/javascript"
        case "html": return "text/html"
        case "css": return "text/css"
        case "json": return "application/json"
        case "webp": return "image/webp"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        default: return "application/octet-stream"
        }
    }
}
