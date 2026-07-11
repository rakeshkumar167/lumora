import SwiftUI
import LumoraKit

/// Digital clock with live weather. Shows the real local time (reconstructed from
/// the global animation clock), the date, and a weather line (icon + temperature +
/// city) sourced from the shared `WeatherStore`. Scales to the surface size.
struct DigitalClockView: View {
    let color: RGBAColor
    let accent: RGBAColor
    let time: Double

    @ObservedObject private var weather = WeatherStore.shared

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .medium; f.dateStyle = .none; return f
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEEEMMMd"); return f
    }()

    var body: some View {
        let date = Date(timeIntervalSinceReferenceDate: time)
        GeometryReader { geo in
            let base = min(geo.size.width, geo.size.height)
            VStack(spacing: base * 0.04) {
                Text(Self.timeFormatter.string(from: date))
                    .font(.system(size: base * 0.19, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color.color)
                Text(Self.dateFormatter.string(from: date))
                    .font(.system(size: base * 0.075, weight: .medium, design: .rounded))
                    .foregroundStyle(color.color.opacity(0.8))
                weatherLine(base: base)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black)
        .onAppear { weather.start() }
    }

    @ViewBuilder private func weatherLine(base: CGFloat) -> some View {
        if let snap = weather.snapshot {
            HStack(spacing: base * 0.03) {
                Image(systemName: Self.icon(code: snap.weatherCode, isDay: snap.isDay))
                    .symbolRenderingMode(.hierarchical)
                Text("\(Int(snap.temperature.rounded()))°\(weather.unitSymbol)")
                    .fontWeight(.semibold)
                if !snap.place.isEmpty {
                    Text(snap.place).foregroundStyle(accent.color.opacity(0.75))
                }
            }
            .font(.system(size: base * 0.085, weight: .medium, design: .rounded))
            .foregroundStyle(accent.color)
        } else {
            Text("Loading weather…")
                .font(.system(size: base * 0.06, design: .rounded))
                .foregroundStyle(accent.color.opacity(0.5))
        }
    }

    /// WMO weather code → SF Symbol (day/night variants where it matters).
    static func icon(code: Int, isDay: Bool) -> String {
        switch code {
        case 0, 1: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2:    return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:    return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57, 66, 67: return "cloud.sleet.fill"
        case 61, 63, 65: return "cloud.rain.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}
