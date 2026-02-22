import SwiftUI
import MapKit
import AppKit
import UniformTypeIdentifiers

// UTI für GRIB2 (nur definieren wenn noch nicht vorhanden)
private extension UTType {
    static let grib2 = UTType(filenameExtension: "grib2") ?? .data
}

struct MapWeatherView: View {
    @Bindable var weatherVM: WeatherViewModel
    var locationVM: LocationViewModel

    var body: some View {
        ZStack(alignment: .bottom) {
            // Karte mit Overlay-Rendering via MKMapView
            GribMapKitView(weatherVM: weatherVM, locationVM: locationVM)
                .ignoresSafeArea()

            // Zeitslider am unteren Rand
            if let grid = weatherVM.currentGrid, grid.times.count > 1 {
                TimeSliderView(times: grid.times,
                               selectedIndex: $weatherVM.selectedHourIndex)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(10)
            }
        }
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                LayerPickerView(selectedLayer: $weatherVM.selectedLayer)
                if weatherVM.isLoadingGrid {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    downloadGrib()
                } label: {
                    Label("Als GRIB2 speichern…", systemImage: "arrow.down.doc")
                }
                .disabled(weatherVM.currentGrid == nil)
            }
        }
    }

    private func downloadGrib() {
        guard let grid = weatherVM.currentGrid else { return }
        let panel = NSSavePanel()
        panel.title = "GRIB2-Raster speichern"
        panel.allowedContentTypes = [.grib2]
        panel.nameFieldStringValue = "Wettermodell-\(grid.model.displayName).grib2"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? GribWriter.write(grid: grid, to: url)
        }
    }
}

// MARK: - TimeSliderView

struct TimeSliderView: View {
    let times: [Date]
    @Binding var selectedIndex: Int

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E dd. MMM HH:mm"
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    var body: some View {
        guard !times.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(VStack(spacing: 2) {
            Text(TimeSliderView.fmt.string(from: times[selectedIndex]) + " UTC")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Slider(value: Binding(
                get: { Double(selectedIndex) },
                set: { selectedIndex = Int($0.rounded()) }
            ), in: 0...Double(times.count - 1), step: 1)
        })
    }
}

// MARK: - LayerPickerView

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
