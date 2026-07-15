// Run: swift scripts/verify_maze.swift
// Renders the Maze Generate & Solve effect (self-carving corridors with a
// glowing head, then a traced BFS solution) at three phases — mid-carve,
// full-carve, and solve — mirroring MazeSolveView in SurfaceContentView.swift
// (standalone scripts can't import the app module's private views, so the pure
// Maze generator is mirrored inline). Writes PNGs to /tmp and asserts each
// frame is non-blank and full-carve has more lit pixels than mid-carve (the
// corridors build up).
import AppKit
import SwiftUI

// MARK: - Pure maze generator (mirrors Sources/LumoraKit/Maze.swift)

struct MazeCell: Hashable { var x: Int; var y: Int }

struct Passage: Hashable {
    let a: MazeCell; let b: MazeCell
    init(_ p: MazeCell, _ q: MazeCell) {
        if (p.x, p.y) <= (q.x, q.y) { a = p; b = q } else { a = q; b = p }
    }
}

struct LCG {
    var state: UInt64
    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed)) &* 0x9E3779B97F4A7C15 &+ 0x1234_5678_9ABC_DEF
        if state == 0 { state = 0xDEAD_BEEF }
    }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    mutating func int(_ n: Int) -> Int { Int(next() >> 11) % n }
}

struct Maze {
    let cols: Int; let rows: Int
    let passages: Set<Passage>
    let carveOrder: [Passage]

    static func generate(cols: Int, rows: Int, seed: Int) -> Maze {
        var rng = LCG(seed: seed)
        var visited = [Bool](repeating: false, count: cols * rows)
        func idx(_ x: Int, _ y: Int) -> Int { y * cols + x }
        var passages = Set<Passage>()
        var carveOrder: [Passage] = []
        var stack: [MazeCell] = [MazeCell(x: 0, y: 0)]
        visited[idx(0, 0)] = true
        let offs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        while let current = stack.last {
            var cand: [MazeCell] = []
            for (dx, dy) in offs {
                let nx = current.x + dx, ny = current.y + dy
                if nx >= 0, nx < cols, ny >= 0, ny < rows, !visited[idx(nx, ny)] {
                    cand.append(MazeCell(x: nx, y: ny))
                }
            }
            if cand.isEmpty { stack.removeLast(); continue }
            let nxt = cand[rng.int(cand.count)]
            visited[idx(nxt.x, nxt.y)] = true
            let p = Passage(current, nxt)
            passages.insert(p); carveOrder.append(p); stack.append(nxt)
        }
        return Maze(cols: cols, rows: rows, passages: passages, carveOrder: carveOrder)
    }

    func neighbors(of c: MazeCell) -> [MazeCell] {
        var r: [MazeCell] = []
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            let n = MazeCell(x: c.x + dx, y: c.y + dy)
            guard n.x >= 0, n.x < cols, n.y >= 0, n.y < rows else { continue }
            if passages.contains(Passage(c, n)) { r.append(n) }
        }
        return r
    }

    func solve() -> [MazeCell] {
        let start = MazeCell(x: 0, y: 0), goal = MazeCell(x: cols - 1, y: rows - 1)
        var cameFrom = [MazeCell: MazeCell](); var seen: Set<MazeCell> = [start]
        var queue = [start]; var head = 0
        while head < queue.count {
            let c = queue[head]; head += 1
            if c == goal { break }
            for n in neighbors(of: c) where !seen.contains(n) {
                seen.insert(n); cameFrom[n] = c; queue.append(n)
            }
        }
        guard seen.contains(goal) else { return [] }
        var path = [goal]; var cur = goal
        while cur != start, let prev = cameFrom[cur] { path.append(prev); cur = prev }
        return path.reversed()
    }
}

// MARK: - Renderer frame (mirrors MazeSolveView.draw)

let cols = 18, rows = 12
let maze = Maze.generate(cols: cols, rows: rows, seed: 0)
let solution = maze.solve()

