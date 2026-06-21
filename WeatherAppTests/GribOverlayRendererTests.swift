import Testing
@testable import WeatherApp

@Test func bilinearSampleInterpolatesBetweenGridPoints() {
    let region = GridRegion(latMin: 50.0, latMax: 52.0, lonMin: 8.0, lonMax: 10.0, nx: 3, ny: 3)
    let values: [Double?] = [
        0, 10, 20,
        30, 40, 50,
        60, 70, 80,
    ]
    let midLon = region.longitude(ix: 1)
    let midLat = region.latitude(iy: 1)
    let sampled = GribOverlayRenderer.bilinearSample(
        values: values,
        region: region,
        lat: midLat,
        lon: midLon
    )
    #expect(sampled != nil)
    #expect(abs(sampled! - 40.0) < 0.01)
}

@Test func bilinearSampleAtCellCenterReturnsExactValue() {
    let region = GridRegion(latMin: 50.0, latMax: 52.0, lonMin: 8.0, lonMax: 10.0, nx: 3, ny: 3)
    let values: [Double?] = Array(repeating: 15.0, count: 9)
    let lat = region.latitude(iy: 0)
    let lon = region.longitude(ix: 2)
    let sampled = GribOverlayRenderer.bilinearSample(
        values: values,
        region: region,
        lat: lat,
        lon: lon
    )
    #expect(sampled == 15.0)
}
