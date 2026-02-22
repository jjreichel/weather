import Testing
@testable import WeatherApp
import Foundation

private func makeTestGrid() -> WeatherGrid {
    let region = GridRegion(latMin: 47.0, latMax: 48.0, lonMin: 8.0, lonMax: 9.0, nx: 2, ny: 2)
    let t0 = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!
    let t1 = ISO8601DateFormatter().date(from: "2024-01-01T01:00:00Z")!
    let values: [[Double?]] = [
        [5.0, 6.0, 7.0, 8.0],
        [5.5, 6.5, 7.5, 8.5],
    ]
    return WeatherGrid(
        region: region, model: .icon,
        times: [t0, t1],
        data: [.temperature: values],
        windDirection: [Array(repeating: nil, count: 4), Array(repeating: nil, count: 4)]
    )
}

@Test func gribWriterProducesGRIBMagicBytes() throws {
    let grid = makeTestGrid()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.grib2")
    try GribWriter.write(grid: grid, to: url)
    let data = try Data(contentsOf: url)
    #expect(data.count > 0)
    #expect(data[0] == 0x47) // 'G'
    #expect(data[1] == 0x52) // 'R'
    #expect(data[2] == 0x49) // 'I'
    #expect(data[3] == 0x42) // 'B'
}

@Test func gribWriterEdition2() throws {
    let grid = makeTestGrid()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_ed.grib2")
    try GribWriter.write(grid: grid, to: url)
    let data = try Data(contentsOf: url)
    #expect(data[7] == 0x02)
}

@Test func gribWriterEndsWithTerminator() throws {
    let grid = makeTestGrid()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_end.grib2")
    try GribWriter.write(grid: grid, to: url)
    let data = try Data(contentsOf: url)
    let last4 = data.suffix(4)
    #expect(Array(last4) == [0x37, 0x37, 0x37, 0x37])
}

@Test func gribWriterSection3HasCorrectSectionNumber() throws {
    let grid = makeTestGrid()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_s3.grib2")
    try GribWriter.write(grid: grid, to: url)
    let data = try Data(contentsOf: url)
    // Section 3 beginnt bei Offset 16 (Sec0) + 21 (Sec1) = 37
    let sec3Start = 37
    #expect(data[sec3Start + 4] == 0x03)
}

@Test func gribWriterSection5HasNBits16() throws {
    let grid = makeTestGrid()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_s5.grib2")
    try GribWriter.write(grid: grid, to: url)
    let data = try Data(contentsOf: url)
    // Sec5 beginnt bei 37+72 (Sec3) + 34 (Sec4) = 143
    let sec5Start = 37 + 72 + 34
    #expect(data[sec5Start + 4] == 0x05)
    #expect(data[sec5Start + 20] == 16)
}

@Test func gribWriterMessageLengthConsistency() throws {
    let grid = makeTestGrid()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_len.grib2")
    try GribWriter.write(grid: grid, to: url)
    let data = try Data(contentsOf: url)
    let totalLen = (0..<8).reduce(UInt64(0)) { acc, i in
        (acc << 8) | UInt64(data[8 + i])
    }
    #expect(totalLen >= 179)
}
