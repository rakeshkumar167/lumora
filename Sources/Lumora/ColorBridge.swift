import AppKit
import LumoraKit
import SwiftUI

extension RGBAColor {
    /// Bridge the UI-free model color to a SwiftUI `Color`.
    var color: Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Build a model color from a SwiftUI `Color` (via sRGB components).
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(
            r: Double(ns.redComponent),
            g: Double(ns.greenComponent),
            b: Double(ns.blueComponent),
            a: Double(ns.alphaComponent)
        )
    }
}
