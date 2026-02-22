import Testing
@testable import WeatherApp
import Foundation

private let forecastJSON = """
{
  "hourly": {
    "time": ["2024-01-01T00:00","2024-01-01T01:00"],
    "temperature_2m": [5.0, 6.0],
    "wind_speed_10m": [10.0, 11.0],
    "wind_direction_10m": [180.0, 185.0],
    "precipitation": [0.0, 0.1],
    "cape": [100.0, 200.0],
    "cloud_cover": [50.0, 60.0]
  }
}
""".data(using: .utf8)!

private let marineJSON = """
{
  "hourly": {
    "time": ["2024-01-01T00:00","2024-01-01T01:00"],
    "wave_height": [1.5, 1.8]
  }
}
""".data(using: .utf8)!

@Test func gridFetchServiceDecodesGridPoint() async throws {
    let session = URLSession.mockSession(forecastJSON: forecastJSON, marineJSON: marineJSON)
    let service = GridFetchService(session: session)
    let region = GridRegion(latMin: 54.0, latMax: 55.0, lonMin: 9.0, lonMax: 10.0, nx: 2, ny: 2)
    let grid = try await service.fetchGrid(region: region, model: .icon)
    #expect(grid.times.count == 2)
    #expect(grid.data[.temperature]?.count == 2)        // 2 Stunden
    #expect(grid.data[.temperature]?[0].count == 4)     // 4 Punkte (2×2)
    #expect(grid.data[.temperature]?[0][0] == 5.0)
    #expect(grid.windDirection[0][0] == 180.0)
}
