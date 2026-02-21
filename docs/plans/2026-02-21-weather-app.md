# Weather App – Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Baue eine native macOS-App (Swift + SwiftUI), die Wettermodelle (ICON, GFS, ECMWF) via Open-Meteo und aktuelle DWD-Beobachtungen via Bright Sky anzeigt – mit Karte, Charts und Standortverwaltung.

**Architecture:** MVVM mit `@Observable`-ViewModels, `actor`-basierten API-Services, `async/await` + `URLSession`. MapKit für Karte, Swift Charts für Meteogramme, CoreLocation für GPS.

**Tech Stack:** Swift 6, SwiftUI, MapKit, Swift Charts, CoreLocation, CLGeocoder, UserDefaults, XCTest

---

## Voraussetzungen (manuell, einmalig)

Vor Beginn sicherstellen:
1. **Xcode.app** aus dem App Store installiert (kostenlos) – für Build, Signing und CoreLocation
2. **xcodegen** installiert: `brew install xcodegen`

---

## Task 1: Projektstruktur erstellen

**Files:**
- Create: `project.yml`
- Create: `WeatherApp/Info.plist`
- Create: `WeatherApp/WeatherApp.entitlements`

**Step 1: project.yml anlegen**

```yaml
# project.yml
name: WeatherApp
options:
  bundleIdPrefix: com.jjreichel
  deploymentTarget:
    macOS: "14.0"
  createIntermediateGroups: true
targets:
  WeatherApp:
    type: application
    platform: macOS
    sources:
      - WeatherApp
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.jjreichel.WeatherApp
      SWIFT_VERSION: 6.0
      MARKETING_VERSION: 1.0
      CURRENT_PROJECT_VERSION: 1
      INFOPLIST_FILE: WeatherApp/Info.plist
      CODE_SIGN_ENTITLEMENTS: WeatherApp/WeatherApp.entitlements
      ENABLE_HARDENED_RUNTIME: YES
  WeatherAppTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - WeatherAppTests
    dependencies:
      - target: WeatherApp
    settings:
      SWIFT_VERSION: 6.0
```

**Step 2: Info.plist anlegen**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>WeatherApp benötigt deinen Standort, um lokale Wetterdaten anzuzeigen.</string>
  <key>CFBundleName</key>
  <string>WeatherApp</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
</dict>
</plist>
```

**Step 3: Entitlements anlegen**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.network.client</key>
  <true/>
  <key>com.apple.security.personal-information.location</key>
  <true/>
</dict>
</plist>
```

**Step 4: Ordnerstruktur anlegen**

```bash
mkdir -p WeatherApp/App
mkdir -p WeatherApp/Views
mkdir -p WeatherApp/ViewModels
mkdir -p WeatherApp/Services
mkdir -p WeatherApp/Models
mkdir -p WeatherAppTests
```

**Step 5: Xcode-Projekt generieren**

```bash
xcodegen generate
```

Expected: `WeatherApp.xcodeproj` wird erstellt. Danach Projekt in Xcode öffnen:
```bash
open WeatherApp.xcodeproj
```

**Step 6: Commit**

```bash
git add project.yml WeatherApp/ WeatherAppTests/ WeatherApp.xcodeproj
git commit -m "feat: Projektstruktur via xcodegen anlegen"
```

---

## Task 2: Enums und Fehlertypen

**Files:**
- Create: `WeatherApp/Models/WeatherModel.swift`
- Create: `WeatherApp/Models/WeatherLayer.swift`
- Create: `WeatherApp/Models/WeatherError.swift`

**Step 1: WeatherModel.swift**

```swift
enum WeatherModel: String, CaseIterable, Identifiable, Sendable {
    case icon   = "icon_seamless"
    case gfs    = "gfs_seamless"
    case ecmwf  = "ecmwf_ifs025"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .icon:  return "ICON"
        case .gfs:   return "GFS"
        case .ecmwf: return "ECMWF"
        }
    }
}
```

