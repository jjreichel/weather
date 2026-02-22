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

    // MARK: - Grid-Daten

    var currentGrid: WeatherGrid?
    var selectedHourIndex: Int = 0
    var isLoadingGrid = false

    private let gridService = GridFetchService()
    private var gridTask: Task<Void, Never>?

    func loadGrid(for mapRegion: MKCoordinateRegion) async {
        gridTask?.cancel()
        let region = GridRegion(from: mapRegion)
        isLoadingGrid = true
        gridTask = Task {
            let grid = try? await gridService.fetchGrid(region: region, model: selectedModel)
            guard !Task.isCancelled else { return }
            self.currentGrid = grid
            self.isLoadingGrid = false
        }
        await gridTask?.value
    }

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
