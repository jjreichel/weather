# GRIB Grid Overlay Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wetterdaten als NxM-Raster aus Open-Meteo laden, als bilinear-interpoliertes CGImage-Overlay auf MapKit darstellen, mit Zeitslider durch 168 Vorhersagestunden blättern und die Rasterdaten als vollständige WMO GRIB2-Datei exportieren.

**Architecture:** `GridFetchService` (actor) lädt ~300 Punkte parallel per `TaskGroup`. `WeatherGrid` speichert alle Variablen × 168 Zeitschritte. Der bestehende SwiftUI `Map`-View wird durch `NSViewRepresentable` wrapping `MKMapView` ersetzt, damit `GribOverlayRenderer: MKOverlayRenderer` ein `CGImage` direkt in den Map-Kontext zeichnen kann. `GribWriter` schreibt binäres WMO GRIB2 Edition 2 (Simple Packing, Sections 0–8).

**Tech Stack:** Swift 6, SwiftUI, MapKit (`MKMapView` via `NSViewRepresentable`), CoreGraphics, Open-Meteo Forecast API + Marine API, WMO GRIB2 Ed.2, AppKit (`NSSavePanel`), Swift Testing.

---

## Referenz

- Open-Meteo Forecast API: `https://api.open-meteo.com/v1/forecast`
- Open-Meteo Marine API: `https://marine-api.open-meteo.com/v1/marine`
- WMO GRIB2 Spec: Grid Definition Template 3.0 (Lat/Lon), Product Definition Template 4.0, Data Representation Template 5.0 (Simple Packing)
- Vorhandener Test-Pattern: `WeatherAppTests/OpenMeteoServiceTests.swift` (Swift Testing, `@Test`, `#expect`)
- Array `[safe:]` Extension: bereits in `OpenMeteoService.swift` (lokal definiert — wird in Task 1 in ein eigenes File verschoben)

---

## Task 1: WeatherLayer erweitern + WeatherGrid + GridRegion Modelle

**Files:**
- Modify: `WeatherApp/Models/WeatherLayer.swift`
- Create: `WeatherApp/Models/WeatherGrid.swift`
- Create: `WeatherApp/Utilities/CollectionExtensions.swift`
- Test: `WeatherAppTests/WeatherGridTests.swift`

**Step 1: Failing Test schreiben**

`WeatherAppTests/WeatherGridTests.swift`:
```swift
import Testing
import MapKit
@testable import WeatherApp

@Test func gridRegionComputesStepAndCoordinates() {
    let region = GridRegion(latMin: 47.0, latMax: 55.0, lonMin: 6.0, lonMax: 15.0, nx: 10, ny: 9)
    #expect(abs(region.lonStep - 1.0) < 0.001)
    #expect(abs(region.latStep - 1.0) < 0.001)
    #expect(region.latitude(iy: 0) == 47.0)
    #expect(region.latitude(iy: 8) == 55.0)
    #expect(region.longitude(ix: 0) == 6.0)
    #expect(region.longitude(ix: 9) == 15.0)
    #expect(region.index(ix: 2, iy: 3) == 3 * 10 + 2)
}

@Test func gridRegionFromMapRegion() {
    let center = CLLocationCoordinate2D(latitude: 51.0, longitude: 10.0)
    let span = MKCoordinateSpan(latitudeDelta: 8.0, longitudeDelta: 9.0)
    let mapRegion = MKCoordinateRegion(center: center, span: span)
    let gridRegion = GridRegion(from: mapRegion)
    #expect(abs(gridRegion.latMin - 47.0) < 0.01)
    #expect(abs(gridRegion.latMax - 55.0) < 0.01)
}

@Test func gridStepForSmallSpan() {
    #expect(GridRegion.step(for: 3.0) == 0.1)
}

@Test func gridStepForLargeSpan() {
    #expect(GridRegion.step(for: 50.0) == 2.0)
}
```

**Step 2: Tests ausführen — müssen FEHLSCHLAGEN**

```bash
xcodebuild test -scheme WeatherApp -destination 'platform=macOS' \
  -only-testing WeatherAppTests/WeatherGridTests -quiet 2>&1 | tail -20
```
Erwartet: Compilerfehler (Typen existieren nicht).

**Step 3: Implementierung**

`WeatherApp/Utilities/CollectionExtensions.swift`:
```swift
// Sicherer Array-Zugriff — zentrale Definition (aus OpenMeteoService.swift entfernen)
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
```

`WeatherApp/Models/WeatherLayer.swift` (komplett ersetzen):
```swift
import Foundation

enum WeatherLayer: String, CaseIterable, Identifiable, Sendable {
    case temperature
    case precipitation
    case wind
    case cloudCover
    case wave
    case cape

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .temperature:   return "Temperatur"
        case .precipitation: return "Niederschlag"
        case .wind:          return "Wind"
        case .cloudCover:    return "Bewölkung"
        case .wave:          return "Wellen"
        case .cape:          return "CAPE"
        }
    }
}
```

`WeatherApp/Models/WeatherGrid.swift`:
```swift
import Foundation
import MapKit

/// Sendable Bounding-Box eines regulären lat/lon-Rasters.
/// ix=0 ist Westen, iy=0 ist Süden.
struct GridRegion: Sendable, Equatable {
    let latMin: Double
    let latMax: Double
    let lonMin: Double
    let lonMax: Double
    let nx: Int   // Anzahl Punkte in Längenrichtung
    let ny: Int   // Anzahl Punkte in Breitenrichtung

    var latStep: Double { (latMax - latMin) / Double(max(1, ny - 1)) }
    var lonStep: Double { (lonMax - lonMin) / Double(max(1, nx - 1)) }
    var centerLat: Double { (latMin + latMax) / 2 }
    var centerLon: Double { (lonMin + lonMax) / 2 }

    func latitude(iy: Int) -> Double  { latMin + Double(iy) * latStep }
    func longitude(ix: Int) -> Double { lonMin + Double(ix) * lonStep }

    /// Punkt-Index: Zeilen-Major, Süd→Nord
    func index(ix: Int, iy: Int) -> Int { iy * nx + ix }

    /// Alle (ix, iy)-Paare
    var allIndices: [(ix: Int, iy: Int)] {
        (0..<ny).flatMap { iy in (0..<nx).map { ix in (ix: ix, iy: iy) } }
    }

    /// Schrittweite basierend auf Kartenspanne (immer ~300 Punkte)
    static func step(for latSpan: Double) -> Double {
        switch latSpan {
        case ..<5:     return 0.1
        case 5..<15:   return 0.25
        case 15..<40:  return 0.5
        default:       return 2.0
        }
    }

    init(from region: MKCoordinateRegion) {
        let step = GridRegion.step(for: region.span.latitudeDelta)
        let lat0 = region.center.latitude  - region.span.latitudeDelta  / 2
        let lat1 = region.center.latitude  + region.span.latitudeDelta  / 2
        let lon0 = region.center.longitude - region.span.longitudeDelta / 2
        let lon1 = region.center.longitude + region.span.longitudeDelta / 2
        latMin = (lat0 / step).rounded(.down) * step
        latMax = (lat1 / step).rounded(.up)   * step
        lonMin = (lon0 / step).rounded(.down) * step
        lonMax = (lon1 / step).rounded(.up)   * step
        nx = max(2, Int((lonMax - lonMin) / step) + 1)
        ny = max(2, Int((latMax - latMin) / step) + 1)
    }

    init(latMin: Double, latMax: Double, lonMin: Double, lonMax: Double, nx: Int, ny: Int) {
        self.latMin = latMin; self.latMax = latMax
        self.lonMin = lonMin; self.lonMax = lonMax
        self.nx = nx; self.ny = ny
    }
}

/// 2D-Wetterdaten-Raster für alle Layer × 168 Stunden.
/// data[layer][hourIndex] ist ein Array mit nx*ny Werten (index = iy*nx + ix).
struct WeatherGrid: Sendable {
    let region: GridRegion
    let model: WeatherModel
    let times: [Date]                           // 168 UTC-Zeitpunkte
    let data: [WeatherLayer: [[Double?]]]       // [layer][hour][point]
    let windDirection: [[Double?]]              // [hour][point] — Richtung in Grad
}
```