struct MazeFrame: View {
    let carveFrac: Double
    let solveFrac: Double   // <0 means solve phase not started
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.02)))
            let margin = min(size.width, size.height) * 0.08
            let boxW = size.width - margin * 2, boxH = size.height - margin * 2
            let cellW = boxW / CGFloat(cols), cellH = boxH / CGFloat(rows)
            func center(_ c: MazeCell) -> CGPoint {
                CGPoint(x: margin + (CGFloat(c.x) + 0.5) * cellW,
                        y: margin + (CGFloat(c.y) + 0.5) * cellH)
            }
            let glow = Color(red: 0.2, green: 0.7, blue: 1.0)
            let acc = Color(red: 1.0, green: 0.55, blue: 0.2)
            func corner(_ gx: Int, _ gy: Int) -> CGPoint {
                CGPoint(x: margin + CGFloat(gx) * cellW, y: margin + CGFloat(gy) * cellH)
            }

            // Maze WALLS (boundaries with no passage) + outer border, revealed by
            // carve progress — mirrors MazeSolveView. Solution threads corridors.
            var visit: [MazeCell: Int] = [:]
            if let f = maze.carveOrder.first { visit[f.a] = 0 }
            for (i, p) in maze.carveOrder.enumerated() { visit[p.b] = i + 1 }
            let maxVisit = max(1, maze.carveOrder.count)
            func ready(_ cells: [MazeCell]) -> Double {
                Double(cells.map { visit[$0] ?? 0 }.max() ?? 0) / Double(maxVisit)
            }
            var wallsPath = Path()
            func addWall(_ a: CGPoint, _ b: CGPoint, _ rdy: Double) {
                if rdy <= carveFrac { wallsPath.move(to: a); wallsPath.addLine(to: b) }
            }
            for y in 0..<rows {
                for x in 0..<cols {
                    let c = MazeCell(x: x, y: y)
                    if x + 1 < cols {
                        let r = MazeCell(x: x + 1, y: y)
                        if !maze.passages.contains(Passage(c, r)) {
                            addWall(corner(x + 1, y), corner(x + 1, y + 1), ready([c, r]))
                        }
                    }
                    if y + 1 < rows {
                        let d = MazeCell(x: x, y: y + 1)
                        if !maze.passages.contains(Passage(c, d)) {
                            addWall(corner(x, y + 1), corner(x + 1, y + 1), ready([c, d]))
                        }
                    }
                }
            }
            addWall(corner(0, 0), corner(cols, 0), 0)
            addWall(corner(0, rows), corner(cols, rows), 0)
            addWall(corner(0, 0), corner(0, rows), 0)
            addWall(corner(cols, 0), corner(cols, rows), 0)
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 6)); l.blendMode = .plusLighter
                l.stroke(wallsPath, with: .color(glow.opacity(0.4)),
                         style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            ctx.stroke(wallsPath, with: .color(glow.opacity(0.95)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            guard solveFrac >= 0, solution.count >= 2 else { return }
            var solved = Path()
            solved.move(to: center(solution[0]))
            let upto = max(1, Int(solveFrac * Double(solution.count - 1)))
            for i in 1...upto { solved.addLine(to: center(solution[i])) }
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 10)); l.blendMode = .plusLighter
                l.stroke(solved, with: .color(acc.opacity(0.6)),
                         style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
            }
            ctx.stroke(solved, with: .color(acc),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 640, height: 440)
    }
}

func litPixelCount(_ image: NSImage) -> Int {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return 0 }
    var count = 0
    for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
            guard let c = rep.colorAt(x: x, y: y) else { continue }
            let lum = 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
            if lum > 0.08 { count += 1 }
        }
    }
    return count
}

func render(carve: Double, solve: Double, path: String) -> Int {
    var lit = 0
    MainActor.assumeIsolated {
        let renderer = ImageRenderer(content: MazeFrame(carveFrac: carve, solveFrac: solve))
        renderer.scale = 2
        guard let img = renderer.nsImage else { print("FAIL: no image for \(path)"); return }
        lit = litPixelCount(img)
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("wrote \(path) (lit pixels: \(lit))")
        }
    }
    return lit
}

let mid = render(carve: 0.45, solve: -1, path: "/tmp/maze_mid_carve.png")
let full = render(carve: 1.0, solve: -1, path: "/tmp/maze_full_carve.png")
let solved = render(carve: 1.0, solve: 1.0, path: "/tmp/maze_solved.png")

precondition(mid > 0, "mid-carve frame should have lit pixels")
precondition(full > 0, "full-carve frame should have lit pixels")
precondition(solved > 0, "solved frame should have lit pixels")
precondition(full > mid, "corridors should build up: full-carve (\(full)) > mid-carve (\(mid))")
precondition(solved >= full, "solution overlay adds pixels: solved (\(solved)) >= full-carve (\(full))")

print("PASS: corridors build up (mid=\(mid) < full=\(full)); solution overlay renders (solved=\(solved))")
