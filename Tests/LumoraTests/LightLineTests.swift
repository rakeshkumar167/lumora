import CoreGraphics
import XCTest
@testable import LumoraKit

final class LightLineTests: XCTestCase {
    // Helpers to build a line with known joints/segments.
    private func line(joints: [(UUID, CGPoint)], edges: [(UUID, UUID)], source: UUID?) -> LightLine {
        LightLine(
            name: "T",
            joints: joints.map { LightLine.Joint(id: $0.0, point: $0.1) },
            segments: edges.map { LightLine.Segment(a: $0.0, b: $0.1) },
            sourceJointID: source
        )
    }

    func testDistancesAlongAChain() {
        let a = UUID(), b = UUID(), c = UUID()
        // A(0,0) - B(0.5,0) - C(1,0); each segment length 0.5.
        let l = line(joints: [(a, CGPoint(x: 0, y: 0)), (b, CGPoint(x: 0.5, y: 0)), (c, CGPoint(x: 1, y: 0))],
                     edges: [(a, b), (b, c)], source: a)
        let d = l.distancesFromSource()
        XCTAssertEqual(d[a]!, 0, accuracy: 1e-9)
        XCTAssertEqual(d[b]!, 0.5, accuracy: 1e-9)
        XCTAssertEqual(d[c]!, 1.0, accuracy: 1e-9)
        XCTAssertEqual(l.maxDistance(), 1.0, accuracy: 1e-9)
    }

