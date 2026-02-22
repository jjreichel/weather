import Foundation

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
    /// - Precondition: 0 ≤ ix < nx, 0 ≤ iy < ny
    func index(ix: Int, iy: Int) -> Int {
        precondition(ix >= 0 && ix < nx && iy >= 0 && iy < ny,
                     "GridRegion.index: Index außerhalb des Rasters (\(ix),\(iy)) bei nx=\(nx),ny=\(ny)")
        return iy * nx + ix
    }

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

    /// Direkt-Initializer. nx und ny müssen ≥ 2 sein (andernfalls ist latStep/lonStep undefiniert).
    init(latMin: Double, latMax: Double, lonMin: Double, lonMax: Double, nx: Int, ny: Int) {
        precondition(nx >= 2 && ny >= 2, "GridRegion: nx und ny müssen ≥ 2 sein (nx=\(nx), ny=\(ny))")
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
