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
    var windSpeedUnit: WindSpeedUnit = .kmh
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

    // MARK: - Grid-Daten (nur on-demand via Download)

    var currentGrid: WeatherGrid?
    var selectedHourIndex: Int = 0
    var isLoadingGrid = false
    var gridLoadProgress: (completed: Int, total: Int)?
    var gridLoadError: String?
    var isExportingGrib = false
    var gribExportProgress: (completed: Int, total: Int)?
    var gridInspection: GridInspection?

    private let gridService = GridFetchService()
    private var downloadTask: Task<Void, Never>?
    private var lastReportedProgress = 0
    private var gridLoadGeneration = 0
    private(set) var lastMapRegion: MKCoordinateRegion?

    /// Kartenregion für GRIB-Download (Karte → Ort → Standard-Mitteleuropa).
    func downloadRegion(fallback location: Location?) -> MKCoordinateRegion {
        if let lastMapRegion { return lastMapRegion }
        if let location {
            return MKCoordinateRegion(
                center: location.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6)
            )
        }
        return Self.defaultMapRegion
    }

    private static let defaultMapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.0, longitude: 10.0),
        span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6)
    )

    /// Raster für die Karte laden (ohne Speicherdialog).
    func startGridLoad(for mapRegion: MKCoordinateRegion) {
        if isLoadingGrid { return }
        gridLoadGeneration += 1
        let generation = gridLoadGeneration
        gridLoadError = nil
        downloadTask = Task {
            do {
                try await fetchGrid(for: mapRegion, generation: generation)
            } catch is CancellationError {
                return
            } catch {
                if generation == gridLoadGeneration {
                    gridLoadError = error.localizedDescription
                }
            }
        }
    }

    /// Aktuelles Raster als GRIB2-Datei speichern.
    func startGridExport(to url: URL) {
        downloadTask?.cancel()
        gridLoadError = nil
        downloadTask = Task {
            do {
                guard let grid = currentGrid else {
                    throw WeatherError.noData
                }
                try await exportGrib(grid: grid, to: url)
            } catch is CancellationError {
                return
            } catch {
                gridLoadError = error.localizedDescription
            }
        }
    }

    /// Sichtbaren Kartenbereich setzen; Raster nur bei merklicher Bewegung verwerfen.
    func setVisibleMapRegion(_ mapRegion: MKCoordinateRegion) {
        if let last = lastMapRegion, Self.regionsEqual(last, mapRegion) { return }
        if let last = lastMapRegion,
           Self.regionChangedSignificantly(mapRegion, comparedTo: last),
           currentGrid != nil {
            currentGrid = nil
            gridInspection = nil
        }
        lastMapRegion = mapRegion
    }

    /// GRIB-Raster für den sichtbaren Kartenbereich laden (nur auf Nutzeraktion).
    func fetchGrid(for mapRegion: MKCoordinateRegion, generation: Int? = nil) async throws {
        let activeGeneration = generation ?? {
            gridLoadGeneration += 1
            return gridLoadGeneration
        }()
        let region = GridRegion(from: mapRegion)
        let model  = selectedModel
        isLoadingGrid = true
        gridLoadError = nil
        lastReportedProgress = 0
        gridLoadProgress = (0, region.allIndices.count)
        defer {
            if activeGeneration == gridLoadGeneration {
                isLoadingGrid = false
                gridLoadProgress = nil
            }
        }
        let grid = try await gridService.fetchGrid(region: region, model: model) { [weak self] completed, total in
            Task { @MainActor in
                guard let self, activeGeneration == self.gridLoadGeneration else { return }
                guard completed == total
                        || completed - self.lastReportedProgress >= 5
                        || self.lastReportedProgress == 0 else { return }
                self.lastReportedProgress = completed
                self.gridLoadProgress = (completed, total)
            }
        }
        try Task.checkCancellation()
        guard activeGeneration == gridLoadGeneration else { return }
        currentGrid = grid
        lastMapRegion = mapRegion
        gridInspection = nil
        clampSelectedHourIndex()
    }

    func exportGrib(grid: WeatherGrid, to url: URL) async throws {
        isExportingGrib = true
        gribExportProgress = (0, 1)
        defer {
            isExportingGrib = false
            gribExportProgress = nil
        }
        let accessed = url.startAccessingSecurityScopedResource()
        try await Task.detached {
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            try GribWriter.write(grid: grid, to: url) { completed, total in
                Task { @MainActor in
                    self.gribExportProgress = (completed, total)
                }
            }
        }.value
    }

    /// Lädt GRIB für den sichtbaren Bereich und speichert die Datei.
    func downloadGrib(for mapRegion: MKCoordinateRegion, to url: URL) async throws {
        try await fetchGrid(for: mapRegion)
        guard let grid = currentGrid else {
            throw WeatherError.noData
        }
        try await exportGrib(grid: grid, to: url)
    }

    func cancelDownload() {
        gridLoadGeneration += 1
        downloadTask?.cancel()
        downloadTask = nil
        isLoadingGrid = false
        isExportingGrib = false
        gridLoadProgress = nil
        gribExportProgress = nil
    }

    func startDownload(for mapRegion: MKCoordinateRegion, saveTo url: URL) {
        downloadTask?.cancel()
        downloadTask = Task {
            do {
                try await downloadGrib(for: mapRegion, to: url)
            } catch is CancellationError {
                return
            } catch {
                gridLoadError = error.localizedDescription
            }
        }
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

    private static func regionChangedSignificantly(
        _ region: MKCoordinateRegion,
        comparedTo other: MKCoordinateRegion
    ) -> Bool {
        let refSpan = max(min(region.span.latitudeDelta, other.span.latitudeDelta), 1e-6)
        let centerShift = hypot(
            region.center.latitude - other.center.latitude,
            region.center.longitude - other.center.longitude
        )
        if centerShift / refSpan > 0.05 { return true }
        if abs(region.span.latitudeDelta - other.span.latitudeDelta) / refSpan > 0.05 { return true }
        if abs(region.span.longitudeDelta - other.span.longitudeDelta) / refSpan > 0.05 { return true }
        return false
    }

    static func regionsEqual(_ a: MKCoordinateRegion, _ b: MKCoordinateRegion) -> Bool {
        abs(a.center.latitude - b.center.latitude) < 1e-8
            && abs(a.center.longitude - b.center.longitude) < 1e-8
            && abs(a.span.latitudeDelta - b.span.latitudeDelta) < 1e-8
            && abs(a.span.longitudeDelta - b.span.longitudeDelta) < 1e-8
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
