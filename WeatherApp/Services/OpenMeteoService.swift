import Foundation

// Internes Decodierungsmodell – nicht exportiert
struct OpenMeteoResponse: Decodable {
    let hourly: HourlyData

    struct HourlyData: Decodable {
        let time: [String]
        let temperature2m: [Double?]
        let precipitation: [Double?]
        let windspeed10m: [Double?]
        let winddirection10m: [Double?]
        let cloudcover: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m    = "temperature_2m"
            case precipitation
            case windspeed10m     = "windspeed_10m"
            case winddirection10m = "winddirection_10m"
            case cloudcover
        }
    }

    func toForecast(location: Location, model: WeatherModel) -> WeatherForecast {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let entries: [WeatherForecast.HourlyEntry] = hourly.time.enumerated().compactMap { (i, str) in
            guard let date = formatter.date(from: str) else { return nil }
            return WeatherForecast.HourlyEntry(
                time: date,
                temperature: hourly.temperature2m[safe: i] ?? nil,
                precipitation: hourly.precipitation[safe: i] ?? nil,
                windSpeed: hourly.windspeed10m[safe: i] ?? nil,
                windDirection: hourly.winddirection10m[safe: i] ?? nil,
                cloudCover: hourly.cloudcover[safe: i] ?? nil
            )
        }
        return WeatherForecast(location: location, model: model, hourly: entries)
    }
}

actor OpenMeteoService {
    private let baseURL = URL(string: "https://api.open-meteo.com/v1/forecast")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    func fetchForecast(for location: Location, model: WeatherModel) async throws -> WeatherForecast {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude",      value: String(location.latitude)),
            URLQueryItem(name: "longitude",     value: String(location.longitude)),
            URLQueryItem(name: "hourly",        value: "temperature_2m,precipitation,windspeed_10m,winddirection_10m,cloudcover"),
            URLQueryItem(name: "models",        value: model.rawValue),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone",      value: "auto"),
        ]
        guard let url = components.url else { throw WeatherError.invalidURL }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw WeatherError.serverError(http.statusCode)
        }
        let raw = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return raw.toForecast(location: location, model: model)
    }
}

// Hilfserweiterung für sicheren Array-Zugriff
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
