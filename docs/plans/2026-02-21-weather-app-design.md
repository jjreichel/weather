# Weather App – Design Document

**Datum:** 2026-02-21
**Status:** Genehmigt

---

## Überblick

Native macOS-App (Swift + SwiftUI) zur Anzeige verschiedener Wettermodelle und Echtzeit-Beobachtungsdaten. Die App kombiniert interaktive Karten (MapKit) mit Zeitreihen-Charts (Swift Charts) und aktuellen Stationsdaten.

---

## Navigation & UI-Struktur

Single-Window-App mit `NavigationSplitView`:

```
┌─────────────────────────────────────────────────────┐
│  [Location Picker]         [Model: ICON ▾]  [⚙]    │
├──────────────┬──────────────────────────────────────┤
│ Sidebar      │                                      │
│  🗺 Karte    │        Hauptinhalt                   │
│  📈 Charts   │   (Karte / Charts / Beobachtungen)   │
│  🌡 Aktuell  │                                      │
│              │                                      │
│  Orte        │                                      │
│  ★ Favoriten │                                      │
└──────────────┴──────────────────────────────────────┘
```

- **Karte:** MapKit-Karte mit wählbaren Wetter-Overlays (Temperatur, Niederschlag, Wind, Bewölkung)
- **Charts:** Swift Charts Meteogramm – stündlicher Modellvergleich (ICON, GFS, ECMWF)
- **Aktuell:** Aktuelle Beobachtungen von DWD-Stationen in der Nähe des gewählten Ortes
- **Toolbar:** Ortssuche, Modellauswahl, Einstellungen

---

## Datenquellen & APIs

### Open-Meteo (`api.open-meteo.com`)
- Kein API-Schlüssel erforderlich
- Modelle: ICON, GFS, ECMWF (pro Anfrage wählbar)
- Stündliche Variablen: Temperatur, Niederschlag, Wind (Geschwindigkeit + Richtung), Bewölkung, Luftdruck
- Vorhersagezeitraum: 7 Tage

### Bright Sky / DWD (`api.brightsky.dev`)
- Kein API-Schlüssel erforderlich
- Aktuelle Beobachtungen von DWD-Stationen
- ICON-Radardaten

### Wettermodelle (Enum)
```swift
enum WeatherModel { case ICON, GFS, ECMWF }
```

### Karten-Overlays (Enum)
```swift
enum WeatherLayer { case temperature, precipitation, wind, cloudCover }
```

**Hinweis:** Karten-Overlays werden als Datenpunkt-Raster über die sichtbare Kartenregion gerendert (keine Kachel-basierten Rasterbilder in v1).

---

## Architektur

**Muster:** MVVM mit `async/await` + `URLSession`

```
WeatherApp/
├── App/
│   └── WeatherApp.swift          # @main, WindowGroup
├── Views/
│   ├── ContentView.swift         # Sidebar + NavigationSplitView
│   ├── MapView.swift             # MapKit + Overlay-Rendering
│   ├── ChartsView.swift          # Swift Charts Meteogramm
│   ├── ObservationsView.swift    # Aktuelle DWD-Beobachtungen
│   └── LocationSearchView.swift  # Suche + Favoriten-Sheet
├── ViewModels/
│   ├── WeatherViewModel.swift    # Lädt und hält Vorhersagedaten
│   └── LocationViewModel.swift  # GPS, Suche, gespeicherte Orte
├── Services/
│   ├── OpenMeteoService.swift    # async/await URLSession
│   └── BrightSkyService.swift   # async/await URLSession
├── Models/
│   ├── Location.swift            # lat/lon, Name, isFavorite
│   ├── WeatherForecast.swift     # Stündliche/tägliche Vorhersagewerte
│   └── Observation.swift         # Aktuelle DWD-Stationsmessung
└── docs/
    └── plans/
        └── 2026-02-21-weather-app-design.md
```

**Standortverwaltung:**
- GPS via `CoreLocation`
- Geocoding / Ortssuche via `CLGeocoder`
- Favoriten persistiert in `UserDefaults`

---

## Fehlerbehandlung

- Netzwerkfehler → Inline-Banner in der betroffenen View mit Retry-Button (kein Modal)
- GPS nicht verfügbar → Fallback auf letzten bekannten Ort oder manuelle Suche
- Decode-Fehler → Logging + Anzeige "Keine Daten verfügbar"
- API-Timeout: 15 Sekunden

---

## Nicht in v1 enthalten

- Unit-Tests (Struktur ist darauf ausgelegt, leicht ergänzbar)
- Push-Benachrichtigungen / Hintergrundaktualisierung
- Widgets
- Kachel-basierte Raster-Overlays (Windy-Stil)
- Multi-Window-Unterstützung
