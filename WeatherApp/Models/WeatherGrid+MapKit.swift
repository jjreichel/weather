import MapKit

extension GridRegion {
    /// Erstellt ein GridRegion aus dem sichtbaren MapKit-Kartenausschnitt.
    /// Schrittweite wird adaptiv gewählt, sodass ~300 Punkte entstehen.
    init(from region: MKCoordinateRegion) {
        let step = GridRegion.step(for: region.span.latitudeDelta)
        let lat0 = region.center.latitude  - region.span.latitudeDelta  / 2
        let lat1 = region.center.latitude  + region.span.latitudeDelta  / 2
        let lon0 = region.center.longitude - region.span.longitudeDelta / 2
        let lon1 = region.center.longitude + region.span.longitudeDelta / 2
        self.init(
            latMin: (lat0 / step).rounded(.down) * step,
            latMax: (lat1 / step).rounded(.up)   * step,
            lonMin: (lon0 / step).rounded(.down) * step,
            lonMax: (lon1 / step).rounded(.up)   * step,
            nx: max(2, Int(((lon1 - lon0) / step).rounded(.up)) + 1),
            ny: max(2, Int(((lat1 - lat0) / step).rounded(.up)) + 1)
        )
    }
}
