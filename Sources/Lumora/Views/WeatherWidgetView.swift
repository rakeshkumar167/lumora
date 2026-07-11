import SwiftUI
import LumoraKit

/// An iOS-weather-widget-style card: a rounded rectangle with an opaque
/// day/night sky-gradient background showing the location, current time (no
/// seconds), a large temperature, and the condition. Driven by the shared
/// `WeatherStore` and the global animation clock.
struct WeatherWidgetView: View {
    let time: Double

    @ObservedObject private var weather = WeatherStore.shared

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEEEMMMd"); return f
    }()

    var body: some View {
        let date = Date(timeIntervalSinceReferenceDate: time)
        let snap = weather.snapshot
        let isDay = snap?.isDay ?? true
        GeometryReader { geo in
            let base = min(geo.size.width, geo.size.height)
            let pad = base * 0.12
            ZStack {
                RoundedRectangle(cornerRadius: base * 0.14, style: .continuous)
                    .fill(skyGradient(isDay: isDay))
                    .overlay(
                        RoundedRectangle(cornerRadius: base * 0.14, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: max(1, base * 0.006))
                    )

                VStack(alignment: .leading, spacing: base * 0.03) {
                    // Location + time.
                    HStack(spacing: base * 0.03) {
                        Image(systemName: "location.fill").font(.system(size: base * 0.06))
                        Text(snap?.place ?? weather.selectedCity.name)
                            .font(.system(size: base * 0.085, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Spacer()
                        Text(Self.timeFormatter.string(from: date))
                            .font(.system(size: base * 0.075, weight: .medium, design: .rounded))
                            .opacity(0.85)
                    }

                    // Big temperature.
                    HStack(alignment: .top, spacing: base * 0.02) {
                        Text(snap.map { "\(Int($0.temperature.rounded()))" } ?? "—")
                            .font(.system(size: base * 0.30, weight: .thin, design: .rounded))
                        Text("°\(weather.unitSymbol)")
                            .font(.system(size: base * 0.12, weight: .regular, design: .rounded))
                            .padding(.top, base * 0.04)
                    }

                    Spacer(minLength: 0)

                    // Condition icon + label + date.
                    HStack(spacing: base * 0.04) {
                        Image(systemName: DigitalClockView.icon(code: snap?.weatherCode ?? 3, isDay: isDay))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: base * 0.11))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(Self.condition(code: snap?.weatherCode ?? 3))
                                .font(.system(size: base * 0.07, weight: .semibold, design: .rounded))
                            Text(Self.dateFormatter.string(from: date))
                                .font(.system(size: base * 0.055, weight: .regular, design: .rounded))
                                .opacity(0.8)
                        }
                        Spacer()
                    }
                }
                .padding(pad)
                .foregroundStyle(.white)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear { weather.start() }
    }

    private func skyGradient(isDay: Bool) -> LinearGradient {
        let colors: [Color] = isDay
            ? [Color(red: 0.29, green: 0.56, blue: 0.89), Color(red: 0.53, green: 0.74, blue: 0.96)]
            : [Color(red: 0.08, green: 0.10, blue: 0.24), Color(red: 0.22, green: 0.20, blue: 0.40)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// WMO weather code → short human label.
    static func condition(code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mainly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73, 75, 77: return "Snow"
        case 80, 81, 82: return "Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm"
        default: return "—"
        }
    }
}
