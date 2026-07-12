import Foundation

/// Conway's Game of Life rules + deterministic seeding. Pure and testable;
/// the renderer drives it from the global clock (seed → step N generations).
/// Grids are row-major `[Bool]` of `cols × rows`; the board wraps (toroidal).
public enum GameOfLife {
    /// Advance one generation.
    public static func step(_ g: [Bool], cols: Int, rows: Int) -> [Bool] {
        guard cols > 0, rows > 0, g.count == cols * rows else { return g }
        var next = [Bool](repeating: false, count: cols * rows)
        for y in 0..<rows {
            for x in 0..<cols {
                var n = 0
                for dy in -1...1 {
                    for dx in -1...1 {
                        if dx == 0 && dy == 0 { continue }
                        let nx = (x + dx + cols) % cols
                        let ny = (y + dy + rows) % rows
                        if g[ny * cols + nx] { n += 1 }
                    }
                }
                let alive = g[y * cols + x]
                next[y * cols + x] = alive ? (n == 2 || n == 3) : (n == 3)
            }
        }
        return next
    }

    /// Deterministically scatter `seeds` small random clusters (3×3 soups) so
    /// the board evolves with real oscillators/gliders rather than dying at once.
    public static func seed(cols: Int, rows: Int, seeds: Int, seedValue: Int) -> [Bool] {
        var g = [Bool](repeating: false, count: max(0, cols * rows))
        guard cols > 2, rows > 2 else { return g }
        for s in 0..<seeds {
            let cx = 1 + Int(hash01(seedValue, s * 3 + 1) * Double(cols - 2))
            let cy = 1 + Int(hash01(seedValue, s * 3 + 2) * Double(rows - 2))
            for dy in -1...1 {
                for dx in -1...1 {
                    if hash01(seedValue, s * 97 + (dy + 1) * 3 + (dx + 1)) > 0.45 {
                        let x = cx + dx, y = cy + dy
                        if x >= 0, x < cols, y >= 0, y < rows { g[y * cols + x] = true }
                    }
                }
            }
        }
        return g
    }

    /// Population count (live cells).
    public static func population(_ g: [Bool]) -> Int { g.lazy.filter { $0 }.count }

    private static func hash01(_ a: Int, _ b: Int) -> Double {
        var h = UInt64(bitPattern: Int64(a &* 374761393 &+ b &* 668265263))
        h = (h ^ (h >> 13)) &* 1274126177
        return Double(h % 10000) / 10000.0
    }
}
