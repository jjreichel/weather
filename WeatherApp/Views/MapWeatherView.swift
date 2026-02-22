import SwiftUI
import MapKit

struct WeatherDataPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let color: Color
    let label: String
}

struct MapWeatherView: View {
    @Bindable var weatherVM: WeatherViewModel
    var locationVM: LocationViewModel

    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Map(position: $position) {
                if let loc = locationVM.selectedLocation {
                    Marker(loc.name, coordinate: loc.coordinate)
                }
                ForEach(dataPoints) { point in
                    Annotation("", coordinate: point.coordinate) {
                        ZStack {
                            Circle()
                                .fill(point.color.opacity(0.75))
                                .frame(width: 44, height: 44)
                            Text(point.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }

            LayerPickerView(selectedLayer: $weatherVM.selectedLayer)
                .padding()
        }
        .onChange(of: locationVM.selectedLocation) { _, loc in
            guard let loc else { return }
            withAnimation {
                position = .region(MKCoordinateRegion(
                    center: loc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 3, longitudeDelta: 3)
                ))
            }
        }
    }

    // In v1: ein Datenpunkt am gewählten Ort für die aktuelle Stunde
    var dataPoints: [WeatherDataPoint] {
        guard let forecast = weatherVM.currentForecast,
              let entry = forecast.hourly.first else { return [] }

        let (value, label): (Double?, String) = {
            switch weatherVM.selectedLayer {
            case .temperature:
                let v = entry.temperature
                return (v, v.map { "\(Int($0.rounded()))°C" } ?? "—")
            case .precipitation:
                let v = entry.precipitation
                return (v, v.map { "\(String(format: "%.1f", $0)) mm" } ?? "—")
            case .wind:
                let v = entry.windSpeed
                return (v, v.map { "\(Int($0.rounded())) km/h" } ?? "—")
            case .cloudCover:
                let v = entry.cloudCover
                return (v, v.map { "\(Int($0.rounded()))%" } ?? "—")
            case .wave, .cape:
                return (nil, "—")
            }
        }()

        return [WeatherDataPoint(
            coordinate: forecast.location.coordinate,
            color: colorFor(value: value, layer: weatherVM.selectedLayer),
            label: label
        )]
    }

    func colorFor(value: Double?, layer: WeatherLayer) -> Color {
        guard let v = value else { return .gray }
        switch layer {
        case .temperature:
            switch v {
            case ..<0:    return .blue
            case 0..<10:  return .cyan
            case 10..<20: return .green
            case 20..<30: return .orange
            default:      return .red
            }
        case .precipitation:
            return v < 0.1 ? .gray : v < 2 ? .blue : .indigo
        case .wind:
            return v < 20 ? .green : v < 50 ? .yellow : .red
        case .cloudCover:
            return v < 25 ? .yellow : v < 75 ? .gray : .init(white: 0.35)
        case .wave:
            return v < 1 ? .cyan : v < 3 ? .blue : .indigo
        case .cape:
            return v < 500 ? .green : v < 1500 ? .yellow : .red
        }
    }
}

struct LayerPickerView: View {
    @Binding var selectedLayer: WeatherLayer

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            ForEach(WeatherLayer.allCases) { layer in
                Button(layer.displayName) {
                    selectedLayer = layer
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedLayer == layer ? Color.accentColor : .secondary.opacity(0.6))
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
