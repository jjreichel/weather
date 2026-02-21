import Foundation

// Internes Decodierungsmodell – nicht exportiert
struct OpenMeteoResponse: Decodable {
    let hourly: HourlyData

    private static let hourlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

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
        let entries: [WeatherForecast.HourlyEntry] = hourly.time.enumerated().compactMap { (i, str) in
            guard let date = OpenMeteoResponse.hourlyFormatter.date(from: str) else { return nil }
            return WeatherForecast.HourlyEntry(
                time: date,
                temperature: hourly.temperature2m[safe: i].flatMap { $0 },
                precipitation: hourly.precipitation[safe: i].flatMap { $0 },
                windSpeed: hourly.windspeed10m[safe: i].flatMap { $0 },
                windDirection: hourly.winddirection10m[safe: i].flatMap { $0 },
                cloudCover: hourly.cloudcover[safe: i].flatMap { $0 }
            )
        }
        return WeatherForecast(location: location, model: model, hourly: entries)
    }
}

actor OpenMeteoService {
    private let baseURL = URL(string: "https://api.open-meteo.com/v1/forecast")!
    private let session: URLSession

    init(session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()) {
        self.session = session
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
