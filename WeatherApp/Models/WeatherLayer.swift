enum WeatherLayer: String, CaseIterable, Identifiable, Sendable {
    case temperature
    case precipitation
    case wind
    case cloudCover

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .temperature:   return "Temperatur"
        case .precipitation: return "Niederschlag"
        case .wind:          return "Wind"
        case .cloudCover:    return "Bewölkung"
        }
    }
}
