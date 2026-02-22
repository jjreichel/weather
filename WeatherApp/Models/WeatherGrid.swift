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
    let times: [Date]                           // UTC-Zeitpunkte
    let data: [WeatherLayer: [[Double?]]]       // [layer][hour][point]
    let windDirection: [[Double?]]              // [hour][point] — Richtung in Grad
}
