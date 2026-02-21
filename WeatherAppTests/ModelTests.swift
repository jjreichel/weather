import Testing
@testable import WeatherApp
import Foundation

@Test func locationCodableRoundtrip() throws {
    let loc = Location(name: "Berlin", latitude: 52.52, longitude: 13.41, isFavorite: true)
    let data = try JSONEncoder().encode(loc)
    let decoded = try JSONDecoder().decode(Location.self, from: data)
    #expect(decoded.id == loc.id)
    #expect(decoded.name == loc.name)
    #expect(decoded.latitude == loc.latitude)
    #expect(decoded.longitude == loc.longitude)
    #expect(decoded.isFavorite == loc.isFavorite)
}

@Test func hourlyEntryFields() {
    let entry = WeatherForecast.HourlyEntry(
        time: Date(),
        temperature: 15.5,
        precipitation: 0.2,
        windSpeed: 30,
        windDirection: 180,
        cloudCover: 75
    )
    #expect(entry.temperature == 15.5)
    #expect(entry.precipitation == 0.2)
    #expect(entry.windSpeed == 30)
    #expect(entry.windDirection == 180)
    #expect(entry.cloudCover == 75)
}
