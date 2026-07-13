import Foundation

/// Reduces an FFT magnitude spectrum into a smoothed, auto-gained `AudioLevels`
/// (bass / mid / treble / overall). Stateful across calls — it keeps a decaying
/// running peak so it adapts to room loudness (no user sensitivity knob) — but
/// pure Swift with no AVFoundation, so it is unit-testable with synthetic
/// spectra.
public final class AudioBandAnalyzer {
    /// Band edges in Hz. Energy above `trebleMax` is ignored (little musical
    /// content for driving particles).
    private let bassMax = 250.0
    private let midMax = 2000.0
    private let trebleMax = 8000.0

    /// Rise/fall smoothing (per call). Fast attack, slow decay reads as punchy.
    private let attack: Double
    private let decay: Double
    /// Running-peak decay for auto-gain; the floor stops silence from being
    /// amplified into noise.
    private let gainDecay: Double
    private let peakFloor: Double

    private var peak: Double
    private var smoothed = AudioLevels.silent

    public init(attack: Double = 0.6, decay: Double = 0.12,
                gainDecay: Double = 0.995, peakFloor: Double = 1e-4) {
        self.attack = attack
        self.decay = decay
        self.gainDecay = gainDecay
        self.peakFloor = peakFloor
        self.peak = peakFloor
    }

    public func reset() {
        peak = peakFloor
        smoothed = .silent
    }

    /// Fold `magnitudes` (linear FFT magnitudes, bins `0…Nyquist`) into
    /// normalized, smoothed band levels.
    public func process(magnitudes: [Float], sampleRate: Double) -> AudioLevels {
        guard magnitudes.count > 1, sampleRate > 0 else { return smoothed }
        let hzPerBin = sampleRate / Double(2 * magnitudes.count)

        var bassSum = 0.0, midSum = 0.0, trebleSum = 0.0
        var bassN = 0, midN = 0, trebleN = 0
        for (i, m) in magnitudes.enumerated() {
            let hz = Double(i) * hzPerBin
            let v = Double(m)
            if hz < 20 { continue }                       // skip DC / sub-audible
            if hz <= bassMax { bassSum += v; bassN += 1 }
            else if hz <= midMax { midSum += v; midN += 1 }
            else if hz <= trebleMax { trebleSum += v; trebleN += 1 }
        }
        let bassRaw = bassN > 0 ? bassSum / Double(bassN) : 0
        let midRaw = midN > 0 ? midSum / Double(midN) : 0
        let trebleRaw = trebleN > 0 ? trebleSum / Double(trebleN) : 0
        let overallRaw = (bassRaw + midRaw + trebleRaw) / 3

        // Auto-gain: track a decaying running peak across all bands.
        peak = max(peak * gainDecay, peakFloor)
        peak = max(peak, bassRaw, midRaw, trebleRaw)
        let inv = 1.0 / peak

        let target = AudioLevels(
            bass: clamp(bassRaw * inv),
            mid: clamp(midRaw * inv),
            treble: clamp(trebleRaw * inv),
            overall: clamp(overallRaw * inv))
        smoothed = AudioLevels(
            bass: smooth(smoothed.bass, target.bass),
            mid: smooth(smoothed.mid, target.mid),
            treble: smooth(smoothed.treble, target.treble),
            overall: smooth(smoothed.overall, target.overall))
        return smoothed
    }

    private func smooth(_ current: Double, _ target: Double) -> Double {
        let rate = target > current ? attack : decay
        return current + (target - current) * rate
    }

    private func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}
