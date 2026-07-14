import XCTest
@testable import LumoraKit

final class BeatDetectorTests: XCTestCase {
    func testSteadyLevelProducesNoBeats() {
        let d = BeatDetector()
        var beats = 0
        for _ in 0..<200 { if d.process(bass: 0.4).isBeat { beats += 1 } }
        XCTAssertEqual(beats, 0)
    }

    func testNoiseFloorProducesNoBeats() {
        let d = BeatDetector()
        var beats = 0
        for i in 0..<200 { if d.process(bass: 0.02 + 0.01 * Double(i % 3)).isBeat { beats += 1 } }
        XCTAssertEqual(beats, 0, "levels under the absolute floor must not fire")
    }

    func testPeriodicSpikesFireOnceEach() {
        let d = BeatDetector()
        var beats = 0
        // Quiet baseline with a sharp spike every 20 frames.
        for i in 0..<200 {
            let level = (i % 20 == 0) ? 0.9 : 0.1
            if d.process(bass: level).isBeat { beats += 1 }
        }
        // 10 spikes; allow the first to be swallowed while history warms up.
        XCTAssertGreaterThanOrEqual(beats, 8)
        XCTAssertLessThanOrEqual(beats, 10)
    }

    func testRefractorySuppressesAdjacentFrames() {
        let d = BeatDetector(refractory: 8)
        var beats = 0
        // Two consecutive loud frames should count as ONE beat.
        for i in 0..<40 {
            let level = (i == 20 || i == 21) ? 0.9 : 0.1
            if d.process(bass: level).isBeat { beats += 1 }
        }
        XCTAssertEqual(beats, 1)
    }

    func testStrengthIsBoundedAndPositiveOnBeat() {
        let d = BeatDetector()
        var maxStrength = 0.0
        for i in 0..<100 {
            let r = d.process(bass: (i % 25 == 0) ? 0.95 : 0.1)
            if r.isBeat { maxStrength = max(maxStrength, r.strength) }
        }
        XCTAssertGreaterThan(maxStrength, 0)
        XCTAssertLessThanOrEqual(maxStrength, 1.0)
    }
}
