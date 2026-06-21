import Testing
@testable import WeatherApp

@Test func fetchSmallGridFromOpenMeteo() async throws {
    let service = GridFetchService()
    let region = GridRegion(latMin: 52.4, latMax: 52.6, lonMin: 13.3, lonMax: 13.5, nx: 3, ny: 3)
    let grid = try await service.fetchGrid(region: region, model: .icon)
    #expect(!grid.times.isEmpty)
    #expect(grid.data[.temperature]?.first?.compactMap { $0 }.count ?? 0 > 0)
}
