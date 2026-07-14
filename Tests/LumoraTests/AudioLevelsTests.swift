import XCTest
@testable import LumoraKit

final class AudioLevelsTests: XCTestCase {
    func testSilentHasEmptySpectrumAndNoBeats() {
        let s = AudioLevels.silent
        XCTAssertEqual(s.spectrum, [])
        XCTAssertEqual(s.beatCount, 0)
        XCTAssertEqual(s.beatStrength, 0)
    }

    func testExistingInitStillWorksWithoutNewFields() {
        let l = AudioLevels(bass: 0.5, mid: 0.4, treble: 0.3, overall: 0.4)
        XCTAssertEqual(l.spectrum, [])
        XCTAssertEqual(l.beatCount, 0)
    }

    func testNewFieldsRoundTrip() {
        let l = AudioLevels(bass: 0, mid: 0, treble: 0, overall: 0,
                            spectrum: [0.1, 0.2], beatCount: 3, beatStrength: 0.7)
        XCTAssertEqual(l.spectrum, [0.1, 0.2])
        XCTAssertEqual(l.beatCount, 3)
        XCTAssertEqual(l.beatStrength, 0.7)
    }
}
