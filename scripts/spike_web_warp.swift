// Run: swift scripts/spike_web_warp.swift   (launch in background, then screencapture)
// WARP SPIKE for WebGL/JS effects. Shows the bundled plasma.html in a WKWebView
// under a hard-coded perspective .projectionEffect (mimicking
// SurfaceContentView.quadBody), centered on screen, and stays open ~15s so an
// external `screencapture` can grab it. If the plasma appears keystoned in the
// capture, the live '.projectionEffect' warp path works on a WKWebView
// (decision-ladder step 1) — no snapshot fallback needed.
import AppKit
import SwiftUI
import WebKit

let htmlPath = FileManager.default.currentDirectoryPath + "/Sources/Lumora/Web/plasma.html"
let htmlURL = URL(fileURLWithPath: htmlPath)

struct WebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: .zero)
        wv.setValue(false, forKey: "drawsBackground")
        wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        return wv
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

func warp() -> ProjectionTransform {
    var t = CATransform3DIdentity
    t.m34 = -1.0 / 700.0
    t = CATransform3DRotate(t, .pi / 4.5, 0, 1, 0)   // strong Y rotation → keystone
    t = CATransform3DRotate(t, .pi / 14, 1, 0, 0)
    return ProjectionTransform(t)
}

struct SpikeView: View {
    var body: some View {
        ZStack {
            // A reference frame (un-warped border) + the warped web view inside,
            // so the keystone is obvious relative to the straight window edges.
            Color(white: 0.08)
            WebView()
                .frame(width: 460, height: 320)
                .projectionEffect(warp())
        }
        .frame(width: 760, height: 560)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                      styleMask: [.titled], backing: .buffered, defer: false)
window.title = "Web Warp Spike"
window.contentView = NSHostingView(rootView: SpikeView())
window.center()
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

DispatchQueue.main.asyncAfter(deadline: .now() + 15) { exit(0) }
app.run()
