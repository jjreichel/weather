import Foundation

struct BrightSkyCurrentResponse: Decodable {
    let weather: BrightSkyWeather
    let sources: [BrightSkySource]

    struct BrightSkyWeather: Decodable {
        let timestamp: String
        let temperature: Double?
        let precipitation10: Double?
        let windSpeed10: Double?
        let windDirection10: Int?
        let cloudCover: Int?
        let condition: String?
        let icon: String?

        enum CodingKeys: String, CodingKey {
            case timestamp
            case temperature
            case precipitation10  = "precipitation_10"
            case windSpeed10      = "wind_speed_10"
            case windDirection10  = "wind_direction_10"
            case cloudCover       = "cloud_cover"
            case condition
            case icon
        }

        func toObservation(stationName: String) -> Observation {
            let formatter = ISO8601DateFormatter()
            let time = formatter.date(from: timestamp) ?? Date()
            return Observation(
                stationName: stationName,
                time: time,
                temperature: temperature,
                precipitation: precipitation10,
                windSpeed: windSpeed10,
                windDirection: windDirection10.map { Double($0) },
                cloudCover: cloudCover.map { Double($0) },
                condition: condition,
                icon: icon
            )
        }
    }

    struct BrightSkySource: Decodable {
        let stationName: String?

        enum CodingKeys: String, CodingKey {
            case stationName = "station_name"
        }
    }
}

actor BrightSkyService {
    private let baseURL = URL(string: "https://api.brightsky.dev")!
    private let session: URLSession

    init(session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()) {
        self.session = session
    }

    func fetchCurrentObservation(for location: Location) async throws -> Observation {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("current_weather"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(location.latitude)),
            URLQueryItem(name: "lon", value: String(location.longitude)),
        ]
        guard let url = components.url else { throw WeatherError.invalidURL }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw WeatherError.serverError(http.statusCode)
        }
        let raw = try JSONDecoder().decode(BrightSkyCurrentResponse.self, from: data)
        let stationName = raw.sources.first?.stationName ?? "Unbekannte Station"
        return raw.weather.toObservation(stationName: stationName)
    }
}
