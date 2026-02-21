import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
final class LocationViewModel: NSObject {
    var currentLocation: Location?
    var selectedLocation: Location?
    var favorites: [Location] = []
    var searchResults: [Location] = []
    var searchText: String = ""
    var isSearching = false
    var locationError: String?

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let favoritesKey = "savedFavorites"
    private var hasSetInitialLocation = false

    override init() {
        super.init()
        loadFavorites()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func search(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        do {
            let placemarks = try await geocoder.geocodeAddressString(query)
            searchResults = placemarks.compactMap { pm in
                guard let coord = pm.location?.coordinate else { return nil }
                let name = [pm.name, pm.locality].compactMap { $0 }.first ?? "Unbekannt"
                return Location(name: name, latitude: coord.latitude, longitude: coord.longitude)
            }
        } catch {
            searchResults = []
        }
    }

    func addFavorite(_ location: Location) {
        guard !favorites.contains(where: {
            abs($0.latitude - location.latitude) < 0.01 &&
            abs($0.longitude - location.longitude) < 0.01
        }) else { return }
        var loc = location
        loc.isFavorite = true
        favorites.append(loc)
        saveFavorites()
    }

    func removeFavorite(_ location: Location) {
        favorites.removeAll { $0.id == location.id }
        saveFavorites()
    }

    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }

    private func loadFavorites() {
        guard let data = UserDefaults.standard.data(forKey: favoritesKey),
              let saved = try? JSONDecoder().decode([Location].self, from: data) else { return }
        favorites = saved
    }
}

extension LocationViewModel: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            let placemarks = try? await CLGeocoder().reverseGeocodeLocation(loc)
            let name = placemarks?.first?.locality ?? "Aktueller Standort"
            let location = Location(
                name: name,
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude
            )
            self.currentLocation = location
            if !self.hasSetInitialLocation {
                self.selectedLocation = location
                self.hasSetInitialLocation = true
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        Task { @MainActor in
            self.locationError = error.localizedDescription
        }
    }
}
