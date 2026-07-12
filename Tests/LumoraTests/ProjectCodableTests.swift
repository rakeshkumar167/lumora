import XCTest
@testable import LumoraKit

final class ProjectCodableTests: XCTestCase {
    // Old .lumora files have no `lightLines` key; they must still decode.
    func testDecodesLegacyProjectWithoutLightLines() throws {
        let json = """
        { "surfaces": [] }
        """.data(using: .utf8)!
        let project = try JSONDecoder().decode(Project.self, from: json)
        XCTAssertEqual(project.scenes.count, 1)
        XCTAssertEqual(project.scenes[0].surfaces.count, 0)
        XCTAssertEqual(project.scenes[0].lightLines.count, 0)
    }

    // A legacy flat project (surfaces + lightLines, no scenes) loads as one scene.
    func testDecodesLegacyFlatProjectAsSingleScene() throws {
        let a = UUID(), b = UUID()
        let line = LightLine(
            name: "L1",
            joints: [.init(id: a, point: .init(x: 0.1, y: 0.1)), .init(id: b, point: .init(x: 0.9, y: 0.9))],
            segments: [.init(a: a, b: b)],
            sourceJointID: a
        )
        // Encode a legacy-shaped payload (flat surfaces + lightLines, no scenes).
        struct LegacyProject: Encodable { let surfaces: [Surface]; let lightLines: [LightLine] }
        let data = try JSONEncoder().encode(LegacyProject(surfaces: [], lightLines: [line]))
        let project = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(project.scenes.count, 1)
        XCTAssertEqual(project.scenes[0].lightLines, [line])
    }

    func testRoundTripsScenes() throws {
        let s1 = ProjectScene(name: "Intro", surfaces: [Surface.defaultRect(name: "A")], duration: 12)
        let s2 = ProjectScene(name: "Main", surfaces: [], duration: 20)
        let project = Project(scenes: [s1, s2])
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(decoded.scenes.count, 2)
        XCTAssertEqual(decoded.scenes[0].name, "Intro")
        XCTAssertEqual(decoded.scenes[0].duration, 12)
        XCTAssertEqual(decoded.scenes[1].name, "Main")
        XCTAssertEqual(decoded, project)
    }
}

final class SceneTimelineTests: XCTestCase {
    func testWithinScenesAndBoundaries() {
        let d = [5.0, 10.0, 15.0]
        XCTAssertEqual(SceneTimeline.index(at: 0, durations: d), 0)
        XCTAssertEqual(SceneTimeline.index(at: 4.9, durations: d), 0)
        XCTAssertEqual(SceneTimeline.index(at: 5.0, durations: d), 1)   // boundary → next
        XCTAssertEqual(SceneTimeline.index(at: 14.9, durations: d), 1)
        XCTAssertEqual(SceneTimeline.index(at: 15.0, durations: d), 2)
        XCTAssertEqual(SceneTimeline.index(at: 29.9, durations: d), 2)
    }

    func testWrapsPastTheEnd() {
        let d = [5.0, 10.0, 15.0]   // total 30
        XCTAssertEqual(SceneTimeline.index(at: 30.0, durations: d), 0)
        XCTAssertEqual(SceneTimeline.index(at: 31.0, durations: d), 0)
        XCTAssertEqual(SceneTimeline.index(at: 36.0, durations: d), 1)
    }

    func testEmptyAndSingle() {
        XCTAssertEqual(SceneTimeline.index(at: 3, durations: []), 0)
        XCTAssertEqual(SceneTimeline.index(at: 999, durations: [10]), 0)
    }

    func testZeroDurationDoesNotStall() {
        // Zero clamps to the 1s minimum, so the second scene is still reachable.
        let d = [0.0, 5.0]
        XCTAssertEqual(SceneTimeline.index(at: 0.5, durations: d), 0)
        XCTAssertEqual(SceneTimeline.index(at: 2.0, durations: d), 1)
    }
}