**Step 4: `[safe:]` aus OpenMeteoService.swift entfernen**

In `WeatherApp/Services/OpenMeteoService.swift` die letzten 6 Zeilen (die `Array`-Extension) löschen — sie ist jetzt in `CollectionExtensions.swift`.

**Step 5: Tests ausführen — müssen BESTEHEN**

```bash
xcodebuild test -scheme WeatherApp -destination 'platform=macOS' \
  -only-testing WeatherAppTests/WeatherGridTests -quiet 2>&1 | tail -10
```
Erwartet: `Test run passed.`

**Step 6: Commit**

```bash
git add WeatherApp/Models/WeatherLayer.swift WeatherApp/Models/WeatherGrid.swift \
        WeatherApp/Utilities/CollectionExtensions.swift \
        WeatherApp/Services/OpenMeteoService.swift \
        WeatherAppTests/WeatherGridTests.swift
git commit -m "$(cat <<'EOF'
feat: WeatherGrid-Modell + GridRegion, WeatherLayer um wave/cape erweitert

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

> **Hinweis:** Nach dem Commit `xcodegen generate` ausführen, da neue Dateien hinzugekommen sind.

---

## Task 2: GridFetchService

**Files:**
- Create: `WeatherApp/Services/GridFetchService.swift`
- Test: `WeatherAppTests/GridFetchServiceTests.swift`

**Step 1: Failing Test**

`WeatherAppTests/GridFetchServiceTests.swift`:
```swift
import Testing
@testable import WeatherApp
import Foundation

// Minimalster Open-Meteo-JSON für einen Punkt (Forecast)
private let forecastJSON = """
{
  "hourly": {
    "time": ["2024-01-01T00:00","2024-01-01T01:00"],
    "temperature_2m": [5.0, 6.0],
    "wind_speed_10m": [10.0, 11.0],
    "wind_direction_10m": [180.0, 185.0],
    "precipitation": [0.0, 0.1],
    "cape": [100.0, 200.0],
    "cloud_cover": [50.0, 60.0]
  }
}
""".data(using: .utf8)!

// Marine-JSON für einen Punkt
private let marineJSON = """
{
  "hourly": {
    "time": ["2024-01-01T00:00","2024-01-01T01:00"],
    "wave_height": [1.5, 1.8]
  }
}
""".data(using: .utf8)!

@Test func gridFetchServiceDecodesGridPoint() async throws {
    let session = URLSession.mockSession(forecastJSON: forecastJSON, marineJSON: marineJSON)
    let service = GridFetchService(session: session)
    // 2×2 Grid, 2 Zeitschritte
    let region = GridRegion(latMin: 54.0, latMax: 55.0, lonMin: 9.0, lonMax: 10.0, nx: 2, ny: 2)
    let grid = try await service.fetchGrid(region: region, model: .icon)
    #expect(grid.times.count == 2)
    #expect(grid.data[.temperature]?.count == 2)        // 2 Stunden
    #expect(grid.data[.temperature]?[0].count == 4)     // 4 Punkte (2×2)
    #expect(grid.data[.temperature]?[0][0] == 5.0)
    #expect(grid.windDirection[0][0] == 180.0)
}
```

Außerdem URLSession Mock in den Tests:
```swift
// WeatherAppTests/URLSessionMock.swift
import Foundation

extension URLSession {
    static func mockSession(forecastJSON: Data, marineJSON: Data) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.forecastData = forecastJSON
        MockURLProtocol.marineData   = marineJSON
        return URLSession(configuration: config)
    }
}

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var forecastData: Data = Data()
    nonisolated(unsafe) static var marineData:   Data = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let data = request.url?.host?.contains("marine") == true
            ? MockURLProtocol.marineData
            : MockURLProtocol.forecastData
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
```

**Step 2: Test ausführen — muss FEHLSCHLAGEN**
```bash
xcodebuild test -scheme WeatherApp -destination 'platform=macOS' \
  -only-testing WeatherAppTests/GridFetchServiceTests -quiet 2>&1 | tail -20
```

**Step 3: Implementierung**

`WeatherApp/Services/GridFetchService.swift`:
```swift
import Foundation
import MapKit

// Interne Decodiermodelle
private struct ForecastGridResponse: Decodable {
    let hourly: HourlyData

    struct HourlyData: Decodable {
        let time:             [String]
        let temperature2m:    [Double?]
        let windSpeed10m:     [Double?]
        let windDirection10m: [Double?]
        let precipitation:    [Double?]
        let cape:             [Double?]
        let cloudCover:       [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m    = "temperature_2m"
            case windSpeed10m     = "wind_speed_10m"
            case windDirection10m = "wind_direction_10m"
            case precipitation
            case cape
            case cloudCover       = "cloud_cover"
        }
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    var times: [Date] {
        hourly.time.compactMap { ForecastGridResponse.fmt.date(from: $0) }
    }
}

private struct MarineGridResponse: Decodable {
    let hourly: HourlyData

