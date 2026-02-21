import Foundation

struct WeatherForecast: Equatable, Sendable {
    let location: Location
    let model: WeatherModel
    let hourly: [HourlyEntry]

    struct HourlyEntry: Equatable, Sendable {
        let time: Date
        let temperature: Double?   // °C
        let precipitation: Double? // mm
        let windSpeed: Double?     // km/h
        let windDirection: Double? // Grad
        let cloudCover: Double?    // %
    }
}
