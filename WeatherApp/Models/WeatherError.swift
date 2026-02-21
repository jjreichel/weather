import Foundation

enum WeatherError: LocalizedError, Sendable {
    case invalidURL
    case serverError(Int)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL:         return "Ungültige URL"
        case .serverError(let c): return "Serverfehler (HTTP \(c))"
        case .noData:             return "Keine Daten verfügbar"
        }
    }
}
