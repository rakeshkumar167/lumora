import XCTest
@testable import LumoraKit

final class CountdownConfigTests: XCTestCase {
    func testDefaults() {
        let c = CountdownConfig()
        XCTAssertEqual(c.label, "")
        XCTAssertTrue(c.finale)
        XCTAssertGreaterThan(c.target, Date())   // default target is in the future (next midnight)
    }
    func testRoundTrips() throws {
        let c = CountdownConfig(target: Date(timeIntervalSince1970: 1_900_000_000), label: "NYE", finale: false)
        let back = try JSONDecoder().decode(CountdownConfig.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back, c)
    }
    func testMissingKeysDefault() throws {
        let json = "{}".data(using: .utf8)!
        let c = try JSONDecoder().decode(CountdownConfig.self, from: json)
        XCTAssertEqual(c.label, "")
        XCTAssertTrue(c.finale)
    }
}
