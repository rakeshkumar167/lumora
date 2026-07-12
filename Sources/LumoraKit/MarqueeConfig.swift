import Foundation

/// Customization for the Marquee Text effect. Codable so it persists with a
/// project. Stored on `Surface` and read by the marquee renderer.
public struct MarqueeConfig: Equatable, Codable {
    /// Text to scroll. Empty falls back to the surface's name.
    public var text: String
    /// Font family name (e.g. "Helvetica Neue"). Empty uses the system
    /// monospaced face.
    public var fontName: String
    /// Font size in points.
    public var fontSize: Double
    /// When true, characters cycle through the color spectrum instead of using
    /// the chosen palette color.
    public var rainbow: Bool

    public init(text: String = "", fontName: String = "", fontSize: Double = 48, rainbow: Bool = false) {
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.rainbow = rainbow
    }
}
