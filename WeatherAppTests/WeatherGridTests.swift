import Testing
import MapKit
@testable import WeatherApp

@Test func gridRegionComputesStepAndCoordinates() {
    let region = GridRegion(latMin: 47.0, latMax: 55.0, lonMin: 6.0, lonMax: 15.0, nx: 10, ny: 9)
    #expect(abs(region.lonStep - 1.0) < 0.001)
    #expect(abs(region.latStep - 1.0) < 0.001)
    #expect(region.latitude(iy: 0) == 47.0)
    #expect(region.latitude(iy: 8) == 55.0)
    #expect(region.longitude(ix: 0) == 6.0)
    #expect(region.longitude(ix: 9) == 15.0)
    #expect(region.index(ix: 2, iy: 3) == 3 * 10 + 2)
}

@Test func gridRegionFromMapRegion() {
    let center = CLLocationCoordinate2D(latitude: 51.0, longitude: 10.0)
    let span = MKCoordinateSpan(latitudeDelta: 8.0, longitudeDelta: 9.0)
    let mapRegion = MKCoordinateRegion(center: center, span: span)
    let gridRegion = GridRegion(from: mapRegion)
    #expect(abs(gridRegion.latMin - 47.0) < 0.01)
    #expect(abs(gridRegion.latMax - 55.0) < 0.01)
}

@Test func gridStepForSmallSpan() {
    #expect(GridRegion.step(for: 3.0) == 0.1)
}

@Test func gridStepForHighZoom() {
    #expect(GridRegion.step(for: 0.02) < 0.01)
    #expect(GridRegion.step(for: 0.02) >= 0.002)
}

@Test func gridRegionFromHighZoomMapRegion() {
    let center = CLLocationCoordinate2D(latitude: 51.0, longitude: 10.0)
    let span = MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.04)
    let gridRegion = GridRegion(from: MKCoordinateRegion(center: center, span: span))
    #expect(gridRegion.nx >= 2)
    #expect(gridRegion.ny >= 2)
    #expect(gridRegion.nx * gridRegion.ny <= 300)
    #expect(gridRegion.latMax - gridRegion.latMin >= 0.02)
    #expect(gridRegion.lonMax - gridRegion.lonMin >= 0.02)
}

@Test func gridRegionFromExtremeZoomUsesMinimumSpan() {
    let center = CLLocationCoordinate2D(latitude: 51.0, longitude: 10.0)
    let span = MKCoordinateSpan(latitudeDelta: 0.001, longitudeDelta: 0.001)
    let gridRegion = GridRegion(from: MKCoordinateRegion(center: center, span: span))
    #expect(gridRegion.latMax - gridRegion.latMin >= GridRegion.minimumMapSpan - 0.001)
}

@Test func gridStepForLargeSpan() {
    #expect(GridRegion.step(for: 50.0) == 2.0)
}

@Test func gridRegionFromMapRegionCapsPointCount() {
    let center = CLLocationCoordinate2D(latitude: 51.0, longitude: 10.0)
    let span = MKCoordinateSpan(latitudeDelta: 6.0, longitudeDelta: 6.0)
    let gridRegion = GridRegion(from: MKCoordinateRegion(center: center, span: span))
    #expect(gridRegion.nx * gridRegion.ny <= 300)
    #expect(gridRegion.nx >= 2)
    #expect(gridRegion.ny >= 2)
}

@Test func gridInspectionFindsNearestPoint() {
    let region = GridRegion(latMin: 50.0, latMax: 52.0, lonMin: 9.0, lonMax: 11.0, nx: 5, ny: 5)
    let points: [Double?] = Array(repeating: 10.0, count: 25)
    let grid = WeatherGrid(
        region: region,
        model: .icon,
        times: [Date()],
        data: [.temperature: [points]],
        windDirection: [Array(repeating: 180.0 as Double?, count: 25)]
    )
    let inspection = grid.inspection(at: 51.0, longitude: 10.0)
    #expect(inspection != nil)
    #expect(grid.value(at: inspection!.ix, iy: inspection!.iy, layer: .temperature, hourIndex: 0) == 10.0)
}
