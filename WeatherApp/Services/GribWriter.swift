import Foundation

/// Schreibt ein `WeatherGrid` als vollständige WMO GRIB2-Datei (Edition 2).
/// Format: Simple Packing (Data Representation Template 5.0), 16 Bit pro Wert.
/// Sections: 0 (Indicator) · 1 (Identification) · 3 (Grid Def) · 4 (Product Def) ·
///           5 (Data Repr) · 6 (Bit-Map) · 7 (Data) · 8 (End "7777")
enum GribWriter {

    // MARK: - Öffentliche API

    static func write(grid: WeatherGrid, to url: URL) throws {
        var output = Data()
        let refDate = grid.times.first ?? Date()

        // Variablen-Tabelle: (layer, Disziplin, Kategorie, Parameter, Oberflächentyp, Level)
        let layerSpecs: [(WeatherLayer, UInt8, UInt8, UInt8, UInt8, UInt32)] = [
            (.temperature,   0,  0, 0, 103,  2),  // 2m Temperatur
            (.wind,          0,  2, 1, 103, 10),  // 10m Windgeschwindigkeit
            (.precipitation, 0,  1, 8,   1,  0),  // Niederschlag, Oberfläche
            (.cape,          0,  7, 6,   1,  0),  // CAPE, Oberfläche
            (.cloudCover,    0,  6, 1,   1,  0),  // Bedeckungsgrad
            (.wave,         10,  0, 3,   1,  0),  // Signifikante Wellenhöhe (Ozean)
        ]

        for (layer, disc, cat, param, surf, level) in layerSpecs {
            guard let hourly = grid.data[layer] else { continue }
            for (hi, values) in hourly.enumerated() {
                output.append(buildMessage(
                    values: values, grid: grid,
                    discipline: disc, category: cat, parameter: param,
                    surfaceType: surf, level: level,
                    forecastHour: UInt32(hi), refDate: refDate
                ))
            }
        }

        // Windrichtung als eigene Messages (Disziplin 0, Kat 2, Param 0 = Windrichtung)
        for (hi, values) in grid.windDirection.enumerated() {
            output.append(buildMessage(
                values: values, grid: grid,
                discipline: 0, category: 2, parameter: 0,
                surfaceType: 103, level: 10,
                forecastHour: UInt32(hi), refDate: refDate
            ))
        }

        try output.write(to: url)
    }

    // MARK: - Message-Builder

    private static func buildMessage(
        values: [Double?], grid: WeatherGrid,
        discipline: UInt8, category: UInt8, parameter: UInt8,
        surfaceType: UInt8, level: UInt32,
        forecastHour: UInt32, refDate: Date
    ) -> Data {
        let nx = grid.region.nx
        let ny = grid.region.ny
        let n  = nx * ny

        // Bitmap und Float-Array aufbauen
        var bitmap  = Data(count: (n + 7) / 8)
        var floats  = [Float](repeating: 0, count: n)
        var present = [Int]()

        for i in 0..<n {
            if let v = values[safe: i].flatMap({ $0 }) {
                floats[i] = Float(v)
                bitmap[i / 8] |= (0x80 >> UInt8(i % 8))
                present.append(i)
            }
        }
        let hasMissing = present.count < n

        // Simple Packing: Referenzwert + Binärskala
        let presentFloats = present.map { floats[$0] }
        let refMin: Float = presentFloats.min() ?? 0
        let refMax: Float = presentFloats.max() ?? 0
        let range = refMax - refMin

        let E: Int16 = range > 0
            ? Int16(max(0, Int(ceil(log2(Double(range) / 65535.0)))))
            : 0
        let scaleDivisor = max(Float(pow(2.0, Double(E))), Float.leastNormalMagnitude)

        var packed = Data()
        for i in 0..<n {
            let bitSet = bitmap[i / 8] & (0x80 >> UInt8(i % 8)) != 0
            guard bitSet else { continue }
            let raw = UInt16(max(0, min(65535, Int(((floats[i] - refMin) / scaleDivisor).rounded()))))
            packed.append(UInt8(raw >> 8))
            packed.append(UInt8(raw & 0xFF))
        }

        let sec6Len = hasMissing ? 6 + (n + 7) / 8 : 6
        let sec7Len = 5 + packed.count
        let totalLen = 16 + 21 + 72 + 34 + 21 + sec6Len + sec7Len + 4

        var msg = Data()
        msg.append(contentsOf: sec0(discipline: discipline, totalLen: totalLen))
        msg.append(contentsOf: sec1(refDate: refDate))
        msg.append(contentsOf: sec3(region: grid.region))
        msg.append(contentsOf: sec4(category: category, parameter: parameter,
                                     surfaceType: surfaceType, level: level,
                                     forecastHour: forecastHour))
        msg.append(contentsOf: sec5(refMin: refMin, binaryScale: E,
                                     presentCount: UInt32(present.count)))
        msg.append(contentsOf: sec6(bitmap: bitmap, hasMissing: hasMissing, n: n))
        msg.append(contentsOf: sec7(packed: packed))
        msg.append(contentsOf: [0x37, 0x37, 0x37, 0x37]) // "7777"
        return msg
    }

    // MARK: - Section 0: Indicator (16 Bytes)

    private static func sec0(discipline: UInt8, totalLen: Int) -> [UInt8] {
        var s = [UInt8]("GRIB".utf8)
        s += [0x00, 0x00]        // Reserved
        s.append(discipline)
        s.append(0x02)           // GRIB Edition 2
        let len = UInt64(totalLen)
        s += stride(from: 56, through: 0, by: -8).map { UInt8((len >> $0) & 0xFF) }
        return s  // 16 Bytes
    }