    struct HourlyData: Decodable {
        let waveHeight: [Double?]
        enum CodingKeys: String, CodingKey {
            case waveHeight = "wave_height"
        }
    }
}

actor GridFetchService {
    private let forecastBase = URL(string: "https://api.open-meteo.com/v1/forecast")!
    private let marineBase   = URL(string: "https://marine-api.open-meteo.com/v1/marine")!
    private let session: URLSession

    init(session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()) { self.session = session }

    func fetchGrid(region: GridRegion, model: WeatherModel) async throws -> WeatherGrid {
        let points = region.allIndices  // [(ix:, iy:)]
        let nTotal = region.nx * region.ny

        // Parallele Abfragen
        typealias PointResult = (pointIdx: Int, forecast: ForecastGridResponse?, marine: MarineGridResponse?)
        let results: [PointResult] = await withTaskGroup(of: PointResult.self) { group in
            for (ix, iy) in points {
                group.addTask {
                    let lat = region.latitude(iy: iy)
                    let lon = region.longitude(ix: ix)
                    let idx = region.index(ix: ix, iy: iy)
                    let forecast = try? await self.fetchForecast(lat: lat, lon: lon, model: model)
                    let marine   = try? await self.fetchMarine(lat: lat, lon: lon)
                    return (idx, forecast, marine)
                }
            }
            var out: [PointResult] = []
            for await r in group { out.append(r) }
            return out
        }

        // Zeiten aus erstem Ergebnis
        let times = results.compactMap { $0.forecast?.times }.first ?? []
        let nHours = times.count

        // Leere Arrays vorbereiten
        var tempData  = Array(repeating: Array(repeating: Optional<Double>.none, count: nTotal), count: nHours)
        var windData  = Array(repeating: Array(repeating: Optional<Double>.none, count: nTotal), count: nHours)
        var windDir   = Array(repeating: Array(repeating: Optional<Double>.none, count: nTotal), count: nHours)
        var precData  = Array(repeating: Array(repeating: Optional<Double>.none, count: nTotal), count: nHours)
        var capeData  = Array(repeating: Array(repeating: Optional<Double>.none, count: nTotal), count: nHours)
        var cloudData = Array(repeating: Array(repeating: Optional<Double>.none, count: nTotal), count: nHours)
        var waveData  = Array(repeating: Array(repeating: Optional<Double>.none, count: nTotal), count: nHours)

        for r in results {
            guard let fc = r.forecast else { continue }
            let i = r.pointIdx
            let h = fc.hourly
            for t in 0..<min(nHours, h.temperature2m.count) {
                tempData[t][i]  = h.temperature2m[safe: t].flatMap { $0 }
                windData[t][i]  = h.windSpeed10m[safe: t].flatMap { $0 }
                windDir[t][i]   = h.windDirection10m[safe: t].flatMap { $0 }
                precData[t][i]  = h.precipitation[safe: t].flatMap { $0 }
                capeData[t][i]  = h.cape[safe: t].flatMap { $0 }
                cloudData[t][i] = h.cloudCover[safe: t].flatMap { $0 }
            }
            if let m = r.marine {
                for t in 0..<min(nHours, m.hourly.waveHeight.count) {
                    waveData[t][i] = m.hourly.waveHeight[safe: t].flatMap { $0 }
                }
            }
        }

        let data: [WeatherLayer: [[Double?]]] = [
            .temperature:   tempData,
            .wind:          windData,
            .precipitation: precData,
            .cape:          capeData,
            .cloudCover:    cloudData,
            .wave:          waveData,
        ]

        return WeatherGrid(region: region, model: model, times: times, data: data, windDirection: windDir)
    }

    // MARK: - Private API Calls

    private func fetchForecast(lat: Double, lon: Double, model: WeatherModel) async throws -> ForecastGridResponse {
        var c = URLComponents(url: forecastBase, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "latitude",      value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude",     value: String(format: "%.4f", lon)),
            URLQueryItem(name: "hourly",        value: "temperature_2m,wind_speed_10m,wind_direction_10m,precipitation,cape,cloud_cover"),
            URLQueryItem(name: "models",        value: model.rawValue),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone",      value: "UTC"),
        ]
        let (data, _) = try await session.data(from: c.url!)
        return try JSONDecoder().decode(ForecastGridResponse.self, from: data)
    }

    private func fetchMarine(lat: Double, lon: Double) async throws -> MarineGridResponse {
        var c = URLComponents(url: marineBase, resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "latitude",      value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude",     value: String(format: "%.4f", lon)),
            URLQueryItem(name: "hourly",        value: "wave_height"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone",      value: "UTC"),
        ]
        let (data, _) = try await session.data(from: c.url!)
        return try JSONDecoder().decode(MarineGridResponse.self, from: data)
    }
}
```

**Step 4: Tests ausführen — müssen BESTEHEN**
```bash
xcodebuild test -scheme WeatherApp -destination 'platform=macOS' \
  -only-testing WeatherAppTests/GridFetchServiceTests -quiet 2>&1 | tail -10
```

**Step 5: Commit**
```bash
git add WeatherApp/Services/GridFetchService.swift \
        WeatherAppTests/GridFetchServiceTests.swift \
        WeatherAppTests/URLSessionMock.swift
git commit -m "$(cat <<'EOF'
feat: GridFetchService — paralleles NxM-Raster aus Open-Meteo

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: GribWriter — WMO GRIB2 Binary Export

**Files:**
- Create: `WeatherApp/Services/GribWriter.swift`
- Test: `WeatherAppTests/GribWriterTests.swift`

**Step 1: Failing Tests**

`WeatherAppTests/GribWriterTests.swift`:
```swift
import Testing
@testable import WeatherApp
import Foundation

// Hilfsfunktion: Minimal-WeatherGrid mit 2×2-Gitter, 2 Stunden
private func makeTestGrid() -> WeatherGrid {
    let region = GridRegion(latMin: 47.0, latMax: 48.0, lonMin: 8.0, lonMax: 9.0, nx: 2, ny: 2)
    let t0 = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!
    let t1 = ISO8601DateFormatter().date(from: "2024-01-01T01:00:00Z")!
    let values: [[Double?]] = [
        [5.0, 6.0, 7.0, 8.0],   // Stunde 0
        [5.5, 6.5, 7.5, 8.5],   // Stunde 1
    ]
    return WeatherGrid(
        region: region, model: .icon,
        times: [t0, t1],
        data: [.temperature: values],
        windDirection: [Array(repeating: nil, count: 4), Array(repeating: nil, count: 4)]
    )
}

@Test func gribWriterProducesGRIBMagicBytes() throws {
    let grid = makeTestGrid()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.grib2")
    try GribWriter.write(grid: grid, to: url)
    let data = try Data(contentsOf: url)
    #expect(data.count > 0)
    // Jede Message beginnt mit "GRIB"
    #expect(data[0] == 0x47) // 'G'
    #expect(data[1] == 0x52) // 'R'
    #expect(data[2] == 0x49) // 'I'
    #expect(data[3] == 0x42) // 'B'
}

@Test func gribWriterEdition2() throws {
    let grid = makeTestGrid()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_ed.grib2")
    try GribWriter.write(grid: grid, to: url)
    let data = try Data(contentsOf: url)
    #expect(data[7] == 0x02)  // GRIB Edition 2
}

@Test func gribWriterEndsWithTerminator() throws {
    let grid = makeTestGrid()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_end.grib2")
    try GribWriter.write(grid: grid, to: url)
    let data = try Data(contentsOf: url)
    let last4 = data.suffix(4)
    #expect(Array(last4) == [0x37, 0x37, 0x37, 0x37]) // "7777"
}

@Test func gribWriterSection3HasCorrectSectionNumber() throws {
    let grid = makeTestGrid()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_s3.grib2")
    try GribWriter.write(grid: grid, to: url)
    let data = try Data(contentsOf: url)
    // Section 3 beginnt bei Offset 16 (Sec0) + 21 (Sec1) = 37
    let sec3Start = 37
    #expect(data[sec3Start + 4] == 0x03) // Section number = 3
}

@Test func gribWriterSection5HasNBits16() throws {
    let grid = makeTestGrid()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_s5.grib2")
    try GribWriter.write(grid: grid, to: url)
    let data = try Data(contentsOf: url)
    // Sec5 beginnt bei 37+72 (Sec3) + 34 (Sec4) = 143
    let sec5Start = 37 + 72 + 34
    #expect(data[sec5Start + 4] == 0x05) // Section number = 5
    #expect(data[sec5Start + 20] == 16)  // nBits per value = 16
}

@Test func gribWriterMessageLengthConsistency() throws {
    let grid = makeTestGrid()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_len.grib2")
    try GribWriter.write(grid: grid, to: url)
    let data = try Data(contentsOf: url)
    // Gesamtlänge der ersten Message aus Section 0, Bytes 8-15 (big-endian UInt64)
    let totalLen = (0..<8).reduce(UInt64(0)) { acc, i in
        (acc << 8) | UInt64(data[8 + i])
    }
    // Mindestlänge: 16+21+72+34+21+6+5+4 = 179 Bytes (kein Bitmap, keine Daten)
    #expect(totalLen >= 179)
}
```

**Step 2: Test ausführen — muss FEHLSCHLAGEN**
```bash
xcodebuild test -scheme WeatherApp -destination 'platform=macOS' \
  -only-testing WeatherAppTests/GribWriterTests -quiet 2>&1 | tail -20
```

**Step 3: Implementierung**

`WeatherApp/Services/GribWriter.swift`:
```swift
import Foundation

enum GribWriter {

    // MARK: - Öffentliche API

    static func write(grid: WeatherGrid, to url: URL) throws {
        var output = Data()
        let refDate = grid.times.first ?? Date()

        // Jede Variable, alle Zeitschritte
        let layers: [(WeatherLayer, UInt8 /*disziplin*/, UInt8 /*kat*/, UInt8 /*param*/, UInt8 /*surface*/, UInt32 /*level*/)] = [
            (.temperature,   0, 0, 0,  103, 2),   // 2m über Grund
            (.wind,          0, 2, 1,  103, 10),  // 10m Windgeschwindigkeit
            (.precipitation, 0, 1, 8,  1,   0),   // Oberfläche
            (.cape,          0, 7, 6,  1,   0),
            (.cloudCover,    0, 6, 1,  1,   0),
            (.wave,         10, 0, 3,  1,   0),   // Ozean-Disziplin
        ]

        for (layer, disc, cat, param, surfaceType, level) in layers {
            guard let hourly = grid.data[layer] else { continue }
            for (hi, values) in hourly.enumerated() {
                let forecastHour = UInt32(hi)
                let msg = buildMessage(
                    values: values, grid: grid,
                    discipline: disc, category: cat, parameter: param,
                    surfaceType: surfaceType, level: level,
                    forecastHour: forecastHour, refDate: refDate
                )
                output.append(msg)
            }
        }

        // Windrichtung als extra Messages (Disziplin 0, Kat 2, Param 0)
        for (hi, values) in grid.windDirection.enumerated() {
            let msg = buildMessage(
                values: values, grid: grid,
                discipline: 0, category: 2, parameter: 0,
                surfaceType: 103, level: 10,
                forecastHour: UInt32(hi), refDate: refDate
            )
            output.append(msg)
        }

        try output.write(to: url)
    }

    // MARK: - Message Builder

    private static func buildMessage(
        values: [Double?], grid: WeatherGrid,
        discipline: UInt8, category: UInt8, parameter: UInt8,
        surfaceType: UInt8, level: UInt32,
        forecastHour: UInt32, refDate: Date
    ) -> Data {
        let nx = grid.region.nx
        let ny = grid.region.ny
        let n  = nx * ny

        // Simple Packing vorbereiten
        var bitmap   = Data(count: (n + 7) / 8)
        var floats   = [Float](repeating: 0, count: n)
        var present  = [Int]()
        for i in 0..<n {
            if let v = values[safe: i].flatMap({ $0 }) {
                floats[i] = Float(v)
                bitmap[i / 8] |= (0x80 >> UInt8(i % 8))
                present.append(i)
            }
        }
        let hasMissing = present.count < n

        let presentFloats = present.map { floats[$0] }
        let refMin: Float = presentFloats.min() ?? 0
        let refMax: Float = presentFloats.max() ?? 0
        let range = refMax - refMin

        // Binärskala E: kleinste Potenz von 2, sodass range / 2^E < 65535
        let E: Int16 = range > 0
            ? Int16(max(0, Int(ceil(log2(Double(range) / 65535.0)))))
            : 0
        let scaleDivisor = Float(pow(2.0, Double(E)))

        // Packing
        var packed = Data()
        for i in 0..<n {
            let bitSet = bitmap[i / 8] & (0x80 >> UInt8(i % 8)) != 0
            guard bitSet else { continue }
            let raw = UInt16(max(0, min(65535, Int(((floats[i] - refMin) / max(scaleDivisor, 1e-10)).rounded()))))
            packed.append(UInt8(raw >> 8))
            packed.append(UInt8(raw & 0xFF))
        }

        // Sektionslängen
        let sec6Len = hasMissing ? 6 + (n + 7) / 8 : 6
        let sec7Len = 5 + packed.count
        let totalLen = 16 + 21 + 72 + 34 + 21 + sec6Len + sec7Len + 4

        var msg = Data()
        msg.append(contentsOf: buildSec0(discipline: discipline, totalLen: totalLen))
        msg.append(contentsOf: buildSec1(refDate: refDate))
        msg.append(contentsOf: buildSec3(region: grid.region))
        msg.append(contentsOf: buildSec4(category: category, parameter: parameter,
                                         surfaceType: surfaceType, level: level,
                                         forecastHour: forecastHour))
        msg.append(contentsOf: buildSec5(refMin: refMin, binaryScale: E,
                                         presentCount: UInt32(present.count)))
        msg.append(contentsOf: buildSec6(bitmap: bitmap, hasMissing: hasMissing, n: n))
        msg.append(contentsOf: buildSec7(packed: packed))
        msg.append(contentsOf: [0x37, 0x37, 0x37, 0x37]) // "7777"
        return msg
    }

    // MARK: - Section Builder

    /// Section 0: Indicator — 16 Bytes
    private static func buildSec0(discipline: UInt8, totalLen: Int) -> [UInt8] {
        var s = [UInt8]("GRIB".utf8)      // 4 Bytes
        s += [0x00, 0x00]                  // Reserved
        s.append(discipline)               // Disziplin
        s.append(0x02)                     // Edition 2
        let len = UInt64(totalLen)
        s += [(len>>56)&0xFF, (len>>48)&0xFF, (len>>40)&0xFF, (len>>32)&0xFF,
              (len>>24)&0xFF, (len>>16)&0xFF, (len>> 8)&0xFF,  len     &0xFF]
        return s  // 16 Bytes
    }

    /// Section 1: Identification — 21 Bytes
    private static func buildSec1(refDate: Date) -> [UInt8] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let dc = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: refDate)
        let y  = UInt16(dc.year  ?? 2024)
        var s: [UInt8] = []
        s += uint32BE(21)                  // Section length
        s.append(0x01)                     // Section number
        s += [0x00, 0xFF]                  // Originating centre (255 = missing)
        s += [0x00, 0x00]                  // Sub-centre
        s.append(0x02)                     // Master tables version
        s.append(0x00)                     // Local tables version
        s.append(0x01)                     // Significance of ref time (1=Start of forecast)
        s += [UInt8(y>>8), UInt8(y&0xFF)]  // Year
        s.append(UInt8(dc.month  ?? 1))
        s.append(UInt8(dc.day    ?? 1))
        s.append(UInt8(dc.hour   ?? 0))
        s.append(UInt8(dc.minute ?? 0))
        s.append(UInt8(dc.second ?? 0))
        s.append(0x00)                     // Production status
        s.append(0x01)                     // Type: Forecast
        return s  // 21 Bytes
    }

    /// Section 3: Grid Definition (Template 3.0 Lat/Lon) — 72 Bytes
    private static func buildSec3(region: GridRegion) -> [UInt8] {
        var s: [UInt8] = []
        s += uint32BE(72)
        s.append(0x03)
        s.append(0x00)                         // Source: code table
        s += uint32BE(region.nx * region.ny)   // Number of data points
        s.append(0x00)                         // No optional list
        s.append(0x00)
        s += [0x00, 0x00]                      // Template 3.0

        // Template 3.0
        s.append(0x06)                         // Earth shape 6 (sphere R=6371229 m)
        s.append(0x00); s += uint32BE(0)       // Scale + radius
        s.append(0x00); s += uint32BE(0)       // Scale + major axis
        s.append(0x00); s += uint32BE(0)       // Scale + minor axis
        s += uint32BE(UInt32(region.nx))       // Ni
        s += uint32BE(UInt32(region.ny))       // Nj
        s += uint32BE(0)                       // Basic angle
        s += uint32BE(0xFFFFFFFF)              // Subdivisions (missing)

        let la1 = Int32(region.latMin * 1_000_000)
        let lo1 = UInt32(bitPattern: Int32(region.lonMin * 1_000_000))
        let la2 = Int32(region.latMax * 1_000_000)
        let lo2 = UInt32(bitPattern: Int32(region.lonMax * 1_000_000))
        let di  = UInt32(region.lonStep * 1_000_000)
        let dj  = UInt32(region.latStep * 1_000_000)

        s += int32BE(la1)
        s += uint32BE(lo1)
        s.append(0x30)                         // Resolution flags (i+j increments given)
        s += int32BE(la2)
        s += uint32BE(lo2)
        s += uint32BE(di)
        s += uint32BE(dj)
        s.append(0x00)                         // Scanning mode: i+, j+, row-major
        return s  // 72 Bytes
    }

    /// Section 4: Product Definition (Template 4.0) — 34 Bytes
    private static func buildSec4(category: UInt8, parameter: UInt8,
                                   surfaceType: UInt8, level: UInt32,
                                   forecastHour: UInt32) -> [UInt8] {
        var s: [UInt8] = []
        s += uint32BE(34)
        s.append(0x04)
        s += [0x00, 0x00]      // Coordinate values after template
        s += [0x00, 0x00]      // Template 4.0
        s.append(category)
        s.append(parameter)
        s.append(0x02)         // Generating process: Forecast
        s.append(0xFF)         // Background process
        s.append(0xFF)         // Analysis process
        s += [0x00, 0x00]      // Hours after cutoff
        s.append(0x00)         // Minutes after cutoff
        s.append(0x01)         // Unit of time: hour
        s += uint32BE(forecastHour)
        s.append(surfaceType)
        s.append(0x00)         // Scale factor
        s += uint32BE(level)
        s.append(0xFF)         // Second surface: missing
        s.append(0x00)
        s += uint32BE(0)
        return s  // 34 Bytes
    }

    /// Section 5: Data Representation (Template 5.0 Simple Packing) — 21 Bytes
    private static func buildSec5(refMin: Float, binaryScale: Int16, presentCount: UInt32) -> [UInt8] {
        var s: [UInt8] = []
        s += uint32BE(21)
        s.append(0x05)
        s += uint32BE(presentCount)
        s += [0x00, 0x00]      // Template 5.0
        // IEEE 754 big-endian float32
        let bits = refMin.bitPattern.bigEndian
        s += [(bits>>24)&0xFF, (bits>>16)&0xFF, (bits>>8)&0xFF, bits&0xFF].map { UInt8($0) }
        // Binary scale E (signed Int16, big-endian)
        let eRaw = UInt16(bitPattern: binaryScale)
        s += [UInt8(eRaw >> 8), UInt8(eRaw & 0xFF)]
        s += [0x00, 0x00]      // Decimal scale D = 0
        s.append(16)           // nBits per value
        s.append(0x00)         // Type: floating point
        return s  // 21 Bytes
    }

    /// Section 6: Bit-Map
    private static func buildSec6(bitmap: Data, hasMissing: Bool, n: Int) -> [UInt8] {
        if hasMissing {
            var s = uint32BE(UInt32(6 + (n + 7) / 8))
            s.append(0x06)
            s.append(0x00)  // Bitmap present
            s += [UInt8](bitmap)
            return s
        } else {
            return uint32BE(6) + [0x06, 0xFF]  // Kein Bitmap
        }
    }

    /// Section 7: Data
    private static func buildSec7(packed: Data) -> [UInt8] {
        var s = uint32BE(UInt32(5 + packed.count))
        s.append(0x07)
        s += [UInt8](packed)
        return s
    }

    // MARK: - Hilfsfunktionen (Big-Endian Encoding)

    private static func uint32BE(_ v: UInt32) -> [UInt8] {
        [UInt8(v>>24), UInt8((v>>16)&0xFF), UInt8((v>>8)&0xFF), UInt8(v&0xFF)]
    }
    private static func uint32BE(_ v: Int) -> [UInt8] { uint32BE(UInt32(bitPattern: Int32(v))) }
    private static func int32BE(_ v: Int32) -> [UInt8]  { uint32BE(UInt32(bitPattern: v)) }
}
```

**Step 4: Tests ausführen — müssen BESTEHEN**
```bash
xcodebuild test -scheme WeatherApp -destination 'platform=macOS' \
  -only-testing WeatherAppTests/GribWriterTests -quiet 2>&1 | tail -10
```

**Step 5: Commit**
```bash
git add WeatherApp/Services/GribWriter.swift WeatherAppTests/GribWriterTests.swift
git commit -m "$(cat <<'EOF'
feat: GribWriter — WMO GRIB2 Ed.2 Binary-Export (Simple Packing, Sections 0-8)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: GribMapOverlay + GribOverlayRenderer (CGImage-Rendering)

**Files:**
- Create: `WeatherApp/Views/GribMapOverlay.swift`

Kein Unit-Test für Rendering-Code; Integration wird in Task 8 visuell geprüft.

**Step 1: Implementierung**

`WeatherApp/Views/GribMapOverlay.swift`:
```swift
import MapKit
import SwiftUI

// MARK: - MKOverlay

final class GribMapOverlay: NSObject, MKOverlay {
    var grid: WeatherGrid? {
        didSet { updateBounds() }
    }
    var selectedLayer: WeatherLayer = .temperature
    var selectedHourIndex: Int = 0

    private(set) var boundingMapRect: MKMapRect = .world
    var coordinate: CLLocationCoordinate2D = .init(latitude: 0, longitude: 0)

    private func updateBounds() {
        guard let g = grid else { return }
        let r = g.region
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: r.latMax, longitude: r.lonMin))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: r.latMin, longitude: r.lonMax))
        boundingMapRect = MKMapRect(x: nw.x, y: nw.y,
                                    width: se.x - nw.x, height: se.y - nw.y)
        coordinate = CLLocationCoordinate2D(latitude: r.centerLat, longitude: r.centerLon)
    }
}

