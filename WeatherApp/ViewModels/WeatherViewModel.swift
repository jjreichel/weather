import Foundation
import MapKit
import Observation

@MainActor
@Observable
final class WeatherViewModel {
    var forecasts: [WeatherModel: WeatherForecast] = [:]
    var observation: StationObservation?
    var selectedModel: WeatherModel = .icon
    var selectedLayer: WeatherLayer = .temperature
    var isLoading = false
    var error: String?

    private let openMeteo = OpenMeteoService()
    private let brightSky = BrightSkyService()

    func loadAll(for location: Location) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        async let obs = fetchObservation(for: location)
        async let fc  = fetchAllForecasts(for: location)
        self.observation = await obs
        self.forecasts   = await fc
        if forecasts.isEmpty && observation == nil {
            error = "Wetterdaten konnten nicht geladen werden. Netzwerkverbindung prüfen."
        }
    }

    var currentForecast: WeatherForecast? {
        forecasts[selectedModel]
    }

    // MARK: - Grid-Daten (Task 6)
    var currentGrid: WeatherGrid? = nil
    var selectedHourIndex: Int = 0

    /// Lädt das Wetterdaten-Raster für die angezeigte Kartenregion (Stub — Task 6).
    func loadGrid(for region: MKCoordinateRegion) async {}

    private func fetchObservation(for location: Location) async -> StationObservation? {
        try? await brightSky.fetchCurrentObservation(for: location)
    }

    private func fetchAllForecasts(for location: Location) async -> [WeatherModel: WeatherForecast] {
        await withTaskGroup(of: (WeatherModel, WeatherForecast?).self) { group in
            for model in WeatherModel.allCases {
                group.addTask { [openMeteo] in
                    let forecast = try? await openMeteo.fetchForecast(for: location, model: model)
                    return (model, forecast)
                }
            }
            var result: [WeatherModel: WeatherForecast] = [:]
            for await (model, forecast) in group {
                if let forecast { result[model] = forecast }
            }
            return result
        }
    }
}
