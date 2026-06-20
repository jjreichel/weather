import Foundation
import CoreLocation

struct GridInspection: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let ix: Int
    let iy: Int

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension WeatherGrid {
    /// Nächster Rasterpunkt zur angeklickten Koordinate (nil wenn außerhalb).
    func nearestGridIndex(latitude: Double, longitude: Double) -> (ix: Int, iy: Int)? {
        let r = region
        guard latitude >= r.latMin, latitude <= r.latMax,
              longitude >= r.lonMin, longitude <= r.lonMax else { return nil }
        let ix = min(r.nx - 1, max(0, Int(((longitude - r.lonMin) / r.lonStep).rounded())))
        let iy = min(r.ny - 1, max(0, Int(((latitude - r.latMin) / r.latStep).rounded())))
        return (ix, iy)
    }

    func inspection(at latitude: Double, longitude: Double) -> GridInspection? {
        guard let (ix, iy) = nearestGridIndex(latitude: latitude, longitude: longitude) else { return nil }
        return GridInspection(
            latitude: region.latitude(iy: iy),
            longitude: region.longitude(ix: ix),
            ix: ix, iy: iy
        )
    }

    func value(at ix: Int, iy: Int, layer: WeatherLayer, hourIndex: Int) -> Double? {
        data[layer]?[safe: hourIndex]?[safe: region.index(ix: ix, iy: iy)].flatMap { $0 }
    }

    func windDirection(at ix: Int, iy: Int, hourIndex: Int) -> Double? {
        windDirection[safe: hourIndex]?[safe: region.index(ix: ix, iy: iy)].flatMap { $0 }
    }
}
