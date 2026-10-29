// Retakes the welcome-tour screenshots in Sources/Lumora/Resources/tour-*.png.
//
// 1. Launch the app with the sample project (`swift run Lumora`), let the
//    splash fade, close the tour, and leave "Surface 1" selected (the default).
// 2. Run: swift scripts/capture_tour_screenshots.swift
//
// Needs Screen Recording permission for the terminal. Crop rects are in pixels
// of a Retina capture of the default-size editor window (1471×831 pt); if the
// layout changes, adjust the rects below and eyeball the output.
import AppKit
import CoreGraphics

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
guard let id = windows.first(where: {
    $0[kCGWindowOwnerName as String] as? String == "Lumora" && $0[kCGWindowName as String] as? String == "Lumora"
})?[kCGWindowNumber as String] as? Int else {
    fatalError("Lumora editor window not found — is the app running?")
}

let full = NSTemporaryDirectory() + "lumora-tour-full.png"
let capture = Process()
capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
capture.arguments = ["-x", "-o", "-l\(id)", full]
try capture.run()
capture.waitUntilExit()

let src = NSImage(contentsOfFile: full)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../Sources/Lumora/Resources").standardized

// name, x, y, w, h, max output width (0 = keep)
let crops: [(String, Int, Int, Int, Int, Int)] = [
    ("tour-canvas",          643,  135, 1736, 1402, 1100),
    ("tour-toolbar",         643,  135, 1736,   90, 0),
    ("tour-properties",        0,  135,  641,  690, 0),
    ("tour-media",             0,  853,  641,  684, 0),
    ("tour-surfaces",       2380,  135,  562,  350, 0),
    ("tour-scenes-list",       0, 1540,  900,  122, 0),
    ("tour-scenes-controls", 2550, 1540,  392,  122, 0),
    ("tour-project",        2560,   59,  382,   76, 0),
    ("tour-saveopen",       1670,  135,  330,   90, 0),
]

for (name, x, y, w, h, maxW) in crops {
    var img = src.cropping(to: CGRect(x: x, y: y, width: w, height: h))!
    if maxW > 0, img.width > maxW {
        let scale = Double(maxW) / Double(img.width)
        let size = CGSize(width: Double(img.width) * scale, height: Double(img.height) * scale)
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(origin: .zero, size: size))
        img = ctx.makeImage()!
    }
    let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
    try png.write(to: out.appendingPathComponent("\(name).png"))
    print("wrote \(name).png")
}
