import Foundation

/// Smoothed, normalized audio energy split into three frequency bands plus an
/// overall level. All values are in `0…1`. Produced by `AudioBandAnalyzer` and
/// consumed by `SwarmDrivers(from:)`. Pure value type — no AVFoundation.
public struct AudioLevels: Equatable {
    public var bass: Double
    public var mid: Double
    public var treble: Double
    public var overall: Double

    public init(bass: Double = 0, mid: Double = 0, treble: Double = 0, overall: Double = 0) {
        self.bass = bass
        self.mid = mid
        self.treble = treble
        self.overall = overall
    }

    /// Silence — the resting state and the mic-denied fallback source.
    public static let silent = AudioLevels()
}