**Step 2: WeatherLayer.swift**

```swift
enum WeatherLayer: String, CaseIterable, Identifiable, Sendable {
    case temperature
    case precipitation
    case wind
    case cloudCover

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .temperature:  return "Temperatur"
        case .precipitation: return "Niederschlag"
        case .wind:         return "Wind"
        case .cloudCover:   return "Bewölkung"
        }
    }
}
```

**Step 3: WeatherError.swift**

```swift
import Foundation

enum WeatherError: LocalizedError, Sendable {
    case invalidURL
    case serverError(Int)
    case noData

    var errorDescription: String? {
        switch self {
        case .invalidURL:        return "Ungültige URL"
        case .serverError(let c): return "Serverfehler (HTTP \(c))"
        case .noData:            return "Keine Daten verfügbar"
        }
    }
}
```

**Step 4: Commit**

```bash
git add WeatherApp/Models/
git commit -m "feat: Enums und Fehlertypen hinzufügen"
```

---

## Task 3: Datenmodelle

**Files:**
- Create: `WeatherApp/Models/Location.swift`
- Create: `WeatherApp/Models/WeatherForecast.swift`
- Create: `WeatherApp/Models/Observation.swift`
- Create: `WeatherAppTests/ModelTests.swift`

**Step 1: Failing test schreiben**

```swift
// WeatherAppTests/ModelTests.swift
import Testing
@testable import WeatherApp
import Foundation

@Test func locationCodableRoundtrip() throws {
    let loc = Location(name: "Berlin", latitude: 52.52, longitude: 13.41)
    let data = try JSONEncoder().encode(loc)
    let decoded = try JSONDecoder().decode(Location.self, from: data)
    #expect(decoded.name == loc.name)
    #expect(decoded.latitude == loc.latitude)
    #expect(decoded.longitude == loc.longitude)
}

@Test func hourlyEntryFields() {
    let entry = WeatherForecast.HourlyEntry(
        time: Date(),
        temperature: 15.5,
        precipitation: 0.2,
        windSpeed: 30,
        windDirection: 180,
        cloudCover: 75
    )
    #expect(entry.temperature == 15.5)
    #expect(entry.precipitation == 0.2)
}
```

**Step 2: Test ausführen (erwartet FAIL)**

In Xcode: Cmd+U oder über Test-Navigator.
Expected: Fehler wegen fehlender Typen.

**Step 3: Location.swift**

```swift
import Foundation
import CoreLocation

struct Location: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var isFavorite: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.isFavorite = isFavorite
    }
}
```

**Step 4: WeatherForecast.swift**

```swift
import Foundation

struct WeatherForecast: Equatable, Sendable {
    let location: Location
    let model: WeatherModel
    let hourly: [HourlyEntry]

    struct HourlyEntry: Equatable, Sendable {
        let time: Date
        let temperature: Double?   // °C
        let precipitation: Double? // mm
        let windSpeed: Double?     // km/h
        let windDirection: Double? // Grad
        let cloudCover: Double?    // %
    }
}
```

**Step 5: Observation.swift**

```swift
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
```

**Step 6: Test erneut ausführen (erwartet PASS)**

**Step 7: Commit**

```bash
git add WeatherApp/Models/ WeatherAppTests/
git commit -m "feat: Datenmodelle mit Tests hinzufügen"
```

---

## Task 4: OpenMeteoService

**Files:**
- Create: `WeatherApp/Services/OpenMeteoService.swift`
- Create: `WeatherAppTests/OpenMeteoServiceTests.swift`

**Step 1: Failing test mit Mock-Daten schreiben**

