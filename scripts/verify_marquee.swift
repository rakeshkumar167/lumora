// Run: swift scripts/verify_marquee.swift
// Renders the Marquee Text effect with custom text/font/size and rainbow,
// mirroring the renderer in SurfaceContentView, to confirm it looks right.
import AppKit
import SwiftUI

struct Marquee: View {
    var text: String
    var fontName: String
    var fontSize: Double
    var rainbow: Bool
    var textColor: Color
    var bg: Color
    var time: Double = 0.6

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))
            let base = text.isEmpty ? "LUMORA" : text
            let label = base + "     "
            let font: Font = fontName.isEmpty
                ? .system(size: fontSize, weight: .bold, design: .monospaced)
                : .custom(fontName, size: fontSize)
            let chars = Array(label)
            var widths: [CGFloat] = []
            var unitWidth: CGFloat = 0
            for ch in chars {
                let w = ctx.resolve(Text(String(ch)).font(font))
                    .measure(in: CGSize(width: 10000, height: 10000)).width
                widths.append(w); unitWidth += w
            }
            if unitWidth < 1 { unitWidth = 1 }
            let offset = CGFloat(time) * 120
            var tileX = -offset.truncatingRemainder(dividingBy: unitWidth)
            if tileX > 0 { tileX -= unitWidth }
            let y = size.height / 2
            let denom = Double(max(chars.count, 1))
            while tileX < size.width {
                var x = tileX
                for (i, ch) in chars.enumerated() {
                    let w = widths[i]
                    let col: Color = rainbow
                        ? Color(hue: (Double(i) / denom + time * 0.08).truncatingRemainder(dividingBy: 1),
                                saturation: 0.95, brightness: 1)
                        : textColor
                    ctx.draw(Text(String(ch)).font(font).foregroundColor(col),
                             at: CGPoint(x: x + w / 2, y: y))
                    x += w
                }
                tileX += unitWidth
            }
        }
    }
}

struct Board: View {
    var body: some View {
        VStack(spacing: 10) {
            Marquee(text: "", fontName: "", fontSize: 48, rainbow: false,
                    textColor: .cyan, bg: Color(white: 0.08)).frame(width: 700, height: 90)
            Marquee(text: "Happy Diwali!", fontName: "Snell Roundhand", fontSize: 60, rainbow: false,
                    textColor: .yellow, bg: Color(red: 0.1, green: 0.0, blue: 0.15)).frame(width: 700, height: 90)
            Marquee(text: "NOW OPEN", fontName: "Impact", fontSize: 64, rainbow: true,
                    textColor: .white, bg: .black).frame(width: 700, height: 90)
            Marquee(text: "welcome to the show", fontName: "Futura", fontSize: 44, rainbow: true,
                    textColor: .white, bg: Color(white: 0.05)).frame(width: 700, height: 90)
        }.padding(16).background(Color(white: 0.2))
    }
}

MainActor.assumeIsolated {
    let r = ImageRenderer(content: Board()); r.scale = 2
    if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: "/tmp/marquee.png")); print("wrote /tmp/marquee.png")
    }
}
