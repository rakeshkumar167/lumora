import Foundation

/// Pure helper: given per-scene durations, which scene is playing at a given
/// elapsed time in a looping sequence.
public enum SceneTimeline {
    /// Minimum effective duration so a 0-length scene can't stall the loop.
    public static let minDuration: Double = 1.0

    /// Index of the scene playing `elapsed` seconds into the looping sequence.
    /// Returns 0 for empty input.
    public static func index(at elapsed: Double, durations: [Double]) -> Int {
        guard !durations.isEmpty else { return 0 }
        let d = durations.map { Swift.max($0, minDuration) }
        let total = d.reduce(0, +)
        guard total > 0 else { return 0 }
        var t = elapsed.truncatingRemainder(dividingBy: total)
        if t < 0 { t += total }
        var acc = 0.0
        for (i, dur) in d.enumerated() {
            acc += dur
            if t < acc { return i }
        }
        return d.count - 1
    }
}
