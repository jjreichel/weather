# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

The Xcode project is **not committed** — regenerate it whenever new Swift files are added:

```bash
xcodegen generate
```

Build and test via Xcode UI or `xcodebuild`:

```bash
# Alle Tests ausführen
xcodebuild test -scheme WeatherApp -destination 'platform=macOS'

# Einzelnen Test ausführen (Swift Testing verwendet `--filter`)
xcodebuild test -scheme WeatherApp -destination 'platform=macOS' \
  -only-testing WeatherAppTests/decodeOpenMeteoResponse
```

- Swift 6.0, macOS 14.0 deployment target
- Tests use **Swift Testing** (`@Test`, `#expect`) — kein XCTest
- Bundle ID: `com.jjreichel.WeatherApp`

## Architektur

MVVM mit Swift 6 Concurrency:

- **`@Observable` ViewModels** auf `@MainActor`: `WeatherViewModel`, `LocationViewModel`
- **`actor` Services** für Netzwerkzugriffe: `OpenMeteoService`, `BrightSkyService`
- ViewModels instanziieren ihre Services direkt (kein Dependency Injection)
- Alle Models sind `Sendable` und `Equatable`

### Datenfluss

```
LocationViewModel (Ortauswahl + Favoriten)
    └─→ WeatherViewModel.loadAll(for:)
            ├─→ OpenMeteoService.fetchForecast(...)  [parallel per WeatherModel]
            └─→ BrightSkyService.fetchCurrentObservation(...)
```

`WeatherViewModel.loadAll` startet alle drei Wettermodelle (ICON, GFS, ECMWF) und die Stationsbeobachtung parallel via `TaskGroup` und `async let`.

### Views

`ContentView` verwendet `NavigationSplitView` mit drei Detail-Views:
- **MapWeatherView** — Karte mit Wetterüberlagerung
- **ChartsView** — Zeitreihen-Charts (SwiftUI Charts)
- **ObservationsView** — aktuelle DWD-Stationsbeobachtung

Die Ortsuche öffnet `LocationSearchView` als Sheet.

## APIs

| Dienst | Endpunkt | Authentifizierung |
|--------|----------|-------------------|
| Open-Meteo | `https://api.open-meteo.com/v1/forecast` | Kein API-Key |
| Bright Sky (DWD) | `https://api.brightsky.dev/current_weather` | Kein API-Key |

Open-Meteo wird immer mit `timezone=UTC` angefragt. Stundenwerte werden als UTC-Strings im Format `yyyy-MM-dd'T'HH:mm` geliefert.

`WeatherModel` rawValues sind die API-Modellnamen: `icon_seamless`, `gfs_seamless`, `ecmwf_ifs025`.

## Kommentarsprache

Kommentare im Code auf **Deutsch** schreiben.
