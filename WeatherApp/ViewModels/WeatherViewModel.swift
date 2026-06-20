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
    var gridInspection: GridInspection?

    private let gridService = GridFetchService()
    private var gridTask: Task<Void, Never>?
    private var gridGeneration = 0
    private(set) var lastMapRegion: MKCoordinateRegion?

    func loadGrid(for mapRegion: MKCoordinateRegion) {
        gridTask?.cancel()
        lastMapRegion = mapRegion
        let region = GridRegion(from: mapRegion)
        let model  = selectedModel          // Snapshot: Modell zum Aufrufzeitpunkt erfassen
        isLoadingGrid = true
        gridGeneration += 1
        let generation = gridGeneration
        gridTask = Task {
            let grid = try? await gridService.fetchGrid(region: region, model: model)
            guard !Task.isCancelled, generation == self.gridGeneration else { return }
            self.currentGrid = grid
            self.gridInspection = nil
            self.clampSelectedHourIndex()
            self.isLoadingGrid = false
        }
    }

    /// Grid für die zuletzt sichtbare Kartenregion neu laden (z. B. nach Modellwechsel).
    func reloadGridForCurrentRegion() {
        guard let region = lastMapRegion else { return }
        loadGrid(for: region)
    }

    private func clampSelectedHourIndex() {
        guard let grid = currentGrid else { return }
        selectedHourIndex = min(selectedHourIndex, max(0, grid.times.count - 1))
    }

    func inspectGrid(at coordinate: CLLocationCoordinate2D) {
        guard let grid = currentGrid else { return }
        gridInspection = grid.inspection(at: coordinate.latitude, longitude: coordinate.longitude)
    }

    func clearGridInspection() {
        gridInspection = nil
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
