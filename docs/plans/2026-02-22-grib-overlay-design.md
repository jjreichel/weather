# GRIB-Overlay Design

**Datum:** 2026-02-22
**Status:** Genehmigt

---

## Überblick

Erweiterung der bestehenden Weather-App um ein flächendeckendes Karten-Overlay auf Basis eines regulären Wettermodell-Rasters. Nutzer können Temperatur, Wind (Vektoren), Niederschlag, CAPE und Wellenhöhe über den gesamten sichtbaren Kartenausschnitt visualisieren, durch 7-Tage-Vorhersagestunden blättern und die Rasterdaten als vollständige GRIB2-Datei exportieren.

---

## Datenquellen

### Open-Meteo Forecast API
- URL: `https://api.open-meteo.com/v1/forecast`
- Variablen: `temperature_2m`, `wind_speed_10m`, `wind_direction_10m`, `precipitation`, `cape`
- Vorhersagezeitraum: 7 Tage stündlich (168 Zeitschritte)

### Open-Meteo Marine API
- URL: `https://marine-api.open-meteo.com/v1/marine`
- Variablen: `wave_height`
- Nur für Gitterpunkte über Wasser aufgerufen; Landpunkte werden im GRIB2 als fehlend (Bit-Map-Section) markiert

---

## Neue Architektur-Komponenten

```
Services/
  GridFetchService.swift      (actor) — lädt Gitter parallel aus Open-Meteo
  GribWriter.swift            — schreibt WMO GRIB2-Binary (Ed. 2)

Models/
  WeatherGrid.swift           — 2D-Rasterdaten aller Variablen + Zeitschritte
  WeatherLayer.swift          — erweitert um .wave, .cape

Views/
  GribMapOverlay.swift        — MKOverlay-Konformität (Bounding-Box)
  GribOverlayRenderer.swift   — MKOverlayRenderer, rendert CGImage
```

`WeatherViewModel` erhält ein neues Published-Property `currentGrid: WeatherGrid?`.

---

## Gitterauflösung (adaptiv, immer ~300 Punkte)

| Kartenspanne (°Breitengrad) | Schrittweite | Gitterdimension |
|-----------------------------|-------------|-----------------|
| > 40° (Kontinent) | 2,0° | ~300 |
| 15–40° (Region) | 0,5° | ~300 |
| 5–15° (Land) | 0,25° | ~300 |
| < 5° (lokal) | 0,1° | ~300 |

Beim Ändern der Kartenregion: Debounce 0,8 s, dann `GridFetchService.fetchGrid(region:model:)`.

---

## Datenmodell

```swift
struct WeatherGrid: Sendable {
    let region: MKCoordinateRegion
    let nx: Int, ny: Int          // Gitterdimensionen
    let times: [Date]             // 168 Zeitschritte (UTC)
    let model: WeatherModel
    // [WeatherLayer: [hourIndex][pointIndex]] — pointIndex = y*nx + x
    let data: [WeatherLayer: [[Double?]]]
}
```

---

## Rendering (GribOverlayRenderer)

Erbt von `MKOverlayRenderer`. Die `draw(_:zoomScale:in:)` Methode:

1. Liest `WeatherGrid.data[selectedLayer][selectedHourIndex]` (nx×ny Werte)
2. Erstellt einen nx×ny `CGImage` via `CGContext` (RGBA)
3. Bilineare Interpolation zwischen Gitterpunkten → glatte Farbverläufe
4. Wendet Farbskala an (je Variable unterschiedliche Rampe)
5. Zeichnet das Bild skaliert auf die Overlay-Boundingbox in den Map-Kontext

### Wind-Vektoren

Zusätzlich zum Farb-Overlay: SwiftUI `ForEach` über ein ausgedünntes Subgitter (jeder 3. Punkt, ~33 Pfeile). Jeder Pfeil ist eine `Annotation` mit `Canvas`-Pfeil, rotiert um die Windrichtung, Länge proportional zur Windgeschwindigkeit.

---

## UI-Änderungen

### Zeitslider (MapWeatherView)
- Am unteren Rand der Karte: SwiftUI `Slider(value:in:step:)` über 0…167
- Darunter Zeitanzeige: z.B. „Mo 14:00 UTC"
- Slider-Drag löst sofortiges Re-Rendering aus (Daten bereits im Speicher)

### Download-Button
- In der Map-Toolbar: „Als GRIB2 speichern…"
- Öffnet `NSSavePanel` mit `allowedContentTypes: [.grib2]`
- `GribWriter` schreibt alle Variablen × alle Zeitschritte in eine `.grib2`-Datei

### Layer-Picker
- Bestehende Layer bleiben (Temperatur, Wind, Niederschlag, Bewölkung)
- Neu: **Wellen** (blau, Skala 0–10 m) und **CAPE** (gelb-rot, Skala 0–3000 J/kg)

---

## GRIB2-Export (GribWriter)

Format: WMO FM 92 GRIB Edition 2. Eine GRIB2-Datei enthält alle Variablen × Zeitschritte als separate GRIB2-Messages.

### Sections pro Message

| Section | Inhalt |
|---------|--------|
| 0 | Indicator: `"GRIB"`, Gesamtlänge, Disziplin, Edition 2 |
| 1 | Identification: Referenzzeit (T0 UTC), Typ = Vorhersage |
| 3 | Grid Definition Template 0: reguläres lat/lon-Gitter, Ni, Nj, La1, Lo1, La2, Lo2, Di, Dj |
| 4 | Product Definition Template 0: Parameterkategorie/-nummer, Vorhersagestunde |
| 5 | Data Representation Template 0 (Simple Packing): Referenzwert, Skalierung |
| 6 | Bit-Map Section: 1 Bit pro Gitterpunkt (0 = fehlend, z.B. Wellen auf Land) |
| 7 | Data Section: gepackte Ganzzahlwerte |
| 8 | End: `"7777"` |

### Variablen-Tabelle (WMO Table 4.2)

| Variable | Disziplin | Kategorie | Parameter |
|----------|-----------|-----------|-----------|
| Temperatur 2m | 0 (Atmosphäre) | 0 (Temperatur) | 0 |
| Windgeschwindigkeit | 0 | 2 (Wind) | 1 |
| Windrichtung | 0 | 2 (Wind) | 0 |
| Niederschlag | 0 | 1 (Feuchte) | 8 |
| CAPE | 0 | 7 (Stabilität) | 6 |
| Signif. Wellenhöhe | 10 (Ozean) | 0 (Wellen) | 3 |

---

## Nicht in diesem Feature

- Animierte Streamlines (Wind als Fluss-Animation wie Windy)
- Import externer GRIB-Dateien von Drittquellen
- Push-Cache / Hintergrundaktualisierung des Gitters
