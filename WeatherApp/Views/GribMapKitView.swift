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
            if coord.lastCenteredLocation?.id != loc.id {
                coord.lastCenteredLocation = loc
                let region = MKCoordinateRegion(center: loc.coordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6))
                mv.setRegion(region, animated: true)
            }
        }

        // Overlay-Properties aktualisieren
        let overlay = coord.overlay
        overlay.grid              = weatherVM.currentGrid
        overlay.selectedLayer     = weatherVM.selectedLayer
        overlay.selectedHourIndex = weatherVM.selectedHourIndex

        if let renderer = mv.renderer(for: overlay) as? GribOverlayRenderer {
            renderer.setNeedsDisplay()
        }

        // Wind-Pfeile aktualisieren
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
            if let wind = annotation as? WindArrowAnnotation {
                let v = MKAnnotationView(annotation: wind, reuseIdentifier: "wind")
                v.image = wind.arrowImage
                return v
            }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "pin")
            view.glyphImage = NSImage(systemSymbolName: "location.fill", accessibilityDescription: nil)
            return view
        }

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

            for iy in stride(from: 0, to: ny, by: 3) {
                for ix in stride(from: 0, to: nx, by: 3) {
                    let pidx = grid.region.index(ix: ix, iy: iy)
                    guard let speed = speedData[safe: pidx].flatMap({ $0 }),
                          let dir   = dirData[safe: pidx].flatMap({ $0 }) else { continue }
                    let coordinate = CLLocationCoordinate2D(
                        latitude:  grid.region.latitude(iy: iy),
                        longitude: grid.region.longitude(ix: ix)
                    )
                    newAnnotations.append(WindArrowAnnotation(coordinate: coordinate,
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
    let direction: Double  // Meteorologisch (0=N, 90=O, 180=S, 270=W)

    init(coordinate: CLLocationCoordinate2D, speed: Double, direction: Double) {
        self.coordinate = coordinate
        self.speed = speed
        self.direction = direction
    }

    var arrowImage: NSImage {
        let size = CGSize(width: 20, height: 20)
        return NSImage(size: size, flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: CGFloat(self.direction) * .pi / 180)
            let length = CGFloat(min(1.0, self.speed / 60)) * 8 + 4
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: 0, y: -length))
            ctx.addLine(to: CGPoint(x: 0, y: length))
            ctx.addLine(to: CGPoint(x: -3, y: length - 5))
            ctx.move(to: CGPoint(x: 0, y: length))
            ctx.addLine(to: CGPoint(x: 3, y: length - 5))
            ctx.strokePath()
            return true
        }
    }
}
