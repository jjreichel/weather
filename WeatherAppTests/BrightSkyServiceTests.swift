import Testing
@testable import WeatherApp
import Foundation

@Test func decodeBrightSkyCurrentWeather() throws {
    let json = """
    {
      "weather": {
        "timestamp": "2024-01-01T12:00:00+00:00",
        "temperature": 8.3,
        "precipitation_10": 0.0,
        "wind_speed_10": 15.2,
        "wind_direction_10": 225,
        "cloud_cover": 50,
        "condition": "dry",
        "icon": "partly-cloudy-day"
      },
      "sources": [
        { "station_name": "Berlin-Tempelhof" }
      ]
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(BrightSkyCurrentResponse.self, from: json)
    #expect(response.weather.temperature == 8.3)
    #expect(response.weather.windSpeed10 == 15.2)
    #expect(response.weather.windDirection10 == 225)
    #expect(response.weather.cloudCover == 50)
    #expect(response.weather.condition == "dry")
    #expect(response.sources.first?.stationName == "Berlin-Tempelhof")
}

@Test func brightSkyToObservationConversion() throws {
    let json = """
    {
      "weather": {
        "timestamp": "2024-01-01T12:00:00+00:00",
        "temperature": 8.3,
        "precipitation_10": 0.5,
        "wind_speed_10": 15.2,
        "wind_direction_10": 225,
        "cloud_cover": 50,
        "condition": "dry",
        "icon": "partly-cloudy-day"
      },
      "sources": [
        { "station_name": "Berlin-Tempelhof" }
      ]
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(BrightSkyCurrentResponse.self, from: json)
    let obs = response.weather.toObservation(stationName: "Berlin-Tempelhof")

    #expect(obs.stationName == "Berlin-Tempelhof")
    #expect(obs.temperature == 8.3)
    #expect(obs.windSpeed == 15.2)
    #expect(obs.windDirection == 225.0)
    #expect(obs.cloudCover == 50.0)
    #expect(obs.precipitation == 0.5)
    #expect(obs.condition == "dry")
    #expect(obs.icon == "partly-cloudy-day")
}