```swift
// WeatherAppTests/OpenMeteoServiceTests.swift
import Testing
@testable import WeatherApp
import Foundation

@Test func decodeOpenMeteoResponse() throws {
    let json = """
    {
      "latitude": 52.52,
      "longitude": 13.41,
      "hourly": {
        "time": ["2024-01-01T00:00", "2024-01-01T01:00"],
        "temperature_2m": [5.1, 4.9],
        "precipitation": [0.0, 0.1],
        "windspeed_10m": [12.3, 11.5],
        "winddirection_10m": [180.0, 175.0],
        "cloudcover": [75.0, 80.0]
      }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: json)
    #expect(response.hourly.time.count == 2)
    #expect(response.hourly.temperature2m.first == 5.1)
}
```

**Step 2: Test ausführen (erwartet FAIL)**

Expected: `OpenMeteoResponse` nicht gefunden.

**Step 3: OpenMeteoService.swift**

```swift
import Foundation

// Internes Decodierungsmodell – nicht exportiert
struct OpenMeteoResponse: Decodable {
    let hourly: HourlyData

    struct HourlyData: Decodable {
        let time: [String]
        let temperature2m: [Double?]
        let precipitation: [Double?]
        let windspeed10m: [Double?]
        let winddirection10m: [Double?]
        let cloudcover: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m    = "temperature_2m"
            case precipitation
            case windspeed10m     = "windspeed_10m"
            case winddirection10m = "winddirection_10m"
            case cloudcover
        }
    }

    func toForecast(location: Location, model: WeatherModel) -> WeatherForecast {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let entries: [WeatherForecast.HourlyEntry] = hourly.time.enumerated().compactMap { (i, str) in
            guard let date = formatter.date(from: str) else { return nil }
            return WeatherForecast.HourlyEntry(
                time: date,
                temperature: hourly.temperature2m[safe: i] ?? nil,
                precipitation: hourly.precipitation[safe: i] ?? nil,
                windSpeed: hourly.windspeed10m[safe: i] ?? nil,
                windDirection: hourly.winddirection10m[safe: i] ?? nil,
                cloudCover: hourly.cloudcover[safe: i] ?? nil
            )
        }
        return WeatherForecast(location: location, model: model, hourly: entries)
    }
}

actor OpenMeteoService {
    private let baseURL = URL(string: "https://api.open-meteo.com/v1/forecast")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    func fetchForecast(for location: Location, model: WeatherModel) async throws -> WeatherForecast {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude",     value: String(location.latitude)),
            URLQueryItem(name: "longitude",    value: String(location.longitude)),
            URLQueryItem(name: "hourly",       value: "temperature_2m,precipitation,windspeed_10m,winddirection_10m,cloudcover"),
            URLQueryItem(name: "models",       value: model.rawValue),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone",     value: "auto"),
        ]
        guard let url = components.url else { throw WeatherError.invalidURL }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw WeatherError.serverError(http.statusCode)
        }
        let raw = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return raw.toForecast(location: location, model: model)
    }
}

// Hilfserweiterung für sicheren Array-Zugriff
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

**Step 4: Test erneut ausführen (erwartet PASS)**

**Step 5: Commit**

```bash
git add WeatherApp/Services/OpenMeteoService.swift WeatherAppTests/OpenMeteoServiceTests.swift
git commit -m "feat: OpenMeteoService mit Decode-Test hinzufügen"
```

---

## Task 5: BrightSkyService

**Files:**
- Create: `WeatherApp/Services/BrightSkyService.swift`
- Create: `WeatherAppTests/BrightSkyServiceTests.swift`

**Step 1: Failing test schreiben**

```swift
// WeatherAppTests/BrightSkyServiceTests.swift
import Testing
@testable import WeatherApp
import Foundation

