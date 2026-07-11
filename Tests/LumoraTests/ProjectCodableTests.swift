import XCTest
@testable import LumoraKit

final class ProjectCodableTests: XCTestCase {
    // Old .lumora files have no `lightLines` key; they must still decode.
    func testDecodesLegacyProjectWithoutLightLines() throws {
        let json = """
        { "surfaces": [] }
        """.data(using: .utf8)!
        let project = try JSONDecoder().decode(Project.self, from: json)
        XCTAssertEqual(project.surfaces.count, 0)
        XCTAssertEqual(project.lightLines.count, 0)
    }

    func testRoundTripsLightLines() throws {
        let a = UUID(), b = UUID()
        let line = LightLine(
            name: "L1",
            joints: [.init(id: a, point: .init(x: 0.1, y: 0.1)), .init(id: b, point: .init(x: 0.9, y: 0.9))],
            segments: [.init(a: a, b: b)],
            sourceJointID: a
        )
        let project = Project(surfaces: [], lightLines: [line])
        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: data)
        XCTAssertEqual(decoded.lightLines, [line])
    }
}
