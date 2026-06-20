import SwiftUI

/// Wetterwerte am angeklickten Kartenpunkt.
struct GridPointDetailView: View {
    let grid: WeatherGrid
    let inspection: GridInspection
    let hourIndex: Int
    var windSpeedUnit: WindSpeedUnit = .kmh
    var onClose: () -> Void

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E dd. MMM HH:mm"
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rasterpunkt")
                        .font(.caption.weight(.semibold))
                    Text(String(format: "%.2f° N, %.2f° E",
                                inspection.latitude, inspection.longitude))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if let time = grid.times[safe: hourIndex] {
                        Text(Self.timeFormatter.string(from: time) + " UTC · \(grid.model.displayName)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { onClose() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            ForEach(WeatherLayer.allCases) { layer in
                if let value = grid.value(at: inspection.ix, iy: inspection.iy,
                                          layer: layer, hourIndex: hourIndex) {
                    HStack {
                        Text(layer.displayName)
                            .font(.caption)
                        Spacer()
                        if layer == .wind,
                           let dir = grid.windDirection(at: inspection.ix, iy: inspection.iy,
                                                        hourIndex: hourIndex) {
                            Text("\(layer.format(value, windSpeedUnit: windSpeedUnit)) · \(Int(dir))°")
                                .font(.caption.monospacedDigit())
                        } else {
                            Text(layer.format(value, windSpeedUnit: windSpeedUnit))
                                .font(.caption.monospacedDigit())
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