    func testForkDistancesAndDisconnectedJoint() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID(), lonely = UUID()
        // A(0,0)-B(0.4,0); B-C(0.4,0.3); B-D(0.4,-0.3). `lonely` has no edge.
        let l = line(joints: [(a, CGPoint(x: 0, y: 0)), (b, CGPoint(x: 0.4, y: 0)),
                              (c, CGPoint(x: 0.4, y: 0.3)), (d, CGPoint(x: 0.4, y: -0.3)),
                              (lonely, CGPoint(x: 0.9, y: 0.9))],
                     edges: [(a, b), (b, c), (b, d)], source: a)
        let dist = l.distancesFromSource()
        XCTAssertEqual(dist[a]!, 0, accuracy: 1e-9)
        XCTAssertEqual(dist[b]!, 0.4, accuracy: 1e-9)
        XCTAssertEqual(dist[c]!, 0.7, accuracy: 1e-9)
        XCTAssertEqual(dist[d]!, 0.7, accuracy: 1e-9)
        XCTAssertNil(dist[lonely]) // unreachable from source
    }

    func testLitFractionLightsFromNearEndpoint() {
        let a = UUID(), b = UUID(), c = UUID()
        let l = line(joints: [(a, CGPoint(x: 0, y: 0)), (b, CGPoint(x: 0.5, y: 0)), (c, CGPoint(x: 1, y: 0))],
                     edges: [(a, b), (b, c)], source: a)
        let dist = l.distancesFromSource()
        let bc = l.segments[1] // B-C, near endpoint B at distance 0.5, length 0.5
        // front hasn't reached B yet.
        XCTAssertEqual(l.litFraction(of: bc, front: 0.25, distances: dist), 0, accuracy: 1e-9)
        // front halfway across B-C.
        XCTAssertEqual(l.litFraction(of: bc, front: 0.75, distances: dist), 0.5, accuracy: 1e-9)
        // front past the far end → fully lit, clamped.
        XCTAssertEqual(l.litFraction(of: bc, front: 2.0, distances: dist), 1.0, accuracy: 1e-9)
    }

    func testLitFractionUnreachableSegmentIsZero() {
        // Source is nil → nothing reachable → every segment dark.
        let a = UUID(), b = UUID()
        let l = line(joints: [(a, CGPoint(x: 0, y: 0)), (b, CGPoint(x: 1, y: 0))],
                     edges: [(a, b)], source: nil)
        let dist = l.distancesFromSource()
        XCTAssertTrue(dist.isEmpty)
        XCTAssertEqual(l.litFraction(of: l.segments[0], front: 5, distances: dist), 0, accuracy: 1e-9)
    }

    func testFillCyclePhases() {
        let c = FillCycle(fillDuration: 2, holdDuration: 1) // period 3
        XCTAssertEqual(c.frontFraction(elapsed: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(c.frontFraction(elapsed: 1), 0.5, accuracy: 1e-9)   // mid-fill
        XCTAssertEqual(c.frontFraction(elapsed: 2), 1.0, accuracy: 1e-9)   // fill complete
        XCTAssertEqual(c.frontFraction(elapsed: 2.5), 1.0, accuracy: 1e-9) // hold
        XCTAssertEqual(c.frontFraction(elapsed: 3), 0, accuracy: 1e-9)     // reset (wrap)
        XCTAssertEqual(c.frontFraction(elapsed: 4), 0.5, accuracy: 1e-9)   // next cycle mid-fill
    }

    func testLitFractionZeroLengthSegment() {
        let a = UUID(), b = UUID(), c = UUID()
        // A(0,0) - B(0.5,0) - C(0.5,0); B-C is zero-length.
        let l = line(joints: [(a, CGPoint(x: 0, y: 0)), (b, CGPoint(x: 0.5, y: 0)), (c, CGPoint(x: 0.5, y: 0))],
                     edges: [(a, b), (b, c)], source: a)
        let dist = l.distancesFromSource()
        let bc = l.segments[1] // B-C, zero-length segment, near endpoint B at distance 0.5
        // front hasn't reached B yet.
        XCTAssertEqual(l.litFraction(of: bc, front: 0.25, distances: dist), 0, accuracy: 1e-9)
        // front at B (the near endpoint).
        XCTAssertEqual(l.litFraction(of: bc, front: 0.5, distances: dist), 1, accuracy: 1e-9)
        // front past B.
        XCTAssertEqual(l.litFraction(of: bc, front: 1.0, distances: dist), 1, accuracy: 1e-9)
    }

    func testCodableRoundTrip() throws {
        let a = UUID(), b = UUID()
        let original = line(joints: [(a, CGPoint(x: 0.1, y: 0.2)), (b, CGPoint(x: 0.8, y: 0.9))],
                            edges: [(a, b)], source: a)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LightLine.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testCycleClosingEdgeStaysDarkAtFullFill() {
        // Documents the accepted trade-off: in a symmetric loop, the closing edge
        // never lights because its nearer endpoint is already at maxDistance.
        let a = UUID(), b = UUID(), c = UUID()
        // Equilateral-ish triangle: A(0,0) source, B(1,0), C(0.5, 0.866)
        // with edges A–B, A–C, B–C.
        let l = line(
            joints: [
                (a, CGPoint(x: 0, y: 0)),
                (b, CGPoint(x: 1, y: 0)),
                (c, CGPoint(x: 0.5, y: 0.866))
            ],
            edges: [(a, b), (a, c), (b, c)],
            source: a
        )
        let d = l.distancesFromSource()
        let maxD = l.maxDistance()

        // Verify distances: A at source (0), B and C each ~1.0 (direct edge lengths).
        XCTAssertEqual(d[a]!, 0, accuracy: 1e-9)
        XCTAssertEqual(d[b]!, 1.0, accuracy: 1e-3)
        XCTAssertEqual(d[c]!, hypot(0.5, 0.866), accuracy: 1e-3)

        // The B–C segment (closing edge) is at segments[2] (added third).
        let bc = l.segments[2]
        // Even at full fill (front == maxD), the closing edge stays essentially dark
        // (lit fraction ~ 0) because its nearer endpoint is already at maxDistance.
        XCTAssertEqual(l.litFraction(of: bc, front: maxD, distances: d), 0, accuracy: 1e-4)
    }
}
