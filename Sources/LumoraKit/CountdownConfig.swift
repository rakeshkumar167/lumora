import Foundation

/// Customization for the Countdown Timer effect. Codable; stored on `Surface`.
public struct CountdownConfig: Equatable, Codable {
    public var target: Date       // when the countdown hits zero
    public var label: String      // optional caption shown under the digits
    public var finale: Bool       // fireworks burst at zero

    public init(target: Date = CountdownConfig.defaultTarget(), label: String = "", finale: Bool = true) {
        self.target = target; self.label = label; self.finale = finale
    }
    /// Next midnight (local) from now — a sensible default.
    public static func defaultTarget(now: Date = Date()) -> Date {
        let cal = Calendar.current
        let startOfTomorrow = cal.startOfDay(for: now.addingTimeInterval(86_400))
        return startOfTomorrow
    }
    private enum CodingKeys: String, CodingKey { case target, label, finale }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        target = try c.decodeIfPresent(Date.self, forKey: .target) ?? CountdownConfig.defaultTarget()
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        finale = try c.decodeIfPresent(Bool.self, forKey: .finale) ?? true
    }
}
