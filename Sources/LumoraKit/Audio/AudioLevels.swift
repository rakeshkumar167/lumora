import Foundation

/// Smoothed, normalized audio energy split into three frequency bands plus an
/// overall level. All values are in `0…1`. Produced by `AudioBandAnalyzer` and
/// consumed by `SwarmDrivers(from:)`. Pure value type — no AVFoundation.
public struct AudioLevels: Equatable {
    public var bass: Double
    public var mid: Double
    public var treble: Double
    public var overall: Double
    /// 16 log-spaced smoothed bins, 20 Hz…8 kHz, each 0…1. Empty until filled.
    public var spectrum: [Double]
    /// Monotonically increasing beat count; consumers diff against last-seen.
    public var beatCount: Int
    /// Strength of the most recent beat, 0…1.
    public var beatStrength: Double

    public init(bass: Double = 0, mid: Double = 0, treble: Double = 0, overall: Double = 0,
                spectrum: [Double] = [], beatCount: Int = 0, beatStrength: Double = 0) {
        self.bass = bass
        self.mid = mid
        self.treble = treble
        self.overall = overall
        self.spectrum = spectrum
        self.beatCount = beatCount
        self.beatStrength = beatStrength
    }

    /// Silence — the resting state and the mic-denied fallback source.
    public static let silent = AudioLevels()
}
