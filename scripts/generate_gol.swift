// Run: swift scripts/generate_gol.swift
// Pre-bakes a nice-looking Game of Life run into a compact resource the app
// loops through (so playback costs nothing — no live simulation). Searches
// several 20-cluster seeds for the liveliest, bakes ~2 min of generations with
// light periodic re-injection so it never goes static, bit-packs every frame,
// and writes Sources/Lumora/Resources/gameoflife.json.
import Foundation

let cols = 100, rows = 56
let frames = 960          // ~2 min at the app's default 8 gen/s
let cells = cols * rows

func hash01(_ a: Int, _ b: Int) -> Double {
    var h = UInt64(bitPattern: Int64(a &* 374761393 &+ b &* 668265263))
    h = (h ^ (h >> 13)) &* 1274126177
    return Double(h % 100000) / 100000
}

func seed(_ seeds: Int, _ sv: Int) -> [Bool] {
    var g = [Bool](repeating: false, count: cells)
    for s in 0..<seeds {
        let cx = 1 + Int(hash01(sv, s * 3 + 1) * Double(cols - 2))
        let cy = 1 + Int(hash01(sv, s * 3 + 2) * Double(rows - 2))
        for dy in -1...1 { for dx in -1...1 {
            if hash01(sv, s * 97 + (dy + 1) * 3 + (dx + 1)) > 0.45 {
                let x = (cx + dx + cols) % cols, y = (cy + dy + rows) % rows
                g[y * cols + x] = true
            }
        } }
    }
    return g
}

func step(_ g: [Bool]) -> [Bool] {
    var n = [Bool](repeating: false, count: cells)
    for y in 0..<rows {
        let up = ((y - 1 + rows) % rows) * cols, dn = ((y + 1) % rows) * cols, cur = y * cols
        for x in 0..<cols {
            let l = (x - 1 + cols) % cols, r = (x + 1) % cols
            var c = 0
            if g[cur + l] { c += 1 }; if g[cur + r] { c += 1 }
            if g[up + x] { c += 1 }; if g[dn + x] { c += 1 }
            if g[up + l] { c += 1 }; if g[up + r] { c += 1 }
            if g[dn + l] { c += 1 }; if g[dn + r] { c += 1 }
            let i = cur + x
            n[i] = g[i] ? (c == 2 || c == 3) : (c == 3)
        }
    }
    return n
}

// Score a seed by total activity (cells that toggle) over 160 generations.
func activity(of sv: Int) -> Int {
    var g = seed(20, sv)
    var toggles = 0
    for _ in 0..<160 {
        let n = step(g)
        for i in 0..<cells where n[i] != g[i] { toggles += 1 }
        g = n
    }
    return toggles
}

var bestSV = 1, bestScore = -1
for sv in 1...30 {
    let a = activity(of: sv)
    if a > bestScore { bestScore = a; bestSV = sv }
}
FileHandle.standardError.write("best seed \(bestSV) (activity \(bestScore))\n".data(using: .utf8)!)

// Bake the frames, re-injecting a small fresh soup every 120 gens to stay lively.
var grid = seed(20, bestSV)
let bytesPerFrame = (cells + 7) / 8
var data = Data(capacity: bytesPerFrame * frames)
for f in 0..<frames {
    var frame = [UInt8](repeating: 0, count: bytesPerFrame)
    for i in 0..<cells where grid[i] { frame[i >> 3] |= (1 << (i & 7)) }
    data.append(contentsOf: frame)
    if f > 0 && f % 120 == 0 {
        let inject = seed(8, bestSV &* 131 &+ f)
        for i in 0..<cells where inject[i] { grid[i] = true }
    }
    grid = step(grid)
}

let json: [String: Any] = ["cols": cols, "rows": rows, "frames": frames,
                           "data": data.base64EncodedString()]
let out = try! JSONSerialization.data(withJSONObject: json, options: [])
let path = "Sources/Lumora/Resources/gameoflife.json"
try! out.write(to: URL(fileURLWithPath: path))
print("wrote \(path): \(frames) frames, \(cols)x\(rows), \(out.count / 1024) KB")
