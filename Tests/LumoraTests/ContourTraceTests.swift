import CoreGraphics
import Foundation
import XCTest
@testable import LumoraKit

final class ContourTraceTests: XCTestCase {
    func testContourTraceCodableRoundTrip() throws {
        let media = MediaAssignment.contourTrace(
            [URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/b.png")],
            .green, 1.5, true)
        let data = try JSONEncoder().encode(media)
        let back = try JSONDecoder().decode(MediaAssignment.self, from: data)
        XCTAssertEqual(media, back)
    }

    func testRainbowBandInRange() {
        for i in 0...100 {
            let b = ContourTrace.rainbowBand(length: CGFloat(i), total: 100, phase: 0)
            XCTAssertGreaterThanOrEqual(b, 0)
            XCTAssertLessThan(b, ContourTrace.rainbowBandCount)
        }
    }

    func testRainbowBandMonotonicAcrossOnePass() {
        let a = ContourTrace.rainbowBand(length: 0, total: 100, phase: 0)
        let mid = ContourTrace.rainbowBand(length: 50, total: 100, phase: 0)
        let end = ContourTrace.rainbowBand(length: 99, total: 100, phase: 0)
        XCTAssertEqual(a, 0)
        XCTAssertGreaterThan(mid, a)
        XCTAssertGreaterThan(end, mid)
    }

    func testRainbowBandWrapsWithPhase() {
        // A full phase of 1.0 wraps back to the same band as phase 0.
        let base = ContourTrace.rainbowBand(length: 25, total: 100, phase: 0)
        let wrapped = ContourTrace.rainbowBand(length: 25, total: 100, phase: 1.0)
        XCTAssertEqual(base, wrapped)
    }
}
