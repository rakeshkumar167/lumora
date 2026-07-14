import XCTest
@testable import LumoraKit

final class AudioBandAnalyzerTests: XCTestCase {
    // Build a magnitude spectrum with a single spike at `hz`.
    private func spectrum(spikeHz: Double, sampleRate: Double, bins: Int) -> [Float] {
        var m = [Float](repeating: 0, count: bins)
        let hzPerBin = sampleRate / Double(2 * bins)
        let idx = min(bins - 1, max(0, Int(spikeHz / hzPerBin)))
        m[idx] = 1.0
        return m
    }

    func testSpectrumHas16Bins() {
        let a = AudioBandAnalyzer()
        let m = spectrum(spikeHz: 440, sampleRate: 44100, bins: 512)
        let levels = a.process(magnitudes: m, sampleRate: 44100)
        XCTAssertEqual(levels.spectrum.count, 16)
    }

    func testLowSpikeLandsInLowBins() {
        let a = AudioBandAnalyzer()
        let m = spectrum(spikeHz: 60, sampleRate: 44100, bins: 512)
        var levels = AudioLevels.silent
        for _ in 0..<10 { levels = a.process(magnitudes: m, sampleRate: 44100) }
        let lowEnergy = levels.spectrum.prefix(4).reduce(0, +)
        let highEnergy = levels.spectrum.suffix(4).reduce(0, +)
        XCTAssertGreaterThan(lowEnergy, highEnergy)
    }

    func testHighSpikeLandsInHighBins() {
        let a = AudioBandAnalyzer()
        let m = spectrum(spikeHz: 6000, sampleRate: 44100, bins: 512)
        var levels = AudioLevels.silent
        for _ in 0..<10 { levels = a.process(magnitudes: m, sampleRate: 44100) }
        let lowEnergy = levels.spectrum.prefix(4).reduce(0, +)
        let highEnergy = levels.spectrum.suffix(4).reduce(0, +)
        XCTAssertGreaterThan(highEnergy, lowEnergy)
    }

    func testResetClearsBeatCount() {
        let a = AudioBandAnalyzer()
        for i in 0..<100 {
            let hz = 60.0
            let mag: Float = (i % 20 == 0) ? 4.0 : 0.2
            var m = spectrum(spikeHz: hz, sampleRate: 44100, bins: 512)
            m = m.map { $0 * mag }
            _ = a.process(magnitudes: m, sampleRate: 44100)
        }
        a.reset()
        let after = a.process(magnitudes: [Float](repeating: 0, count: 512), sampleRate: 44100)
        XCTAssertEqual(after.beatCount, 0)
    }
}
