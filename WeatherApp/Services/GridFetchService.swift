import Foundation
import MapKit

// MARK: - Interne Decodiermodelle

private struct ForecastGridResponse: Decodable {
    let hourly: HourlyData

    struct HourlyData: Decodable {
        let time:             [String]
        let temperature2m:    [Double?]
        let windSpeed10m:     [Double?]
        let windDirection10m: [Double?]
        let precipitation:    [Double?]
        let cape:             [Double?]
        let cloudCover:       [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m    = "temperature_2m"
            case windSpeed10m     = "wind_speed_10m"
            case windDirection10m = "wind_direction_10m"
            case precipitation
            case cape
            case cloudCover       = "cloud_cover"
        }
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    var times: [Date] {
        hourly.time.compactMap { ForecastGridResponse.fmt.date(from: $0) }
    }
}

private struct MarineGridResponse: Decodable {
    let hourly: HourlyData

    struct HourlyData: Decodable {
        let waveHeight: [Double?]
        enum CodingKeys: String, CodingKey {
            case waveHeight = "wave_height"
        }
    }
}

// MARK: - Service

actor GridFetchService {
    private let forecastBase = URL(string: "https://api.open-meteo.com/v1/forecast")!
    private let marineBase   = URL(string: "https://marine-api.open-meteo.com/v1/marine")!
    private let session: URLSession

    init(session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()) { self.session = session }

    func fetchGrid(
        region: GridRegion,
        model: WeatherModel,
        onProgress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) async throws -> WeatherGrid {
        let points = region.allIndices
        let nTotal = points.count

        typealias PointResult = (pointIdx: Int, forecast: ForecastGridResponse?, marine: MarineGridResponse?)
        var completed = 0
        let results: [PointResult] = await withTaskGroup(of: PointResult.self) { group in
            for (ix, iy) in points {
                group.addTask {
                    let lat = region.latitude(iy: iy)
                    let lon = region.longitude(ix: ix)
                    let idx = region.index(ix: ix, iy: iy)
                    let forecast = try? await self.fetchForecast(lat: lat, lon: lon, model: model)
                    let marine   = try? await self.fetchMarine(lat: lat, lon: lon)
                    return (idx, forecast, marine)
                }
            }
            var out: [PointResult] = []
            for await r in group {
                out.append(r)
                completed += 1
                onProgress(completed, nTotal)
            }
            return out
        }

        let times = results.compactMap { $0.forecast?.times }.first ?? []
        let nHours = times.count

        var tempData  = Array(repeating: Array(repeating: Optional<Double>.none, count: nTotal), count: nHours)
        var windData  = Array(repeating: Array(repeating: Optional<Double>.none, count: nTotal), count: nHours)
        var windDir   = Array(repeating: Array(repeating: Optional<Double>.none, count: nTotal), count: nHours)
        var precData  = Array(repeating: Array(repeating: Optional<Double>.none, count: nTotal), count: nHours)
        var capeData  = Array(repeating: Array(repeating: Optional<Double>.none, count: nTotal), count: nHours)
        var cloudData = Array(repeating: Array(repeating: Optional<Double>.none, count: nTotal), count: nHours)
        var waveData  = Array(repeating: Array(repeating: Optional<Double>.none, count: nTotal), count: nHours)

        for r in results {
            guard let fc = r.forecast else { continue }
            let i = r.pointIdx
            let h = fc.hourly
            for t in 0..<min(nHours, h.temperature2m.count) {
                tempData[t][i]  = h.temperature2m[safe: t].flatMap { $0 }
                windData[t][i]  = h.windSpeed10m[safe: t].flatMap { $0 }
                windDir[t][i]   = h.windDirection10m[safe: t].flatMap { $0 }
                precData[t][i]  = h.precipitation[safe: t].flatMap { $0 }
                capeData[t][i]  = h.cape[safe: t].flatMap { $0 }
                cloudData[t][i] = h.cloudCover[safe: t].flatMap { $0 }
            }
            if let m = r.marine {
                for t in 0..<min(nHours, m.hourly.waveHeight.count) {
                    waveData[t][i] = m.hourly.waveHeight[safe: t].flatMap { $0 }
                }
            }
        }

        let data: [WeatherLayer: [[Double?]]] = [
            .temperature:   tempData,
            .wind:          windData,
            .precipitation: precData,
            .cape:          capeData,
            .cloudCover:    cloudData,
            .wave:          waveData,
        ]

        return WeatherGrid(region: region, model: model, times: times, data: data, windDirection: windDir)
    }

    // MARK: - Private API-Aufrufe

    private func fetchForecast(lat: Double, lon: Double, model: WeatherModel) async throws -> ForecastGridResponse {
        var c = URLComponents(url: forecastBase, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "latitude",      value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude",     value: String(format: "%.4f", lon)),
            URLQueryItem(name: "hourly",        value: "temperature_2m,wind_speed_10m,wind_direction_10m,precipitation,cape,cloud_cover"),
            URLQueryItem(name: "models",        value: model.rawValue),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone",      value: "UTC"),
        ]
        let (data, _) = try await session.data(from: c.url!)
        return try JSONDecoder().decode(ForecastGridResponse.self, from: data)
    }

    private func fetchMarine(lat: Double, lon: Double) async throws -> MarineGridResponse {
        var c = URLComponents(url: marineBase, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "latitude",      value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude",     value: String(format: "%.4f", lon)),
            URLQueryItem(name: "hourly",        value: "wave_height"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone",      value: "UTC"),
        ]
        let (data, _) = try await session.data(from: c.url!)
        return try JSONDecoder().decode(MarineGridResponse.self, from: data)
    }
}
