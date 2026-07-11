// Run: swift scripts/verify_tree_mask.swift
import AppKit

let path = "Sources/Lumora/Resources/christmas-tree.png"
guard let img = NSImage(contentsOfFile: path),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { print("no image"); exit(1) }
let cols = 48, rows = 72, bpr = cols * 4
var data = [UInt8](repeating: 0, count: bpr * rows)
let ctx = CGContext(data: &data, width: cols, height: rows, bitsPerComponent: 8, bytesPerRow: bpr,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cols, height: rows))
// Tree silhouette: a triangle from the star apex down to the base, widening
// linearly. Color alone can't separate the golden glow halo (bright + saturated)
// from gold ornaments, but the halo sits beside the narrow tree top, outside
// this triangle.
func insideTree(_ nx: Double, _ ny: Double) -> Bool {
    let top = 0.05, bottom = 0.80
    guard ny >= top, ny <= bottom else { return false }
    let frac = (ny - top) / (bottom - top)      // 0 apex → 1 base
    let halfWidth = 0.06 + 0.40 * frac
    return abs(nx - 0.5) <= halfWidth
}

var pts: [CGPoint] = []
for row in 0..<rows { for col in 0..<cols {
    let i = row*bpr + col*4
    let r = Double(data[i])/255, g = Double(data[i+1])/255, b = Double(data[i+2])/255
    let lum = 0.299*r + 0.587*g + 0.114*b
    let maxc = max(r,max(g,b)), minc = min(r,min(g,b))
    let sat = maxc > 0 ? (maxc-minc)/maxc : 0
    let nx = (Double(col)+0.5)/Double(cols), ny = (Double(rows-1-row)+0.5)/Double(rows)
    // Bright + colorful/near-white, AND within the tree silhouette.
    if lum > 0.34 && (sat > 0.28 || lum > 0.9) && insideTree(nx, ny) {
        pts.append(CGPoint(x: nx, y: ny))
    }
}}
print("kept \(pts.count) / \(cols*rows) cells")

let W = cg.width, H = cg.height
let bmp = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let g = NSGraphicsContext(bitmapImageRep: bmp)!.cgContext
g.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
g.setFillColor(NSColor.cyan.cgColor)
for p in pts { // p is top-left normalized; device is bottom-up
    let x = p.x*Double(W), y = Double(H)*(1-p.y)
    g.fillEllipse(in: CGRect(x: x-3, y: y-3, width: 6, height: 6))
}
if let png = bmp.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: "/tmp/tree_mask.png")); print("wrote /tmp/tree_mask.png")
}
