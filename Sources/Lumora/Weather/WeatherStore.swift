import Foundation

/// A selectable city with fixed coordinates, used to drive the weather lookup.
struct City: Identifiable, Hashable {
    let name: String
    let latitude: Double
    let longitude: Double
    var id: String { name }
}

/// Pre-populated list of major world cities offered in the Digital Clock's
/// City dropdown. Sorted alphabetically for the picker.
enum Cities {
    static let all: [City] = [
        City(name: "Amsterdam", latitude: 52.3676, longitude: 4.9041),
        City(name: "Auckland", latitude: -36.8485, longitude: 174.7633),
        City(name: "Bangalore", latitude: 12.9716, longitude: 77.5946),
        City(name: "Bangkok", latitude: 13.7563, longitude: 100.5018),
        City(name: "Barcelona", latitude: 41.3874, longitude: 2.1686),
        City(name: "Berlin", latitude: 52.5200, longitude: 13.4050),
        City(name: "Buenos Aires", latitude: -34.6037, longitude: -58.3816),
        City(name: "Cairo", latitude: 30.0444, longitude: 31.2357),
        City(name: "Cape Town", latitude: -33.9249, longitude: 18.4241),
        City(name: "Chicago", latitude: 41.8781, longitude: -87.6298),
        City(name: "Dallas", latitude: 32.7767, longitude: -96.7970),
        City(name: "Delhi", latitude: 28.6139, longitude: 77.2090),
        City(name: "Denver", latitude: 39.7392, longitude: -104.9903),
        City(name: "Dubai", latitude: 25.2048, longitude: 55.2708),
        City(name: "Dublin", latitude: 53.3498, longitude: -6.2603),
        City(name: "Hong Kong", latitude: 22.3193, longitude: 114.1694),
        City(name: "Istanbul", latitude: 41.0082, longitude: 28.9784),
        City(name: "Jakarta", latitude: -6.2088, longitude: 106.8456),
        City(name: "Johannesburg", latitude: -26.2041, longitude: 28.0473),
        City(name: "London", latitude: 51.5074, longitude: -0.1278),
        City(name: "Los Angeles", latitude: 34.0522, longitude: -118.2437),
        City(name: "Madrid", latitude: 40.4168, longitude: -3.7038),
        City(name: "Melbourne", latitude: -37.8136, longitude: 144.9631),
        City(name: "Mexico City", latitude: 19.4326, longitude: -99.1332),
        City(name: "Miami", latitude: 25.7617, longitude: -80.1918),
        City(name: "Moscow", latitude: 55.7558, longitude: 37.6173),
        City(name: "Mumbai", latitude: 19.0760, longitude: 72.8777),
        City(name: "New York", latitude: 40.7128, longitude: -74.0060),
        City(name: "Paris", latitude: 48.8566, longitude: 2.3522),
        City(name: "Rio de Janeiro", latitude: -22.9068, longitude: -43.1729),
        City(name: "Rome", latitude: 41.9028, longitude: 12.4964),
        City(name: "San Francisco", latitude: 37.7749, longitude: -122.4194),
        City(name: "São Paulo", latitude: -23.5558, longitude: -46.6396),
        City(name: "Seattle", latitude: 47.6062, longitude: -122.3321),
        City(name: "Seoul", latitude: 37.5665, longitude: 126.9780),
        City(name: "Shanghai", latitude: 31.2304, longitude: 121.4737),
        City(name: "Singapore", latitude: 1.3521, longitude: 103.8198),
        City(name: "Sydney", latitude: -33.8688, longitude: 151.2093),
        City(name: "Tokyo", latitude: 35.6762, longitude: 139.6503),
        City(name: "Toronto", latitude: 43.6532, longitude: -79.3832),
        City(name: "Vancouver", latitude: 49.2827, longitude: -123.1207),
    ]

    static let `default`: City = all.first { $0.name == "San Francisco" } ?? all[0]
}

/// A resolved current-weather reading for display by the Digital Clock effect.
struct WeatherSnapshot: Equatable {
    var temperature: Double   // already in the display unit (°C or °F)
    var weatherCode: Int      // WMO weather interpretation code
    var isDay: Bool
    var place: String         // city name
}

/// Shared, app-wide weather provider. The user picks a city (persisted); this
/// fetches current conditions from the free, key-less Open-Meteo API, caches one
/// snapshot, and refreshes periodically.
@MainActor
final class WeatherStore: ObservableObject {
    static let shared = WeatherStore()

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published var selectedCity: City {
        didSet {
            guard oldValue != selectedCity else { return }
            UserDefaults.standard.set(selectedCity.name, forKey: Self.cityKey)
            snapshot = nil
            lastFetch = nil
            fetch(force: true)
        }
    }

    private static let cityKey = "lumora.weather.city"
    private let refreshInterval: TimeInterval = 15 * 60
    private var lastFetch: Date?
    private var startedTimer = false

    /// US locales get Fahrenheit; everyone else Celsius.
    private var useFahrenheit: Bool { Locale.current.measurementSystem == .us }
    var unitSymbol: String { useFahrenheit ? "F" : "C" }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.cityKey)
        selectedCity = Cities.all.first { $0.name == saved } ?? Cities.default
    }

    /// Idempotent — safe to call from every `.onAppear`.
    func start() {
        fetch()
        guard !startedTimer else { return }
        startedTimer = true
        Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fetch(force: true) }
        }
    }

    private func fetch(force: Bool = false) {
        if !force, let last = lastFetch, Date().timeIntervalSince(last) < refreshInterval, snapshot != nil { return }
        lastFetch = Date()

        let city = selectedCity
        let unit = useFahrenheit ? "fahrenheit" : "celsius"
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(city.latitude)&longitude=\(city.longitude)&current=temperature_2m,weather_code,is_day&temperature_unit=\(unit)&timezone=auto"
        guard let url = URL(string: urlString) else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
                let snap = WeatherSnapshot(
                    temperature: decoded.current.temperature_2m,
                    weatherCode: decoded.current.weather_code,
                    isDay: decoded.current.is_day == 1,
                    place: city.name)
                await MainActor.run {
                    // Ignore a stale response if the user changed city mid-flight.
                    if self.selectedCity == city { self.snapshot = snap }
                }
            } catch {
                // Keep any previous snapshot; allow a retry on the next tick.
                await MainActor.run { self.lastFetch = nil }
            }
        }
    }
}

/// Minimal decoder for Open-Meteo's `current` block.
private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let is_day: Int
    }
    let current: Current
}