// MARK: - MKOverlayRenderer

final class GribOverlayRenderer: MKOverlayRenderer {
    var gridOverlay: GribMapOverlay { overlay as! GribMapOverlay }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        guard let grid = gridOverlay.grid,
              let values = grid.data[gridOverlay.selectedLayer]?[safe: gridOverlay.selectedHourIndex]
        else { return }

        let layer = gridOverlay.selectedLayer
        let nx = grid.region.nx
        let ny = grid.region.ny

        // CGImage erstellen: Zeile 0 = Norden (iy = ny-1)
        var pixels = [UInt8](repeating: 0, count: nx * ny * 4)
        for cgRow in 0..<ny {
            let gridIY = ny - 1 - cgRow
            for ix in 0..<nx {
                let pIdx = grid.region.index(ix: ix, iy: gridIY)
                let value = values[safe: pIdx].flatMap { $0 }
                let (r, g, b, a) = rgba(value: value, layer: layer)
                let base = (cgRow * nx + ix) * 4
                pixels[base]   = r; pixels[base+1] = g
                pixels[base+2] = b; pixels[base+3] = a
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(width: nx, height: ny,
                                    bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: nx * 4, space: colorSpace,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                    provider: provider, decode: nil,
                                    shouldInterpolate: true, // bilineare Interpolation
                                    intent: .defaultIntent)
        else { return }

        let drawRect = self.rect(for: gridOverlay.boundingMapRect)
        ctx.draw(cgImage, in: drawRect)
    }

    // MARK: - Farbskala (RGBA)
    private func rgba(value: Double?, layer: WeatherLayer) -> (UInt8, UInt8, UInt8, UInt8) {
        guard let v = value else { return (128, 128, 128, 0) }  // transparent = fehlend

        switch layer {
        case .temperature:
            // -20..40°C → blau→grün→gelb→rot
            let t = max(0, min(1, (v + 20) / 60))
            return gradient(t, stops: [
                (0.0, (0,  0,  200)),
                (0.4, (0,  200, 200)),
                (0.6, (50, 200, 50)),
                (0.8, (230, 200, 0)),
                (1.0, (200, 0,  0)),
            ])
        case .wind:
            // 0..60 km/h → grün→gelb→rot
            let t = max(0, min(1, v / 60))
            return gradient(t, stops: [
                (0.0, (0, 180, 0)),
                (0.5, (220, 220, 0)),
                (1.0, (200, 0, 0)),
            ])
        case .precipitation:
            // 0..10 mm/h → weiß→blau→dunkelblau
            let t = max(0, min(1, v / 10))
            return gradient(t, stops: [
                (0.0, (230, 230, 255)),
                (0.3, (0,   100, 255)),
                (1.0, (0,   0,   150)),
            ])
        case .cloudCover:
            // 0..100% → gelb→grau
            let t = max(0, min(1, v / 100))
            let c = UInt8(200 - Int(t * 150))
            return (c, c, UInt8(max(0, Int(c) - 50)), 180)
        case .wave:
            // 0..10 m → hellblau→dunkelblau
            let t = max(0, min(1, v / 10))
            return gradient(t, stops: [
                (0.0, (200, 240, 255)),
                (1.0, (0,   40,  160)),
            ])
        case .cape:
            // 0..3000 J/kg → weiß→gelb→rot→dunkelrot
            let t = max(0, min(1, v / 3000))
            return gradient(t, stops: [
                (0.0, (255, 255, 255)),
                (0.3, (255, 200, 0)),
                (0.7, (200, 0,   0)),
                (1.0, (80,  0,   0)),
            ])
        }
    }

    private func gradient(_ t: Double,
                           stops: [(Double, (Int, Int, Int))]) -> (UInt8, UInt8, UInt8, UInt8) {
        for i in 0..<stops.count - 1 {
            let (t0, c0) = stops[i]
            let (t1, c1) = stops[i + 1]
            guard t <= t1 else { continue }
            let f = (t - t0) / max(t1 - t0, 1e-10)
            let r = UInt8(max(0, min(255, Int(Double(c0.0) + f * Double(c1.0 - c0.0)))))
            let g = UInt8(max(0, min(255, Int(Double(c0.1) + f * Double(c1.1 - c0.1)))))
            let b = UInt8(max(0, min(255, Int(Double(c0.2) + f * Double(c1.2 - c0.2)))))
            return (r, g, b, 200)  // 78% Opazität
        }
        let last = stops.last!.1
        return (UInt8(last.0), UInt8(last.1), UInt8(last.2), 200)
    }
}
```

**Step 2: Commit**
```bash
git add WeatherApp/Views/GribMapOverlay.swift
git commit -m "$(cat <<'EOF'
feat: GribMapOverlay + GribOverlayRenderer mit CGImage und bilinearer Interpolation

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: GribMapKitView (NSViewRepresentable wrapping MKMapView)

**Files:**
- Create: `WeatherApp/Views/GribMapKitView.swift`

**Step 1: Implementierung**

`WeatherApp/Views/GribMapKitView.swift`:
```swift
import SwiftUI
import MapKit

/// Ersetzt den SwiftUI Map-View: gibt vollen Zugriff auf MKMapView-Delegate
/// für GribOverlayRenderer und Karten-Regions-Tracking.
struct GribMapKitView: NSViewRepresentable {
    @Bindable var weatherVM: WeatherViewModel
    var locationVM: LocationViewModel

    func makeNSView(context: Context) -> MKMapView {
        let mv = MKMapView()
        mv.delegate = context.coordinator
        mv.showsCompass = true
        mv.showsScale = true
        // Grid-Overlay einmalig hinzufügen
        mv.addOverlay(context.coordinator.overlay, level: .aboveRoads)
        return mv
    }

    func updateNSView(_ mv: MKMapView, context: Context) {
        let coord = context.coordinator

        // Ort-Annotation aktualisieren
        mv.removeAnnotations(mv.annotations)
        if let loc = locationVM.selectedLocation {
            let pin = MKPointAnnotation()
            pin.coordinate = loc.coordinate
            pin.title = loc.name
            mv.addAnnotation(pin)
            // Karte auf Ort zentrieren, nur wenn sich der Ort geändert hat
            if coord.lastCenteredLocation?.id != loc.id {
                coord.lastCenteredLocation = loc
                let region = MKCoordinateRegion(center: loc.coordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6))
                mv.setRegion(region, animated: true)
            }
        }

        // Overlay aktualisieren wenn Grid / Layer / Hour sich geändert haben
        let overlay = coord.overlay
        overlay.grid              = weatherVM.currentGrid
        overlay.selectedLayer     = weatherVM.selectedLayer
        overlay.selectedHourIndex = weatherVM.selectedHourIndex

        if let renderer = mv.renderer(for: overlay) as? GribOverlayRenderer {
            renderer.setNeedsDisplay()
        }

        // Wind-Annotations aktualisieren
        coord.updateWindAnnotations(on: mv, weatherVM: weatherVM)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(weatherVM: weatherVM, locationVM: locationVM)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        let weatherVM: WeatherViewModel
        let locationVM: LocationViewModel
        let overlay = GribMapOverlay()
        var lastCenteredLocation: Location?
        private var debounceTask: Task<Void, Never>?
        private var windAnnotations: [MKAnnotation] = []

        init(weatherVM: WeatherViewModel, locationVM: LocationViewModel) {
            self.weatherVM = weatherVM
            self.locationVM = locationVM
        }

        // Karten-Region hat sich geändert → Grid neu laden (debounced)
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mapView.region
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.8))
                guard !Task.isCancelled else { return }
                await self.weatherVM.loadGrid(for: region)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let go = overlay as? GribMapOverlay {
                return GribOverlayRenderer(overlay: go)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "pin")
            view.glyphImage = NSImage(systemSymbolName: "location.fill", accessibilityDescription: nil)
            if annotation is WindArrowAnnotation {
                // Wind-Pfeil: kleiner, kein Bubble
                let v = MKAnnotationView(annotation: annotation, reuseIdentifier: "wind")
                v.image = (annotation as! WindArrowAnnotation).arrowImage
                return v
            }
            return view
        }

        // Wind-Pfeile: alle 3. Gridpunkt, nur bei Wind-Layer
        func updateWindAnnotations(on mapView: MKMapView, weatherVM: WeatherViewModel) {
            let existing = windAnnotations
            guard weatherVM.selectedLayer == .wind,
                  let grid = weatherVM.currentGrid,
                  let speedData = grid.data[.wind]?[safe: weatherVM.selectedHourIndex],
                  weatherVM.selectedHourIndex < grid.windDirection.count
            else {
                mapView.removeAnnotations(existing)
                windAnnotations = []
                return
            }

            let dirData = grid.windDirection[weatherVM.selectedHourIndex]
            let nx = grid.region.nx
            let ny = grid.region.ny
            var newAnnotations: [WindArrowAnnotation] = []

            // Jeden 3. Punkt (ix und iy)
            for iy in stride(from: 0, to: ny, by: 3) {
                for ix in stride(from: 0, to: nx, by: 3) {
                    let pidx = grid.region.index(ix: ix, iy: iy)
                    guard let speed = speedData[safe: pidx].flatMap({ $0 }),
                          let dir   = dirData[safe: pidx].flatMap({ $0 }) else { continue }
                    let coord = CLLocationCoordinate2D(
                        latitude:  grid.region.latitude(iy: iy),
                        longitude: grid.region.longitude(ix: ix)
                    )
                    newAnnotations.append(WindArrowAnnotation(coordinate: coord,
                                                              speed: speed, direction: dir))
                }
            }

            mapView.removeAnnotations(existing)
            mapView.addAnnotations(newAnnotations)
            windAnnotations = newAnnotations
        }
    }
}

// MARK: - Wind-Pfeil-Annotation

final class WindArrowAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let speed: Double
    let direction: Double  // Grad meteorologisch (0=N, 90=O, 180=S, 270=W)

    init(coordinate: CLLocationCoordinate2D, speed: Double, direction: Double) {
        self.coordinate = coordinate
        self.speed = speed
        self.direction = direction
    }

    var arrowImage: NSImage {
        let size = CGSize(width: 20, height: 20)
        let img = NSImage(size: size, flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            // Pfeil: von Mitte nach oben, dann rotieren
            ctx.translateBy(x: rect.midX, y: rect.midY)
            // Meteorologische Richtung: Wind kommt AUS dieser Richtung → Pfeil zeigt DORTHIN
            ctx.rotate(by: CGFloat(self.direction) * .pi / 180)
            let length = CGFloat(min(1.0, self.speed / 60)) * 8 + 4
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: 0, y: -length))
            ctx.addLine(to: CGPoint(x: 0, y: length))
            // Pfeilkopf
            ctx.addLine(to: CGPoint(x: -3, y: length - 5))
            ctx.move(to: CGPoint(x: 0, y: length))
            ctx.addLine(to: CGPoint(x: 3, y: length - 5))
            ctx.strokePath()
            return true
        }
        return img
    }
}
```

**Step 2: Commit**
```bash
git add WeatherApp/Views/GribMapKitView.swift
git commit -m "$(cat <<'EOF'
feat: GribMapKitView (NSViewRepresentable) mit Region-Tracking + Wind-Pfeilen

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: WeatherViewModel erweitern (selectedHourIndex + loadGrid)

**Files:**
- Modify: `WeatherApp/ViewModels/WeatherViewModel.swift`

**Step 1: Implementierung**

Folgenden Code zu `WeatherViewModel` hinzufügen:

```swift
// Neue Properties
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
```

Import `MapKit` oben hinzufügen.

**Step 2: Commit**
```bash
git add WeatherApp/ViewModels/WeatherViewModel.swift
git commit -m "$(cat <<'EOF'
feat: WeatherViewModel — currentGrid, selectedHourIndex, loadGrid(for:)

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: MapWeatherView — Zeitslider + GribMapKitView + Download-Button

**Files:**
- Modify: `WeatherApp/Views/MapWeatherView.swift`

**Step 1: Komplette neue Implementierung**

`MapWeatherView.swift` (komplett ersetzen — der alte `WeatherDataPoint`-Mechanismus entfällt, da das Overlay die Darstellung übernimmt):

```swift
import SwiftUI
import MapKit
import AppKit
import UniformTypeIdentifiers

// UTI für GRIB2
extension UTType {
    static let grib2 = UTType(filenameExtension: "grib2") ?? .data
}

struct MapWeatherView: View {
    @Bindable var weatherVM: WeatherViewModel
    var locationVM: LocationViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            // Karte mit Overlay-Rendering via MKMapView
            GribMapKitView(weatherVM: weatherVM, locationVM: locationVM)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Zeitslider
                if let grid = weatherVM.currentGrid, grid.times.count > 1 {
                    TimeSliderView(times: grid.times,
                                   selectedIndex: $weatherVM.selectedHourIndex)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(10)
                }
            }

            HStack {
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    LayerPickerView(selectedLayer: $weatherVM.selectedLayer)
                    if weatherVM.isLoadingGrid {
                        ProgressView().scaleEffect(0.7)
                    }
                }
                .padding()
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    downloadGrib()
                } label: {
                    Label("Als GRIB2 speichern…", systemImage: "arrow.down.doc")
                }
                .disabled(weatherVM.currentGrid == nil)
            }
        }
    }

    private func downloadGrib() {
        guard let grid = weatherVM.currentGrid else { return }
        let panel = NSSavePanel()
        panel.title = "GRIB2-Raster speichern"
        panel.allowedContentTypes = [.grib2]
        panel.nameFieldStringValue = "Wettermodell-\(grid.model.displayName).grib2"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try GribWriter.write(grid: grid, to: url)
            } catch {
                // Fehler in Produktion: Logging oder Alert
            }
        }
    }
}

// MARK: - TimeSliderView

struct TimeSliderView: View {
    let times: [Date]
    @Binding var selectedIndex: Int

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E dd. MMM HH:mm"
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    var body: some View {
        VStack(spacing: 2) {
            Text(TimeSliderView.fmt.string(from: times[selectedIndex]) + " UTC")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Slider(value: Binding(
                get: { Double(selectedIndex) },
                set: { selectedIndex = Int($0.rounded()) }
            ), in: 0...Double(times.count - 1), step: 1)
        }
    }
}

// MARK: - LayerPickerView (unverändert aus bestehender Implementierung)
struct LayerPickerView: View {
    @Binding var selectedLayer: WeatherLayer

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(WeatherLayer.allCases) { layer in
                Button(layer.displayName) {
                    selectedLayer = layer
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedLayer == layer ? Color.accentColor : .secondary.opacity(0.6))
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
```

> **Hinweis:** Die alte `colorFor(value:layer:)` Methode und `WeatherDataPoint` aus der alten `MapWeatherView.swift` können entfernt werden; Farb-Logik ist jetzt in `GribOverlayRenderer`.

**Step 2: Alle Tests ausführen**
```bash
xcodebuild test -scheme WeatherApp -destination 'platform=macOS' -quiet 2>&1 | tail -20
```
Erwartet: `Test run passed.`

**Step 3: Commit**
```bash
git add WeatherApp/Views/MapWeatherView.swift
git commit -m "$(cat <<'EOF'
feat: MapWeatherView — Zeitslider, GRIB2-Download-Button, GribMapKitView integriert

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: xcodegen regenerieren + vollständiger Build-Check

**Step 1: xcodegen ausführen**
```bash
cd /Users/jjr/weather && xcodegen generate
```
Erwartet: `✅ Done.`

**Step 2: Alle Tests (final)**
```bash
xcodebuild test -scheme WeatherApp -destination 'platform=macOS' -quiet 2>&1 | tail -20
```
Erwartet: `** TEST SUCCEEDED **`

**Step 3: Finaler Commit**
```bash
git add project.yml WeatherApp.xcodeproj/
git commit -m "$(cat <<'EOF'
build: xcodegen — neue Dateien in Xcode-Projekt aufgenommen

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Zusammenfassung der neuen Dateien

| Datei | Zweck |
|-------|-------|
| `WeatherApp/Models/WeatherGrid.swift` | `GridRegion` + `WeatherGrid` Datenmodelle |
| `WeatherApp/Utilities/CollectionExtensions.swift` | Gemeinsame `[safe:]`-Extension |
| `WeatherApp/Services/GridFetchService.swift` | Parallele Raster-Abfrage (actor) |
| `WeatherApp/Services/GribWriter.swift` | WMO GRIB2 Ed.2 Binary-Writer |
| `WeatherApp/Views/GribMapOverlay.swift` | `MKOverlay` + `MKOverlayRenderer` (CGImage) |
| `WeatherApp/Views/GribMapKitView.swift` | `NSViewRepresentable` für MKMapView |
| `WeatherAppTests/WeatherGridTests.swift` | Modell-Tests |
| `WeatherAppTests/GridFetchServiceTests.swift` | Service-Tests (mock URLSession) |
| `WeatherAppTests/GribWriterTests.swift` | Binary-Format-Tests |
| `WeatherAppTests/URLSessionMock.swift` | Shared Mock für URLProtocol |
