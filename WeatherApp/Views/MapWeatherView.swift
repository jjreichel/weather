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
            GribMapKitView(weatherVM: weatherVM, locationVM: locationVM)
                .ignoresSafeArea()

            HStack(alignment: .bottom, spacing: 10) {
                LayerLegendView(layer: weatherVM.selectedLayer,
                                windSpeedUnit: weatherVM.windSpeedUnit)

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    if let grid = weatherVM.currentGrid,
                       let inspection = weatherVM.gridInspection {
                        GridPointDetailView(
                            grid: grid,
                            inspection: inspection,
                            hourIndex: weatherVM.selectedHourIndex,
                            windSpeedUnit: weatherVM.windSpeedUnit
                        ) {
                            weatherVM.clearGridInspection()
                        }
                    }

                    if let grid = weatherVM.currentGrid, grid.times.count > 1 {
                        TimeSliderView(times: grid.times,
                                       selectedIndex: $weatherVM.selectedHourIndex)
                            .frame(maxWidth: 360)
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                LayerPickerView(selectedLayer: $weatherVM.selectedLayer)
                if let progress = weatherVM.gridLoadProgress, weatherVM.isLoadingGrid {
                    ProgressOverlayView(
                        title: "Raster laden…",
                        completed: progress.completed,
                        total: progress.total
                    )
                }
                if let err = weatherVM.gridLoadError {
                    Text(err)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 200)
                }
            }
            .padding()
        }
        .overlay {
            if weatherVM.isExportingGrib, let progress = weatherVM.gribExportProgress {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressOverlayView(
                        title: "GRIB2 speichern…",
                        completed: progress.completed,
                        total: progress.total
                    )
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    downloadGrib()
                } label: {
                    Label("Als GRIB2 speichern…", systemImage: "arrow.down.doc")
                }
                .disabled(weatherVM.currentGrid == nil || weatherVM.isExportingGrib)
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
            Task {
                do {
                    try await weatherVM.exportGrib(grid: grid, to: url)
                } catch {
                    NSAlert(error: error).runModal()
                }
            }
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

    private var safeIndex: Int {
        min(max(0, selectedIndex), times.count - 1)
    }

    var body: some View {
        guard !times.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(VStack(spacing: 2) {
            Text(TimeSliderView.fmt.string(from: times[safeIndex]) + " UTC")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Slider(value: Binding(
                get: { Double(safeIndex) },
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
