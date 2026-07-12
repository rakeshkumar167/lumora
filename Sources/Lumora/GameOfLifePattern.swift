import Foundation

/// Pre-baked Game of Life frames, loaded once from the bundled resource. The
/// effect loops through these instead of simulating live, so playback is free.
enum GameOfLifePattern {
    struct Pattern {
        let cols: Int
        let rows: Int
        let frameCount: Int
        let data: [UInt8]   // bit-packed: frameCount × bytesPerFrame

        var bytesPerFrame: Int { (cols * rows + 7) / 8 }

        func isLive(frame: Int, x: Int, y: Int) -> Bool {
            let c = y * cols + x
            let idx = frame * bytesPerFrame + (c >> 3)
            guard idx >= 0, idx < data.count else { return false }
            return (data[idx] >> (c & 7)) & 1 == 1
        }
    }

    /// Loaded once and cached (nil only if the resource is missing/corrupt).
    static let shared: Pattern? = load()

    private static func load() -> Pattern? {
        guard let url = Bundle.module.url(forResource: "gameoflife", withExtension: "json"),
              let d = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let cols = obj["cols"] as? Int,
              let rows = obj["rows"] as? Int,
              let frames = obj["frames"] as? Int,
              let b64 = obj["data"] as? String,
              let bytes = Data(base64Encoded: b64) else { return nil }
        return Pattern(cols: cols, rows: rows, frameCount: frames, data: [UInt8](bytes))
    }
}
