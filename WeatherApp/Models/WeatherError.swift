import Foundation

enum WeatherError: LocalizedError, Sendable {
    case invalidURL
    case serverError(Int)
    case noData
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:            return "Ungültige URL"
        case .serverError(let c):    return "Serverfehler (HTTP \(c))"
        case .noData:                return "Keine Daten verfügbar"
        case .networkError(let msg): return msg
        }
    }
}
