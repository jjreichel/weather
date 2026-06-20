import SwiftUI

/// Farblegende für den aktuell gewählten Wetter-Layer.
struct LayerLegendView: View {
    let layer: WeatherLayer

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(layer.displayName)
                .font(.caption.weight(.semibold))

            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(layer.legendStops.enumerated()), id: \.offset) { index, stop in
                        let next = layer.legendStops[safe: index + 1]
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        layer.swiftUIColor(from: stop.rgb),
                                        layer.swiftUIColor(from: next?.rgb ?? stop.rgb),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width / CGFloat(layer.legendStops.count))
                    }
                }
            }
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            HStack {
                ForEach(layer.legendStops, id: \.value) { stop in
                    Text("\(stop.label) \(layer.unit)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if stop.value != layer.legendStops.last?.value { Spacer() }
                }
            }
        }
        .frame(maxWidth: 280)
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
