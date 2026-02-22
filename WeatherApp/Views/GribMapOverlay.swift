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
        // Snapshot: MapKit ruft draw auf einem Render-Thread auf; alle Properties einmalig lesen
        let go = gridOverlay
        let layer = go.selectedLayer
        let hourIndex = go.selectedHourIndex
        guard let grid = go.grid,
              let values = grid.data[layer]?[safe: hourIndex]
        else { return }
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
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                    provider: provider, decode: nil,
                                    shouldInterpolate: true,
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
            let t = max(0, min(1, (v + 20) / 60))
            return gradient(t, stops: [
                (0.0, (0,   0,   200)),
                (0.4, (0,   200, 200)),
                (0.6, (50,  200, 50)),
                (0.8, (230, 200, 0)),
                (1.0, (200, 0,   0)),
            ])
        case .wind:
            let t = max(0, min(1, v / 60))
            return gradient(t, stops: [
                (0.0, (0,   180, 0)),
                (0.5, (220, 220, 0)),
                (1.0, (200, 0,   0)),
            ])
        case .precipitation:
            let t = max(0, min(1, v / 10))
            return gradient(t, stops: [
                (0.0, (230, 230, 255)),
                (0.3, (0,   100, 255)),
                (1.0, (0,   0,   150)),
            ])
        case .cloudCover:
            let t = max(0, min(1, v / 100))
            let c = UInt8(200 - Int(t * 150))
            return (c, c, UInt8(max(0, Int(c) - 50)), 200)
        case .wave:
            let t = max(0, min(1, v / 10))
            return gradient(t, stops: [
                (0.0, (200, 240, 255)),
                (1.0, (0,   40,  160)),
            ])
        case .cape:
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
            return (r, g, b, 200)
        }
        let last = stops.last!.1
        return (UInt8(last.0), UInt8(last.1), UInt8(last.2), 200)
    }
}
