import Testing
@testable import WeatherApp

@Test func windSpeedUnitConvertsKmhToKnots() {
    let unit = WindSpeedUnit.knots
    #expect(abs(unit.chartValue(kmh: 18.52) - 10.0) < 0.1)
    #expect(unit.format(kmh: 18.52) == "10 kn")
}

@Test func windSpeedUnitBeaufort() {
    let unit = WindSpeedUnit.beaufort
    #expect(unit.beaufort(kmh: 0) == 0)
    #expect(unit.beaufort(kmh: 50) >= 6)
    #expect(unit.format(kmh: 50) == "Bft \(unit.beaufort(kmh: 50))")
}

@Test func windLegendStopsUseSelectedUnit() {
    let stops = WeatherLayer.wind.legendStops(windSpeedUnit: .beaufort)
    #expect(stops[1].label == "5")  // ~30 km/h ≈ Bft 5
}
