import SwiftUI

extension WeatherLayer {
    /// Farbstopp für Legende und Overlay (RGB 0…255).
    struct ColorStop: Sendable {
        let value: Double
        let label: String
        let rgb: (Int, Int, Int)
    }

    var unit: String {
        switch self {
        case .temperature:   return "°C"
        case .precipitation: return "mm/h"
        case .wind:          return "km/h"
        case .cloudCover:    return "%"
        case .wave:          return "m"
        case .cape:          return "J/kg"
        }
    }

    var legendStops: [ColorStop] {
        switch self {
        case .temperature:
            return [
                ColorStop(value: -20, label: "-20", rgb: (0, 0, 200)),
                ColorStop(value: 4,   label: "4",   rgb: (0, 200, 200)),
                ColorStop(value: 16,  label: "16",  rgb: (50, 200, 50)),
                ColorStop(value: 28,  label: "28",  rgb: (230, 200, 0)),
                ColorStop(value: 40,  label: "40",  rgb: (200, 0, 0)),
            ]
        case .wind:
            return [
                ColorStop(value: 0,  label: "0",  rgb: (0, 180, 0)),
                ColorStop(value: 30, label: "30", rgb: (220, 220, 0)),
                ColorStop(value: 60, label: "60", rgb: (200, 0, 0)),
            ]
        case .precipitation:
            return [
                ColorStop(value: 0,  label: "0",  rgb: (230, 230, 255)),
                ColorStop(value: 3,  label: "3",  rgb: (0, 100, 255)),
                ColorStop(value: 10, label: "10", rgb: (0, 0, 150)),
            ]
        case .cloudCover:
            return [
                ColorStop(value: 0,   label: "0",   rgb: (200, 200, 150)),
                ColorStop(value: 50,  label: "50",  rgb: (140, 140, 100)),
                ColorStop(value: 100, label: "100", rgb: (50, 50, 50)),
            ]
        case .wave:
            return [
                ColorStop(value: 0,  label: "0",  rgb: (200, 240, 255)),
                ColorStop(value: 5,  label: "5",  rgb: (100, 160, 220)),
                ColorStop(value: 10, label: "10", rgb: (0, 40, 160)),
            ]
        case .cape:
            return [
                ColorStop(value: 0,    label: "0",    rgb: (255, 255, 255)),
                ColorStop(value: 900,  label: "900",  rgb: (255, 200, 0)),
                ColorStop(value: 2100, label: "2100", rgb: (200, 0, 0)),
                ColorStop(value: 3000, label: "3000", rgb: (80, 0, 0)),
            ]
        }
    }

    func swiftUIColor(from rgb: (Int, Int, Int)) -> Color {
        Color(red: Double(rgb.0) / 255, green: Double(rgb.1) / 255, blue: Double(rgb.2) / 255)
    }

    func format(_ value: Double) -> String {
        switch self {
        case .temperature:   return String(format: "%.1f °C", value)
        case .precipitation: return String(format: "%.1f mm/h", value)
        case .wind:          return String(format: "%.0f km/h", value)
        case .cloudCover:    return String(format: "%.0f %%", value)
        case .wave:          return String(format: "%.1f m", value)
        case .cape:          return String(format: "%.0f J/kg", value)
        }
    }
}
