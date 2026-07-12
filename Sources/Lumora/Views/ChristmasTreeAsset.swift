import AppKit
import CoreGraphics
import Foundation

/// The bundled Christmas-tree image and the set of normalized on-tree points
/// where twinkle glints may appear. The image sits on a dark vignetted
/// background, so a luminance threshold on a downsampled grid cleanly excludes
/// the background — glints only spawn on the tree. Computed once, lazily.
enum ChristmasTreeAsset {
    private static let names = ["christmas-tree", "christmas-tree2", "christmas-tree3"]
    static var count: Int { names.count }

    private static var imageCache: [Int: NSImage] = [:]
    private static var pointsCache: [Int: [CGPoint]] = [:]

    /// The bundled tree image at `index` (clamped), loaded and cached lazily.
    static func image(_ index: Int) -> NSImage? {
        let i = clamp(index)
        if let img = imageCache[i] { return img }
        guard let url = Bundle.module.url(forResource: names[i], withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        imageCache[i] = img
        return img
    }

    /// Normalized (0…1, top-left) bright on-tree points for tree `index`.
    static func litPoints(_ index: Int) -> [CGPoint] {
        let i = clamp(index)
        if let p = pointsCache[i] { return p }
        let p = computeLitPoints(image(i))
        pointsCache[i] = p
        return p
    }

    private static func clamp(_ index: Int) -> Int { max(0, min(index, names.count - 1)) }

    private static func computeLitPoints(_ image: NSImage?) -> [CGPoint] {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return fallbackTrianglePoints()
        }
        let cols = 48, rows = 72
        let bytesPerRow = cols * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * rows)
        guard let ctx = CGContext(data: &data, width: cols, height: rows, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return fallbackTrianglePoints()
        }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cols, height: rows))

        var points: [CGPoint] = []
        for row in 0..<rows {
            for col in 0..<cols {
                let i = row * bytesPerRow + col * 4
                let r = Double(data[i]) / 255, g = Double(data[i + 1]) / 255, b = Double(data[i + 2]) / 255
                let lum = 0.299 * r + 0.587 * g + 0.114 * b
                let maxc = max(r, max(g, b)), minc = min(r, min(g, b))
                let sat = maxc > 0 ? (maxc - minc) / maxc : 0
                // CGContext origin is bottom-left; flip row to top-left.
                let nx = (Double(col) + 0.5) / Double(cols)
                let ny = (Double(rows - 1 - row) + 0.5) / Double(rows)
                // Keep a cell only if it is bright (excludes the dark green
                // vignette), colorful or near-white (foliage/ornaments/lights),
                // AND inside the tree silhouette. The last gate is essential:
                // the golden glow halo behind the tree top is bright + saturated
                // like a gold ornament, so only its position distinguishes it.
                if lum > 0.34, sat > 0.28 || lum > 0.9, Self.insideTree(nx, ny) {
                    points.append(CGPoint(x: nx, y: ny))
                }
            }
        }
        return points.isEmpty ? fallbackTrianglePoints() : points
    }

    /// The tree's triangular silhouette: apex at the star, widening to the base.
    /// Excludes the surrounding glow halo and the presents beneath the tree.
    private static func insideTree(_ nx: Double, _ ny: Double) -> Bool {
        let top = 0.05, bottom = 0.80
        guard ny >= top, ny <= bottom else { return false }
        let frac = (ny - top) / (bottom - top)      // 0 apex → 1 base
        let halfWidth = 0.06 + 0.40 * frac
        return abs(nx - 0.5) <= halfWidth
    }

    /// A triangular tree-shaped fallback if the image can't be read.
    private static func fallbackTrianglePoints() -> [CGPoint] {
        var pts: [CGPoint] = []
        let apexX = 0.5, top = 0.08, bottom = 0.82
        for ny in stride(from: top, through: bottom, by: 0.03) {
            let frac = (ny - top) / (bottom - top)          // 0 at apex → 1 at base
            let halfWidth = 0.40 * frac
            for nx in stride(from: apexX - halfWidth, through: apexX + halfWidth, by: 0.05) {
                pts.append(CGPoint(x: nx, y: ny))
            }
        }
        return pts
    }
}
