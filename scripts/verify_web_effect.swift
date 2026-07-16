// Run: swift scripts/verify_web_effect.swift <page-basename>   (e.g. particles3d)
// Loads a bundled web-effect page (Sources/Lumora/Web/<name>.html) into an
// offscreen WKWebView, lets its animation loop run, and captures two snapshots
// a beat apart via WKWebView.takeSnapshot. Asserts the page renders non-blank
// and animates (frames differ over time). Verifies the web-effect *content*;
// the perspective warp is verified separately by scripts/spike_web_warp.swift.
import AppKit
import WebKit

let name = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "plasma"
let htmlPath = FileManager.default.currentDirectoryPath + "/Sources/Lumora/Web/\(name).html"
guard FileManager.default.fileExists(atPath: htmlPath) else { print("FAIL: missing \(htmlPath)"); exit(1) }
let htmlURL = URL(fileURLWithPath: htmlPath)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let frame = NSRect(x: 0, y: 0, width: 640, height: 440)
let webView = WKWebView(frame: frame)
let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.contentView = webView
window.orderBack(nil)

func snapshot(_ done: @escaping (NSImage?) -> Void) {
    let cfg = WKSnapshotConfiguration(); cfg.rect = frame
    webView.takeSnapshot(with: cfg) { image, error in
        if let error = error { print("snapshot error: \(error)") }
        done(image)
    }
}
func stats(_ image: NSImage) -> (lit: Int, fp: [Int], varr: Double) {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return (0, [], 0) }
    var lit = 0; var fp: [Int] = []
    for y in stride(from: 0, to: rep.pixelsHigh, by: 8) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 8) {
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            let lum = 0.299*c.redComponent + 0.587*c.greenComponent + 0.114*c.blueComponent
            if lum > 0.05 { lit += 1 }
            fp.append(Int(lum * 255))
        }
    }
    let mean = fp.isEmpty ? 0 : Double(fp.reduce(0, +)) / Double(fp.count)
    let varr = fp.isEmpty ? 0 : fp.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / Double(fp.count)
    return (lit, fp, varr)
}
func diffCount(_ a: [Int], _ b: [Int]) -> Int {
    guard a.count == b.count else { return max(a.count, b.count) }
    return zip(a, b).reduce(0) { $0 + (abs($1.0 - $1.1) > 6 ? 1 : 0) }
}

final class Nav: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            snapshot { img0 in
                guard let img0 = img0 else { print("FAIL: no first snapshot"); exit(1) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    snapshot { img1 in
                        guard let img1 = img1 else { print("FAIL: no second snapshot"); exit(1) }
                        let s0 = stats(img0), s1 = stats(img1)
                        for (img, p) in [(img0, "/tmp/web_\(name)_t0.png"), (img1, "/tmp/web_\(name)_t1.png")] {
                            if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                               let png = rep.representation(using: .png, properties: [:]) {
                                try? png.write(to: URL(fileURLWithPath: p)); print("wrote \(p) (lit=\(stats(img).lit))")
                            }
                        }
                        precondition(s0.lit > 0 || s1.lit > 0, "\(name) should render non-blank")
                        let d = diffCount(s0.fp, s1.fp)
                        precondition(d > 0, "\(name) should animate (frames differ over time)")
                        print("PASS: \(name) renders (lit=\(s0.lit)→\(s1.lit), variance=\(Int(s1.varr))) and animates (diff=\(d))")
                        exit(0)
                    }
                }
            }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("FAIL: navigation error \(error)"); exit(1)
    }
}
let nav = Nav()
webView.navigationDelegate = nav
webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
DispatchQueue.main.asyncAfter(deadline: .now() + 12) { print("FAIL: timed out"); exit(1) }
app.run()
