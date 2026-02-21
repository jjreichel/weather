import Foundation

struct Observation: Equatable, Sendable {
    let stationName: String
    let time: Date
    let temperature: Double?    // °C
    let precipitation: Double?  // mm
    let windSpeed: Double?      // km/h
    let windDirection: Double?  // Grad
    let cloudCover: Double?     // %
    let condition: String?
    let icon: String?
}
