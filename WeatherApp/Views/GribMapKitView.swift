import SwiftUI
import MapKit
import AppKit

/// MKMapView mit Klick-Erkennung für Rasterpunkt-Abfrage.
final class ClickableMKMapView: MKMapView {
    var onMapClick: ((CLLocationCoordinate2D) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let coord = convert(point, toCoordinateFrom: self)
        onMapClick?(coord)
        super.mouseDown(with: event)
    }
}

/// Ersetzt den SwiftUI Map-View: gibt vollen Zugriff auf MKMapView-Delegate
/// für GribOverlayRenderer und Karten-Regions-Tracking.
struct GribMapKitView: NSViewRepresentable {
    @Bindable var weatherVM: WeatherViewModel
    var locationVM: LocationViewModel
    var zoomInTrigger: Int = 0
    var zoomOutTrigger: Int = 0
    @Binding var liveMapRegion: MKCoordinateRegion?

    func makeNSView(context: Context) -> MKMapView {
        let mv = ClickableMKMapView()
        mv.delegate = context.coordinator
        mv.showsCompass = true
        mv.showsScale = true
        mv.isZoomEnabled = true
        mv.isScrollEnabled = true
        mv.addOverlay(context.coordinator.overlay, level: .aboveRoads)
        context.coordinator.publishRegion(mv.region, weatherVM: weatherVM)
        mv.onMapClick = { [weak coordinator = context.coordinator] coord in
            Task { @MainActor in
                coordinator?.handleMapClick(at: coord)
            }
        }
        return mv
    }

    func updateNSView(_ mv: MKMapView, context: Context) {
        let coord = context.coordinator
        coord.liveMapRegionBinding = $liveMapRegion

        coord.applyZoomIfNeeded(on: mv, zoomInTrigger: zoomInTrigger, zoomOutTrigger: zoomOutTrigger)

        // Ort-Pin nur bei Ortswechsel aktualisieren
        if locationVM.selectedLocation?.id != coord.displayedLocationId {
            if let old = coord.locationPin { mv.removeAnnotation(old) }
            coord.locationPin = nil
            coord.displayedLocationId = locationVM.selectedLocation?.id
            if let loc = locationVM.selectedLocation {
                let pin = MKPointAnnotation()
                pin.coordinate = loc.coordinate
                pin.title = loc.name
                mv.addAnnotation(pin)
                coord.locationPin = pin
                coord.lastCenteredLocation = loc
                let region = MKCoordinateRegion(center: loc.coordinate,
                                                span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6))
                mv.setRegion(region, animated: true)
                coord.publishRegion(region, weatherVM: weatherVM)
            } else {
                coord.lastCenteredLocation = nil
            }
        }

        coord.updateOverlay(on: mv, weatherVM: weatherVM)
        coord.updateWindAnnotationsIfNeeded(on: mv, weatherVM: weatherVM)
        coord.updateInspectionPinIfNeeded(on: mv, weatherVM: weatherVM)

