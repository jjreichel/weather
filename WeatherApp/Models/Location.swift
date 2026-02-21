import Foundation
import CoreLocation

struct Location: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var isFavorite: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.isFavorite = isFavorite
    }
}
