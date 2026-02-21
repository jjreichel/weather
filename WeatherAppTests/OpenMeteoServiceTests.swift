import Testing
@testable import WeatherApp
import Foundation

@Test func decodeOpenMeteoResponse() throws {
    let json = """
    {
      "latitude": 52.52,
      "longitude": 13.41,
      "hourly": {
        "time": ["2024-01-01T00:00", "2024-01-01T01:00"],
        "temperature_2m": [5.1, 4.9],
        "precipitation": [0.0, 0.1],
        "wind_speed_10m": [12.3, 11.5],
        "wind_direction_10m": [180.0, 175.0],
        "cloud_cover": [75.0, 80.0]
      }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: json)
    #expect(response.hourly.time.count == 2)
    #expect(response.hourly.temperature2m.first == 5.1)
    #expect(response.hourly.precipitation.last == 0.1)
    #expect(response.hourly.windspeed10m.first == 12.3)
    #expect(response.hourly.cloudcover.last == 80.0)
}

@Test func openMeteoToForecastConversion() throws {
    let json = """
    {
      "hourly": {
        "time": ["2024-01-01T00:00"],
        "temperature_2m": [5.1],
        "precipitation": [0.0],
        "wind_speed_10m": [12.3],
        "wind_direction_10m": [180.0],
        "cloud_cover": [75.0]
      }
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: json)
    let location = Location(name: "Berlin", latitude: 52.52, longitude: 13.41)
    let forecast = response.toForecast(location: location, model: .icon)

    #expect(forecast.model == .icon)
    #expect(forecast.hourly.count == 1)
    #expect(forecast.hourly.first?.temperature == 5.1)
    #expect(forecast.hourly.first?.windSpeed == 12.3)
}

@Test func safeSubscriptReturnsNilForOutOfBounds() {
    let array = [1, 2, 3]
    #expect(array[safe: 0] == 1)
    #expect(array[safe: 2] == 3)
    #expect(array[safe: 3] == nil)
    #expect(array[safe: -1] == nil)
}
