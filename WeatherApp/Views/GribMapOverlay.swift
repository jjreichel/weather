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

    /// Max. Texturgröße pro Draw-Aufruf (Performance).
    private static let maxRenderDimension = 768
    /// Mindest-Faktor gegenüber Rohraster (schärfere Kanten).
    private static let minUpscalePerAxis = 6

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in ctx: CGContext) {
        let go = gridOverlay
        let layer = go.selectedLayer
        let hourIndex = go.selectedHourIndex
        guard let grid = go.grid,
              let values = grid.data[layer]?[safe: hourIndex]
        else { return }

        let region = grid.region
        let nx = region.nx
        let ny = region.ny
        let drawRect = rect(for: gridOverlay.boundingMapRect)

        // Zoom-abhängige Auflösung: beim Hineinzoomen mehr Pixel, max. gedeckelt
        let zoomFactor = max(1.0, min(Double(zoomScale) * 0.35, 6.0))
        let renderW = min(
            max(nx * Self.minUpscalePerAxis, Int(drawRect.width * zoomFactor)),
            Self.maxRenderDimension
        )
        let renderH = min(
            max(ny * Self.minUpscalePerAxis, Int(drawRect.height * zoomFactor)),
            Self.maxRenderDimension
        )

        let latSpan = region.latMax - region.latMin
        let lonSpan = region.lonMax - region.lonMin
        var pixels = [UInt8](repeating: 0, count: renderW * renderH * 4)

        for py in 0..<renderH {
            let lat = region.latMax - (Double(py) + 0.5) / Double(renderH) * latSpan
            for px in 0..<renderW {
                let lon = region.lonMin + (Double(px) + 0.5) / Double(renderW) * lonSpan
                let value = Self.bilinearSample(values: values, region: region, lat: lat, lon: lon)
                let (r, g, b, a) = rgba(value: value, layer: layer)
                let base = (py * renderW + px) * 4
                pixels[base] = r
                pixels[base + 1] = g
                pixels[base + 2] = b
                pixels[base + 3] = a
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                width: renderW,
                height: renderH,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: renderW * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else { return }

        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: drawRect)
        ctx.restoreGState()
    }

    /// Bilineare Interpolation zwischen den vier umgebenden Rasterpunkten.
    static func bilinearSample(
        values: [Double?],
        region: GridRegion,
        lat: Double,
        lon: Double
    ) -> Double? {
        guard lat >= region.latMin, lat <= region.latMax,
              lon >= region.lonMin, lon <= region.lonMax,
              region.lonStep > 0, region.latStep > 0 else { return nil }

        let gx = (lon - region.lonMin) / region.lonStep
        let gy = (lat - region.latMin) / region.latStep
        let ix0 = max(0, min(region.nx - 1, Int(floor(gx))))
        let iy0 = max(0, min(region.ny - 1, Int(floor(gy))))
        let ix1 = min(ix0 + 1, region.nx - 1)
        let iy1 = min(iy0 + 1, region.ny - 1)
        let tx = gx - Double(ix0)
        let ty = gy - Double(iy0)

        func sample(_ ix: Int, _ iy: Int) -> Double? {
            values[safe: region.index(ix: ix, iy: iy)].flatMap { $0 }
        }

        let corners: [(Double?, Double)] = [
            (sample(ix0, iy0), (1 - tx) * (1 - ty)),
            (sample(ix1, iy0), tx * (1 - ty)),
            (sample(ix0, iy1), (1 - tx) * ty),
            (sample(ix1, iy1), tx * ty),
        ]
        let valid = corners.compactMap { value, weight -> (Double, Double)? in
            guard let value else { return nil }
            return (value, weight)
        }
        guard !valid.isEmpty else { return nil }
        let weightSum = valid.reduce(0.0) { $0 + $1.1 }
        guard weightSum > 0 else { return nil }
        return valid.reduce(0.0) { $0 + $1.0 * $1.1 } / weightSum
    }

    // MARK: - Farbskala (RGBA)

    private func rgba(value: Double?, layer: WeatherLayer) -> (UInt8, UInt8, UInt8, UInt8) {
        guard let v = value else { return (128, 128, 128, 0) }

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
            return (c, c, UInt8(max(0, Int(c) - 50)), 210)
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
            return (r, g, b, 220)
        }
        let last = stops.last!.1
        return (UInt8(last.0), UInt8(last.1), UInt8(last.2), 220)
    }
}