        if weatherVM.currentGrid != nil,
           let renderer = mv.renderer(for: coord.overlay) as? GribOverlayRenderer {
            renderer.setNeedsDisplay()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(weatherVM: weatherVM)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        let weatherVM: WeatherViewModel
        let overlay = GribMapOverlay()
        var lastCenteredLocation: Location?
        var displayedLocationId: UUID?
        private(set) var latestRegion: MKCoordinateRegion?
        private var windAnnotations: [MKAnnotation] = []
        var locationPin: MKPointAnnotation?
        var inspectionPin: MKPointAnnotation?

        // Zustand für inkrementelle Updates (updateNSView nicht bei jedem Progress-Tick)
        private var overlayGridKey: String = ""
        private var overlayLayer: WeatherLayer = .temperature
        private var overlayHour: Int = 0
        private var windStateKey: String?
        private var inspectionKey: String?
        private var handledZoomInTrigger = 0
        private var handledZoomOutTrigger = 0
        var liveMapRegionBinding: Binding<MKCoordinateRegion?>?

        init(weatherVM: WeatherViewModel) {
            self.weatherVM = weatherVM
        }

        func publishRegion(_ region: MKCoordinateRegion, weatherVM: WeatherViewModel) {
            latestRegion = region
            if let binding = liveMapRegionBinding,
               binding.wrappedValue.map({ WeatherViewModel.regionsEqual($0, region) }) != true {
                binding.wrappedValue = region
            }
            weatherVM.setVisibleMapRegion(region)
        }

        func applyZoomIfNeeded(on mapView: MKMapView, zoomInTrigger: Int, zoomOutTrigger: Int) {
            if handledZoomInTrigger != zoomInTrigger {
                handledZoomInTrigger = zoomInTrigger
                zoom(by: 2.0, on: mapView)
            }
            if handledZoomOutTrigger != zoomOutTrigger {
                handledZoomOutTrigger = zoomOutTrigger
                zoom(by: 0.5, on: mapView)
            }
        }

        private func zoom(by factor: Double, on mapView: MKMapView) {
            var region = mapView.region
            region.span.latitudeDelta = max(region.span.latitudeDelta / factor, GridRegion.minimumMapSpan)
            region.span.longitudeDelta = max(region.span.longitudeDelta / factor, GridRegion.minimumMapSpan)
            mapView.setRegion(region, animated: true)
            publishRegion(region, weatherVM: weatherVM)
        }

        func handleMapClick(at coordinate: CLLocationCoordinate2D) {
            weatherVM.inspectGrid(at: coordinate)
        }

        func updateOverlay(on mapView: MKMapView, weatherVM: WeatherViewModel) {
            let gridKey = weatherVM.currentGrid.map { grid in
                "\(grid.model.rawValue)-\(grid.region.nx)x\(grid.region.ny)-\(grid.times.count)"
            } ?? "none"
            let layer = weatherVM.selectedLayer
            let hour = weatherVM.selectedHourIndex
            guard gridKey != overlayGridKey
                    || layer != overlayLayer
                    || hour != overlayHour else { return }

            overlayGridKey = gridKey
            overlayLayer = layer
            overlayHour = hour

            let previousBounds = overlay.boundingMapRect
            overlay.grid = weatherVM.currentGrid
            overlay.selectedLayer = layer
            overlay.selectedHourIndex = hour

            if !MKMapRectEqualToRect(overlay.boundingMapRect, previousBounds) {
                mapView.removeOverlay(overlay)
                mapView.addOverlay(overlay, level: .aboveRoads)
            } else if let renderer = mapView.renderer(for: overlay) as? GribOverlayRenderer {
                renderer.setNeedsDisplay()
            }
        }

        func updateInspectionPinIfNeeded(on mapView: MKMapView, weatherVM: WeatherViewModel) {
            let key = weatherVM.gridInspection.map {
                "\($0.latitude),\($0.longitude)"
            } ?? ""
            guard key != inspectionKey else { return }
            inspectionKey = key

            if let old = inspectionPin {
                mapView.removeAnnotation(old)
                inspectionPin = nil
            }
            guard let inspection = weatherVM.gridInspection else { return }
            let pin = MKPointAnnotation()
            pin.coordinate = inspection.coordinate
            pin.title = "Rasterpunkt"
            mapView.addAnnotation(pin)
            inspectionPin = pin
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !weatherVM.isLoadingGrid, !weatherVM.isExportingGrib else { return }
            publishRegion(mapView.region, weatherVM: weatherVM)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay === self.overlay {
                return GribOverlayRenderer(overlay: self.overlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            if let wind = annotation as? WindArrowAnnotation {
                let id = "wind-\(wind.imageKey)"
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                    ?? MKAnnotationView(annotation: wind, reuseIdentifier: id)
                v.annotation = wind
                v.image = wind.cachedImage
                return v
            }
            if annotation === inspectionPin {
                let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "inspect")
                view.markerTintColor = .systemOrange
                view.glyphImage = NSImage(systemSymbolName: "scope", accessibilityDescription: nil)
                return view
            }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "pin")
            view.glyphImage = NSImage(systemSymbolName: "location.fill", accessibilityDescription: nil)
            return view
        }

        func updateWindAnnotationsIfNeeded(on mapView: MKMapView, weatherVM: WeatherViewModel) {
            let key: String
            if weatherVM.selectedLayer == .wind,
               let grid = weatherVM.currentGrid {
                key = "\(grid.model.rawValue)-\(grid.region.nx)x\(grid.region.ny)-\(weatherVM.selectedHourIndex)"
            } else {
                key = "none"
            }
            guard key != windStateKey else { return }
            windStateKey = key

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
                    newAnnotations.append(WindArrowAnnotation(
                        coordinate: CLLocationCoordinate2D(
                            latitude:  grid.region.latitude(iy: iy),
                            longitude: grid.region.longitude(ix: ix)
                        ),
                        speed: speed,
                        direction: dir
                    ))
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
    let direction: Double
    let cachedImage: NSImage
    let imageKey: String

    init(coordinate: CLLocationCoordinate2D, speed: Double, direction: Double) {
        self.coordinate = coordinate
        self.speed = speed
        self.direction = direction
        let speedBucket = Int(speed.rounded())
        let dirBucket = Int(direction.rounded())
        self.imageKey = "\(speedBucket)-\(dirBucket)"
        self.cachedImage = Self.renderArrow(speed: speed, direction: direction)
    }

    private static func renderArrow(speed: Double, direction: Double) -> NSImage {
        let size = CGSize(width: 20, height: 20)
        return NSImage(size: size, flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: CGFloat(direction + 180) * .pi / 180)
            let length = CGFloat(min(1.0, speed / 60)) * 8 + 4
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
