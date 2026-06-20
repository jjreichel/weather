import Foundation

/// Anzeigeeinheit für Windgeschwindigkeit (intern immer km/h von Open-Meteo).
enum WindSpeedUnit: String, CaseIterable, Identifiable, Sendable {
    case kmh
    case knots
    case beaufort

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kmh:      return "km/h"
        case .knots:    return "kn"
        case .beaufort: return "Bft"
        }
    }

    /// Wert für Charts (kontinuierliche Skala).
    func chartValue(kmh: Double) -> Double {
        switch self {
        case .kmh:      return kmh
        case .knots:    return kmh / 1.852
        case .beaufort: return Double(beaufort(kmh: kmh))
        }
    }

    func format(kmh: Double) -> String {
        switch self {
        case .kmh:
            return String(format: "%.0f km/h", kmh)
        case .knots:
            return String(format: "%.0f kn", kmh / 1.852)
        case .beaufort:
            return "Bft \(beaufort(kmh: kmh))"
        }
    }

    /// Beschriftung für Legende (Windstopp intern in km/h).
    func legendLabel(forKmh kmh: Double) -> String {
        switch self {
        case .kmh:
            return String(format: "%.0f", kmh)
        case .knots:
            return String(format: "%.0f", kmh / 1.852)
        case .beaufort:
            return "\(beaufort(kmh: kmh))"
        }
    }

    /// Beaufort-Skala (WMO, Eingabe m/s via km/h).
    func beaufort(kmh: Double) -> Int {
        let ms = kmh / 3.6
        switch ms {
        case ..<0.3:  return 0
        case ..<1.6:  return 1
        case ..<3.4:  return 2
        case ..<5.5:  return 3
        case ..<8.0:  return 4
        case ..<10.8: return 5
        case ..<13.9: return 6
        case ..<17.2: return 7
        case ..<20.8: return 8
        case ..<24.5: return 9
        case ..<28.5: return 10
        case ..<32.7: return 11
        default:      return 12
        }
    }
}
