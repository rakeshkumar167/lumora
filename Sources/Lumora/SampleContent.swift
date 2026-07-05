import AppKit

/// A neutral blank canvas used as the room backdrop until a real room photo is
/// captured/imported. Drawn in a top-left-origin space to match surface coords.
enum SampleContent {
    static func roomImage(size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocusFlipped(true)
        defer { image.unlockFocus() }

        // Subtle neutral vertical gradient so the canvas reads as a surface
        // without implying any room geometry.
        let gradient = NSGradient(colors: [
            NSColor(white: 0.93, alpha: 1),
            NSColor(white: 0.86, alpha: 1),
        ])
        gradient?.draw(in: NSRect(origin: .zero, size: size), angle: -90)

        return image
    }
}