    // MARK: - Section 1: Identification (21 Bytes)

    private static func sec1(refDate: Date) -> [UInt8] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let dc = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: refDate)
        let y  = UInt16(dc.year ?? 2024)
        var s = u32be(21)
        s.append(0x01)           // Section number
        s += [0x00, 0xFF]        // Originating centre (255 = missing)
        s += [0x00, 0x00]        // Sub-centre
        s += [0x02, 0x00]        // Master/Local tables version
        s.append(0x01)           // Significance of ref time: Start of forecast
        s += [UInt8(y >> 8), UInt8(y & 0xFF)]
        s += [dc.month, dc.day, dc.hour, dc.minute, dc.second].map { UInt8($0 ?? 0) }
        s += [0x00, 0x01]        // Production status: Operational, Type: Forecast
        return s  // 21 Bytes
    }

    // MARK: - Section 3: Grid Definition Template 3.0 Lat/Lon (72 Bytes)

    private static func sec3(region: GridRegion) -> [UInt8] {
        var s = u32be(72)
        s.append(0x03)
        s.append(0x00)           // Source: code table
        s += u32be(region.nx * region.ny)
        s += [0x00, 0x00]        // No optional list
        s += [0x00, 0x00]        // Template 3.0

        // Template 3.0 (Earth: Sphere R=6371229 m)
        s.append(0x06)           // Shape of Earth
        s.append(0x00); s += u32be(0)  // Scale + radius
        s.append(0x00); s += u32be(0)  // Scale + semi-major
        s.append(0x00); s += u32be(0)  // Scale + semi-minor
        s += u32be(region.nx)
        s += u32be(region.ny)
        s += u32be(0)            // Basic angle
        s += u32be(0xFFFFFFFF)   // Subdivisions (missing)

        s += i32be(Int32(region.latMin * 1_000_000))
        s += u32be(UInt32(bitPattern: Int32(region.lonMin * 1_000_000)))
        s.append(0x30)           // Resolution flags
        s += i32be(Int32(region.latMax * 1_000_000))
        s += u32be(UInt32(bitPattern: Int32(region.lonMax * 1_000_000)))
        s += u32be(UInt32(region.lonStep * 1_000_000))
        s += u32be(UInt32(region.latStep * 1_000_000))
        s.append(0x00)           // Scanning mode: i+, j+, rows
        return s  // 72 Bytes
    }

    // MARK: - Section 4: Product Definition Template 4.0 (34 Bytes)

    private static func sec4(category: UInt8, parameter: UInt8,
                               surfaceType: UInt8, level: UInt32,
                               forecastHour: UInt32) -> [UInt8] {
        var s = u32be(34)
        s.append(0x04)
        s += [0x00, 0x00]        // Coordinate values after template
        s += [0x00, 0x00]        // Template 4.0
        s += [category, parameter]
        s.append(0x02)           // Generating process: Forecast
        s += [0xFF, 0xFF]        // Background/analysis process: missing
        s += [0x00, 0x00, 0x00]  // Hours/minutes cutoff
        s.append(0x01)           // Unit: hour
        s += u32be(forecastHour)
        s.append(surfaceType)
        s.append(0x00)           // Scale factor
        s += u32be(level)
        s.append(0xFF)           // Second surface: missing
        s.append(0x00)
        s += u32be(0)
        return s  // 34 Bytes
    }

    // MARK: - Section 5: Data Representation Template 5.0 (21 Bytes)

    private static func sec5(refMin: Float, binaryScale: Int16, presentCount: UInt32) -> [UInt8] {
        var s = u32be(21)
        s.append(0x05)
        s += u32be(presentCount)
        s += [0x00, 0x00]        // Template 5.0
        let bits = refMin.bitPattern.bigEndian
        s += [UInt8(bits>>24), UInt8((bits>>16)&0xFF), UInt8((bits>>8)&0xFF), UInt8(bits&0xFF)]
        let eRaw = UInt16(bitPattern: binaryScale)
        s += [UInt8(eRaw >> 8), UInt8(eRaw & 0xFF)]
        s += [0x00, 0x00]        // Decimal scale D = 0
        s.append(16)             // Bits per value
        s.append(0x00)           // Type: floating point
        return s  // 21 Bytes
    }

    // MARK: - Section 6: Bit-Map

    private static func sec6(bitmap: Data, hasMissing: Bool, n: Int) -> [UInt8] {
        if hasMissing {
            var s = u32be(UInt32(6 + (n + 7) / 8))
            s.append(0x06)
            s.append(0x00)       // Bitmap vorhanden
            s += [UInt8](bitmap)
            return s
        } else {
            return u32be(6) + [0x06, 0xFF]  // Kein Bitmap
        }
    }

    // MARK: - Section 7: Data

    private static func sec7(packed: Data) -> [UInt8] {
        var s = u32be(UInt32(5 + packed.count))
        s.append(0x07)
        s += [UInt8](packed)
        return s
    }

    // MARK: - Big-Endian Hilfsfunktionen

    private static func u32be(_ v: UInt32) -> [UInt8] {
        [UInt8(v>>24), UInt8((v>>16)&0xFF), UInt8((v>>8)&0xFF), UInt8(v&0xFF)]
    }
    private static func u32be(_ v: Int)   -> [UInt8] { u32be(UInt32(bitPattern: Int32(v))) }
    private static func u32be(_ v: UInt)  -> [UInt8] { u32be(UInt32(v)) }
    private static func i32be(_ v: Int32) -> [UInt8] { u32be(UInt32(bitPattern: v)) }
}
