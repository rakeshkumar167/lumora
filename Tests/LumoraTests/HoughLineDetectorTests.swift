import XCTest
import CoreGraphics
@testable import LumoraKit

final class HoughLineDetectorTests: XCTestCase {
    func testDetectedLineComputesAngleAndLength() {
        let l = DetectedLine(p1: CGPoint(x: 0, y: 0), p2: CGPoint(x: 3, y: 4))
        XCTAssertEqual(l.length, 5, accuracy: 1e-9)
        XCTAssertEqual(l.angle, atan2(4.0, 3.0), accuracy: 1e-9)
    }

    func testNormalizeAngleFoldsIntoZeroPi() {
        XCTAssertEqual(LineGeometry.normalizeAngle(-0.1), Double.pi - 0.1, accuracy: 1e-9)
        XCTAssertEqual(LineGeometry.normalizeAngle(Double.pi + 0.1), 0.1, accuracy: 1e-9)
    }

    func testAngleDifferenceIsAcute() {
        XCTAssertEqual(LineGeometry.angleDifference(0.1, Double.pi - 0.1), 0.2, accuracy: 1e-9)
        XCTAssertEqual(LineGeometry.angleDifference(0, Double.pi / 2), Double.pi / 2, accuracy: 1e-9)
    }

    /// EdgeMap with a single horizontal line of edge pixels at row `y0`.
    private func horizontalLineEdges(w: Int, h: Int, y0: Int, x0: Int, x1: Int) -> EdgeMap {
        var e = [Bool](repeating: false, count: w * h)
        for x in x0...x1 { e[y0 * w + x] = true }
        return EdgeMap(width: w, height: h, edges: e)
    }

    func testAccumulatorPeaksAtHorizontalLine() {
        let w = 60, h = 40, y0 = 20
        let edges = horizontalLineEdges(w: w, h: h, y0: y0, x0: 10, x1: 50)
        let cfg = HoughLineDetector.Config()
        let acc = HoughLineDetector.accumulate(edges, config: cfg)

        // Find the max cell.
        var best = -1, bestIdx = 0
        for i in acc.votes.indices where acc.votes[i] > best { best = acc.votes[i]; bestIdx = i }
        let theta = bestIdx / acc.rhoCount
        let rhoIdx = bestIdx % acc.rhoCount
        let thetaDeg = Double(theta) * cfg.thetaStepDeg
        let rho = acc.rhoMin + Double(rhoIdx) * cfg.rhoStep

        // A horizontal line has a vertical normal → θ ≈ 90°, ρ ≈ y0.
        XCTAssertEqual(thetaDeg, 90, accuracy: 2 * cfg.thetaStepDeg)
        XCTAssertEqual(rho, Double(y0), accuracy: 2 * cfg.rhoStep)
        XCTAssertGreaterThan(best, 30, "the whole segment should vote for one cell")
    }

    func testDetectsSingleHorizontalSegment() {
        let w = 60, h = 40
        let edges = horizontalLineEdges(w: w, h: h, y0: 20, x0: 10, x1: 50)
        let lines = HoughLineDetector.detect(edges)
        XCTAssertEqual(lines.count, 1, "one segment expected")
        let l = lines[0]
        XCTAssertEqual(LineGeometry.angleDifference(l.angle, 0), 0, accuracy: 0.05, "horizontal")
        XCTAssertEqual(l.length, 40, accuracy: 3)
        XCTAssertEqual(min(l.p1.y, l.p2.y), 20, accuracy: 1)
    }

    func testDetectsTwoPerpendicularSegments() {
        let w = 60, h = 60
        var e = [Bool](repeating: false, count: w * h)
        for x in 10...50 { e[30 * w + x] = true } // horizontal
        for y in 10...50 { e[y * w + 30] = true } // vertical
        let lines = HoughLineDetector.detect(EdgeMap(width: w, height: h, edges: e))
        XCTAssertGreaterThanOrEqual(lines.count, 2)
        // Some pair is ~perpendicular.
        var foundPerp = false
        for i in 0..<lines.count { for j in (i + 1)..<lines.count {
            if abs(LineGeometry.angleDifference(lines[i].angle, lines[j].angle) - .pi / 2) < 0.1 { foundPerp = true }
        } }
        XCTAssertTrue(foundPerp, "expected a perpendicular pair")
    }
}
