import Foundation

/// Energy-onset beat detection on the bass band. Pure Swift, unit-tested with
/// synthetic level sequences. Keeps a short ring buffer of recent bass levels
/// and fires when the current level is both well above the local mean
/// (`mean + k·stddev`) and above an absolute floor, with a refractory window so
/// one kick reads as one beat.
public final class BeatDetector {
    private let historyLen: Int
    private let k: Double
    private let floor: Double
    private let refractory: Int

    private var history: [Double] = []
    private var sinceLast: Int

    public init(historyLen: Int = 43, k: Double = 1.5, floor: Double = 0.15, refractory: Int = 8) {
        self.historyLen = max(4, historyLen)
        self.k = k
        self.floor = floor
        self.refractory = refractory
        self.sinceLast = refractory   // allow an immediate first beat once warm
    }

    public func reset() {
        history.removeAll(keepingCapacity: true)
        sinceLast = refractory
    }

    /// Feed one bass level (0…1). Returns whether this frame is a beat onset and
    /// its strength (how far above the mean, clamped 0…1).
    public func process(bass: Double) -> (isBeat: Bool, strength: Double) {
        sinceLast += 1
        defer {
            history.append(bass)
            if history.count > historyLen { history.removeFirst() }
        }
        guard history.count >= historyLen / 2 else { return (false, 0) }

        let mean = history.reduce(0, +) / Double(history.count)
        let variance = history.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(history.count)
        let std = variance.squareRoot()
        let threshold = mean + k * std

        let isBeat = bass > threshold && bass > floor && sinceLast >= refractory
        if isBeat {
            sinceLast = 0
            let strength = std > 1e-6 ? min(1.0, (bass - mean) / (4 * std)) : min(1.0, bass)
            return (true, max(0, strength))
        }
        return (false, 0)
    }
}