@Test func decodeBrightSkyCurrentWeather() throws {
    let json = """
    {
      "weather": {
        "timestamp": "2024-01-01T12:00:00+00:00",
        "temperature": 8.3,
        "precipitation_10": 0.0,
        "wind_speed_10": 15.2,
        "wind_direction_10": 225,
        "cloud_cover": 50,
        "condition": "dry",
        "icon": "partly-cloudy-day"
      },
      "sources": [
        { "station_name": "Berlin-Tempelhof" }
      ]
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(BrightSkyCurrentResponse.self, from: json)
    #expect(response.weather.temperature == 8.3)
    #expect(response.sources.first?.stationName == "Berlin-Tempelhof")
}
```

**Step 2: Test ausführen (erwartet FAIL)**

**Step 3: BrightSkyService.swift**

```swift
import Foundation

struct BrightSkyCurrentResponse: Decodable {
    let weather: BrightSkyWeather
    let sources: [BrightSkySource]

    struct BrightSkyWeather: Decodable {
        let timestamp: String
        let temperature: Double?
        let precipitation10: Double?
        let windSpeed10: Double?
        let windDirection10: Double?
        let cloudCover: Double?
        let condition: String?
        let icon: String?

        enum CodingKeys: String, CodingKey {
            case timestamp
            case temperature
            case precipitation10  = "precipitation_10"
            case windSpeed10      = "wind_speed_10"
            case windDirection10  = "wind_direction_10"
            case cloudCover       = "cloud_cover"
            case condition
            case icon
        }

        func toObservation(stationName: String) -> Observation {
            let formatter = ISO8601DateFormatter()
            let time = formatter.date(from: timestamp) ?? Date()
            return Observation(
                stationName: stationName,
                time: time,
                temperature: temperature,
                precipitation: precipitation10,
                windSpeed: windSpeed10,
                windDirection: windDirection10 != nil ? Double(windDirection10!) : nil,
                cloudCover: cloudCover,
                condition: condition,
                icon: icon
            )
        }
    }

    struct BrightSkySource: Decodable {
        let stationName: String?

        enum CodingKeys: String, CodingKey {
            case stationName = "station_name"
        }
    }
}

actor BrightSkyService {
    private let baseURL = URL(string: "https://api.brightsky.dev")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: config)
    }

    func fetchCurrentObservation(for location: Location) async throws -> Observation {
        var components = URLComponents(url: baseURL.appendingPathComponent("current_weather"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(location.latitude)),
            URLQueryItem(name: "lon", value: String(location.longitude)),
        ]
        guard let url = components.url else { throw WeatherError.invalidURL }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw WeatherError.serverError(http.statusCode)
        }
        let raw = try JSONDecoder().decode(BrightSkyCurrentResponse.self, from: data)
        let stationName = raw.sources.first?.stationName ?? "Unbekannte Station"
        return raw.weather.toObservation(stationName: stationName)
    }
}
```

**Step 4: Test erneut ausführen (erwartet PASS)**

**Step 5: Commit**

```bash
git add WeatherApp/Services/BrightSkyService.swift WeatherAppTests/BrightSkyServiceTests.swift
git commit -m "feat: BrightSkyService mit Decode-Test hinzufügen"
```

---

## Task 6: LocationViewModel

**Files:**
- Create: `WeatherApp/ViewModels/LocationViewModel.swift`

```swift
import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
final class LocationViewModel: NSObject {
    var currentLocation: Location?
    var selectedLocation: Location?
    var favorites: [Location] = []
    var searchResults: [Location] = []
    var searchText: String = ""
    var isSearching = false
    var locationError: String?

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let favoritesKey = "savedFavorites"
    private var hasSetInitialLocation = false

    override init() {
        super.init()
        loadFavorites()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func search(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let placemarks = try await geocoder.geocodeAddressString(query)
            searchResults = placemarks.compactMap { pm in
                guard let coord = pm.location?.coordinate else { return nil }
                let name = [pm.name, pm.locality].compactMap { $0 }.first ?? "Unbekannt"
                return Location(name: name, latitude: coord.latitude, longitude: coord.longitude)
            }
        } catch {
            searchResults = []
        }
    }

    func addFavorite(_ location: Location) {
        guard !favorites.contains(where: { abs($0.latitude - location.latitude) < 0.01 && abs($0.longitude - location.longitude) < 0.01 }) else { return }
        var loc = location
        loc.isFavorite = true
        favorites.append(loc)
        saveFavorites()
    }

    func removeFavorite(_ location: Location) {
        favorites.removeAll { $0.id == location.id }
        saveFavorites()
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }

    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: favoritesKey),
              let saved = try? JSONDecoder().decode([Location].self, from: data) else { return }
        favorites = saved
    }
}

extension LocationViewModel: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            let placemarks = try? await CLGeocoder().reverseGeocodeLocation(loc)
            let name = placemarks?.first?.locality ?? "Aktueller Standort"
            let location = Location(name: name, latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
            self.currentLocation = location
            if !self.hasSetInitialLocation {
                self.selectedLocation = location
                self.hasSetInitialLocation = true
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationError = error.localizedDescription
        }
    }
}
```

**Step: Commit**

```bash
git add WeatherApp/ViewModels/LocationViewModel.swift
git commit -m "feat: LocationViewModel mit GPS und Favoriten"
```

---

## Task 7: WeatherViewModel

**Files:**
- Create: `WeatherApp/ViewModels/WeatherViewModel.swift`

```swift
import Foundation
import Observation

@MainActor
@Observable
final class WeatherViewModel {
    var forecasts: [WeatherModel: WeatherForecast] = [:]
    var observation: Observation?
    var selectedModel: WeatherModel = .icon
    var selectedLayer: WeatherLayer = .temperature
    var isLoading = false
    var error: String?

    private let openMeteo = OpenMeteoService()
    private let brightSky = BrightSkyService()

    func loadAll(for location: Location) async {
        isLoading = true
        error = nil
        async let obs = fetchObservation(for: location)
        async let fc  = fetchAllForecasts(for: location)
        self.observation = await obs
        self.forecasts   = await fc
        isLoading = false
    }

    var currentForecast: WeatherForecast? {
        forecasts[selectedModel]
    }

    private func fetchObservation(for location: Location) async -> Observation? {
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
```

**Step: Commit**

```bash
git add WeatherApp/ViewModels/WeatherViewModel.swift
git commit -m "feat: WeatherViewModel mit parallelem Datenladen"
```

---

## Task 8: App Entry Point & ContentView

**Files:**
- Create: `WeatherApp/App/WeatherApp.swift`
- Create: `WeatherApp/Views/ContentView.swift`

**Step 1: WeatherApp.swift**

```swift
import SwiftUI

@main
struct WeatherApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1100, height: 700)
    }
}
```

**Step 2: ContentView.swift**

```swift
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case map          = "Karte"
    case charts       = "Charts"
    case observations = "Aktuell"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .map:          return "map"
        case .charts:       return "chart.line.uptrend.xyaxis"
        case .observations: return "thermometer.medium"
        }
    }
}

struct ContentView: View {
    @State private var locationVM = LocationViewModel()
    @State private var weatherVM  = WeatherViewModel()
    @State private var selectedItem: SidebarItem? = .map
    @State private var showLocationSearch = false

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selectedItem) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)

            if !locationVM.favorites.isEmpty {
                Divider()
                Section("Favoriten") {
                    ForEach(locationVM.favorites) { loc in
                        Button(loc.name) {
                            locationVM.selectedLocation = loc
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(
                            locationVM.selectedLocation?.id == loc.id ? Color.accentColor : .primary
                        )
                    }
                }
                .padding(.horizontal)
            }
        } detail: {
            Group {
                if let error = weatherVM.error {
                    ErrorBanner(message: error) {
                        Task {
                            if let loc = locationVM.selectedLocation {
                                await weatherVM.loadAll(for: loc)
                            }
                        }
                    }
                }
                switch selectedItem {
                case .map:          MapWeatherView(weatherVM: weatherVM, locationVM: locationVM)
                case .charts:       ChartsView(weatherVM: weatherVM)
                case .observations: ObservationsView(weatherVM: weatherVM)
                case nil:           Text("Wähle eine Ansicht").foregroundStyle(.secondary)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        showLocationSearch = true
                    } label: {
                        Label(locationVM.selectedLocation?.name ?? "Ort wählen", systemImage: "location")
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Picker("Modell", selection: $weatherVM.selectedModel) {
                        ForEach(WeatherModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
        }
        .sheet(isPresented: $showLocationSearch) {
            LocationSearchView(locationVM: locationVM)
        }
        .task(id: locationVM.selectedLocation?.id) {
            if let loc = locationVM.selectedLocation {
                await weatherVM.loadAll(for: loc)
            }
        }
    }
}
```

**Step 3: ErrorBanner.swift**

```swift
// WeatherApp/Views/ErrorBanner.swift
import SwiftUI

struct ErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .foregroundStyle(.primary)
            Spacer()
            Button("Wiederholen", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding()
        .background(.red.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}
```

**Step 4: Commit**

```bash
git add WeatherApp/App/ WeatherApp/Views/ContentView.swift WeatherApp/Views/ErrorBanner.swift
git commit -m "feat: App Entry Point, ContentView und ErrorBanner"
```

---

## Task 9: MapView

**Files:**
- Create: `WeatherApp/Views/MapWeatherView.swift`

```swift
import SwiftUI
import MapKit

struct WeatherDataPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let color: Color
    let label: String
}

struct MapWeatherView: View {
    var weatherVM: WeatherViewModel
    var locationVM: LocationViewModel

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $position) {
                if let loc = locationVM.selectedLocation {
                    Marker(loc.name, coordinate: loc.coordinate)
                }
                ForEach(dataPoints) { point in
                    Annotation("", coordinate: point.coordinate) {
                        ZStack {
                            Circle()
                                .fill(point.color.opacity(0.75))
                                .frame(width: 44, height: 44)
                            Text(point.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }

            LayerPickerView(selectedLayer: $weatherVM.selectedLayer)
                .padding()
        }
        .onChange(of: locationVM.selectedLocation) { _, loc in
            guard let loc else { return }
            withAnimation {
                position = .region(MKCoordinateRegion(
                    center: loc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 3, longitudeDelta: 3)
                ))
            }
        }
    }

    // In v1: ein Datenpunkt am gewählten Ort für die aktuelle Stunde
    var dataPoints: [WeatherDataPoint] {
        guard let forecast = weatherVM.currentForecast,
              let entry = forecast.hourly.first else { return [] }

        let (value, label): (Double?, String) = {
            switch weatherVM.selectedLayer {
            case .temperature:
                let v = entry.temperature
                return (v, v.map { "\(Int($0.rounded()))°C" } ?? "—")
            case .precipitation:
                let v = entry.precipitation
                return (v, v.map { "\(String(format: "%.1f", $0)) mm" } ?? "—")
            case .wind:
                let v = entry.windSpeed
                return (v, v.map { "\(Int($0.rounded())) km/h" } ?? "—")
            case .cloudCover:
                let v = entry.cloudCover
                return (v, v.map { "\(Int($0.rounded()))%" } ?? "—")
            }
        }()

        return [WeatherDataPoint(
            coordinate: forecast.location.coordinate,
            color: colorFor(value: value, layer: weatherVM.selectedLayer),
            label: label
        )]
    }

    func colorFor(value: Double?, layer: WeatherLayer) -> Color {
        guard let v = value else { return .gray }
        switch layer {
        case .temperature:
            switch v {
            case ..<0:    return .blue
            case 0..<10:  return .cyan
            case 10..<20: return .green
            case 20..<30: return .orange
            default:      return .red
            }
        case .precipitation:
            return v < 0.1 ? .gray : v < 2 ? .blue : .indigo
        case .wind:
            return v < 20 ? .green : v < 50 ? .yellow : .red
        case .cloudCover:
            return v < 25 ? .yellow : v < 75 ? .gray : .primary
        }
    }
}

struct LayerPickerView: View {
    @Binding var selectedLayer: WeatherLayer

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(WeatherLayer.allCases) { layer in
                Button(layer.displayName) {
                    selectedLayer = layer
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedLayer == layer ? .accentColor : .secondary.opacity(0.6))
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
```

**Step: Commit**

```bash
git add WeatherApp/Views/MapWeatherView.swift
git commit -m "feat: MapView mit Wetter-Overlay und Layer-Picker"
```

---

## Task 10: ChartsView

**Files:**
- Create: `WeatherApp/Views/ChartsView.swift`

```swift
import SwiftUI
import Charts

struct ChartsView: View {
    var weatherVM: WeatherViewModel

    var body: some View {
        Group {
            if weatherVM.isLoading {
                ProgressView("Lade Vorhersage…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if weatherVM.forecasts.isEmpty {
                ContentUnavailableView("Keine Daten", systemImage: "cloud.slash", description: Text("Kein Ort ausgewählt oder keine Daten verfügbar."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        ChartSection(title: "Temperatur (°C)") {
                            Chart {
                                ForEach(WeatherModel.allCases) { model in
                                    if let forecast = weatherVM.forecasts[model] {
                                        ForEach(forecast.hourly.prefix(48), id: \.time) { entry in
                                            if let temp = entry.temperature {
                                                LineMark(x: .value("Zeit", entry.time), y: .value("Temperatur", temp))
                                                    .foregroundStyle(by: .value("Modell", model.displayName))
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(height: 200)
                            .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.weekday(.abbreviated).hour()) } }
                        }

                        ChartSection(title: "Niederschlag (mm)") {
                            Chart {
                                ForEach(WeatherModel.allCases) { model in
                                    if let forecast = weatherVM.forecasts[model] {
                                        ForEach(forecast.hourly.prefix(48), id: \.time) { entry in
                                            if let precip = entry.precipitation {
                                                BarMark(x: .value("Zeit", entry.time), y: .value("mm", precip))
                                                    .foregroundStyle(by: .value("Modell", model.displayName))
                                                    .opacity(0.7)
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(height: 150)
                        }

                        ChartSection(title: "Windgeschwindigkeit (km/h)") {
                            Chart {
                                ForEach(WeatherModel.allCases) { model in
                                    if let forecast = weatherVM.forecasts[model] {
                                        ForEach(forecast.hourly.prefix(48), id: \.time) { entry in
                                            if let wind = entry.windSpeed {
                                                LineMark(x: .value("Zeit", entry.time), y: .value("km/h", wind))
                                                    .foregroundStyle(by: .value("Modell", model.displayName))
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(height: 150)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct ChartSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}
```

**Step: Commit**

```bash
git add WeatherApp/Views/ChartsView.swift
git commit -m "feat: Charts-View mit Temperatur, Niederschlag und Wind"
```

---

## Task 11: ObservationsView

**Files:**
- Create: `WeatherApp/Views/ObservationsView.swift`

```swift
import SwiftUI

struct ObservationsView: View {
    var weatherVM: WeatherViewModel

    var body: some View {
        Group {
            if weatherVM.isLoading {
                ProgressView("Lade Beobachtungen…")
            } else if let obs = weatherVM.observation {
                ObservationDetailView(observation: obs)
            } else {
                ContentUnavailableView("Keine Beobachtungen", systemImage: "antenna.radiowaves.left.and.right.slash", description: Text("Für den gewählten Ort sind keine DWD-Stationsdaten verfügbar."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ObservationDetailView: View {
    let observation: Observation

    private var timeString: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "de_DE")
        return f.string(from: observation.time)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Station", value: observation.stationName)
                LabeledContent("Messung", value: timeString)
            }
            Section("Messwerte") {
                if let t = observation.temperature {
                    LabeledContent("Temperatur", value: String(format: "%.1f °C", t))
                }
                if let w = observation.windSpeed {
                    LabeledContent("Wind", value: String(format: "%.0f km/h", w))
                }
                if let d = observation.windDirection {
                    LabeledContent("Windrichtung", value: "\(Int(d))°")
                }
                if let p = observation.precipitation {
                    LabeledContent("Niederschlag", value: String(format: "%.1f mm", p))
                }
                if let c = observation.cloudCover {
                    LabeledContent("Bewölkung", value: "\(Int(c)) %")
                }
                if let cond = observation.condition {
                    LabeledContent("Bedingung", value: cond)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
```

**Step: Commit**

```bash
git add WeatherApp/Views/ObservationsView.swift
git commit -m "feat: ObservationsView für DWD-Stationsdaten"
```

---

## Task 12: LocationSearchView

**Files:**
- Create: `WeatherApp/Views/LocationSearchView.swift`

```swift
import SwiftUI

struct LocationSearchView: View {
    @Bindable var locationVM: LocationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ort wählen")
                    .font(.headline)
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.return)
            }
            .padding()

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Stadt oder Ort suchen…", text: $locationVM.searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: locationVM.searchText) { _, query in
                        Task { await locationVM.search(query: query) }
                    }
                if locationVM.isSearching {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(10)
            .background(.background.secondary)

            Divider()

            List {
                if let current = locationVM.currentLocation {
                    Section {
                        LocationRow(
                            location: current,
                            isSelected: locationVM.selectedLocation?.id == current.id
                        ) {
                            locationVM.selectedLocation = current
                            dismiss()
                        }
                    } header: {
                        Label("Aktueller Standort", systemImage: "location.fill")
                    }
                }

                if !locationVM.searchResults.isEmpty {
                    Section("Suchergebnisse") {
                        ForEach(locationVM.searchResults) { loc in
                            LocationRow(location: loc, isSelected: false) {
                                locationVM.selectedLocation = loc
                                locationVM.addFavorite(loc)
                                dismiss()
                            }
                        }
                    }
                } else if locationVM.searchText.isEmpty && !locationVM.favorites.isEmpty {
                    Section("Favoriten") {
                        ForEach(locationVM.favorites) { loc in
                            LocationRow(
                                location: loc,
                                isSelected: locationVM.selectedLocation?.id == loc.id
                            ) {
                                locationVM.selectedLocation = loc
                                dismiss()
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    locationVM.removeFavorite(loc)
                                } label: {
                                    Label("Entfernen", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 520)
    }
}

struct LocationRow: View {
    let location: Location
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(location.name)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
```

**Step: Commit**

```bash
git add WeatherApp/Views/LocationSearchView.swift
git commit -m "feat: LocationSearchView mit GPS, Suche und Favoriten"
```

---

## Task 13: Abschließender Build & Smoke-Test

**Step 1: In Xcode bauen**

In Xcode: Cmd+B
Expected: Build Succeeded – keine Fehler, keine Warnungen.

**Step 2: App starten**

In Xcode: Cmd+R
Expected:
- App startet mit NavigationSplitView
- GPS-Berechtigungsdialog erscheint
- Nach GPS-Freigabe: Ort wird gesetzt, Daten werden geladen
- Karte zeigt Marker für den Ort
- Charts zeigen Linien für ICON, GFS, ECMWF
- "Aktuell"-Tab zeigt DWD-Beobachtungen

**Step 3: Manuelle Checks**
- [ ] Ortssuche: "München" eingeben → Ergebnis auswählen → Daten aktualisieren
- [ ] Modellwechsel (ICON → GFS → ECMWF) → Charts aktualisieren sich
- [ ] Layer-Picker auf Karte (Temperatur / Niederschlag / Wind / Bewölkung)
- [ ] Favorit speichern → in Sidebar sichtbar → App neu starten → Favorit noch vorhanden
- [ ] Netzwerk deaktivieren → ErrorBanner erscheint → "Wiederholen" aktiviert Retry

**Step 4: Abschluss-Commit**

```bash
git add .
git commit -m "feat: WeatherApp v1 vollständig implementiert"
```
