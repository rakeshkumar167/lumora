import AVFoundation
import AppKit
import SwiftUI

/// A looping, muted video surface. Hosted as an `AVPlayerLayer`; the parent
/// `SurfaceContentView` perspective-warps it via `.projectionEffect`.
struct VideoContent: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.load(url: url)
        return view
    }

    func updateNSView(_ nsView: PlayerContainerView, context: Context) {
        nsView.load(url: url)
    }
}

/// Layer-backed view that owns the player and fills its bounds with the video.
final class PlayerContainerView: NSView {
    private var playerLayer: AVPlayerLayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func load(url: URL) {
        guard url != currentURL else { return }
        currentURL = url

        playerLayer?.removeFromSuperlayer()

        let queue = AVQueuePlayer()
        queue.isMuted = true
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))

        let layer = AVPlayerLayer(player: queue)
        layer.videoGravity = .resize   // fill the box; whole video maps into the quad
        layer.frame = bounds
        self.layer?.addSublayer(layer)
        playerLayer = layer

        queue.play()
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }
}
