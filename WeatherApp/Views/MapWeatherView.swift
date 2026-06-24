import SwiftUI
import MapKit

struct MapWeatherView: View {
    @Bindable var weatherVM: WeatherViewModel
    var locationVM: LocationViewModel
    @State private var zoomInTrigger = 0
    @State private var zoomOutTrigger = 0
    @State private var liveMapRegion: MKCoordinateRegion?

    private var isBusy: Bool {
        weatherVM.isLoadingGrid || weatherVM.isExportingGrib
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            GribMapKitView(weatherVM: weatherVM,
                           locationVM: locationVM,
                           zoomInTrigger: zoomInTrigger,
                           zoomOutTrigger: zoomOutTrigger,
                           liveMapRegion: $liveMapRegion)
            .ignoresSafeArea()

            // Steuerung über der MapKit-NSView (sonst werden Klicks verschluckt)
            VStack(alignment: .leading, spacing: 6) {
                MapZoomControls(
                    onZoomIn: { zoomInTrigger += 1 },
                    onZoomOut: { zoomOutTrigger += 1 }
                )
                Button {
                    loadGribForMap()
                } label: {
                    Label("GRIB2 laden", systemImage: "cloud.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)

                if weatherVM.currentGrid != nil {
                    Button {
                        GribDownloadPresenter.presentSavePanel(weatherVM: weatherVM)
                    } label: {
                        Label("GRIB2 speichern…", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                }
            }
            .padding(10)
            .background(.clear)
            .allowsHitTesting(true)

            VStack {
                Spacer()
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
            .allowsHitTesting(true)

            VStack {
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        LayerPickerView(selectedLayer: $weatherVM.selectedLayer)
                            .disabled(weatherVM.currentGrid == nil)
                        if weatherVM.currentGrid == nil && !weatherVM.isLoadingGrid {
                            Text("„GRIB2 laden“ klicken")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let err = weatherVM.gridLoadError {
                            Text(err)
                                .font(.caption2)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 240)
                        }
                    }
                    .padding()
                }
                Spacer()
            }
            .allowsHitTesting(true)
        }
        .overlay {
            if isBusy {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                        .allowsHitTesting(false)
                    VStack(spacing: 12) {
                        if let progress = weatherVM.isLoadingGrid
                            ? weatherVM.gridLoadProgress
                            : weatherVM.gribExportProgress {
                            ProgressOverlayView(
                                title: weatherVM.isLoadingGrid ? "GRIB2 laden…" : "GRIB2 speichern…",
                                completed: progress.completed,
                                total: progress.total
                            )
                        } else {
                            ProgressView(weatherVM.isLoadingGrid ? "GRIB2 laden…" : "GRIB2 speichern…")
                        }
                        Button("Abbrechen") {
                            weatherVM.cancelDownload()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func loadGribForMap() {
        let region = liveMapRegion
            ?? weatherVM.downloadRegion(fallback: locationVM.selectedLocation)
        weatherVM.startGridLoad(for: region)
    }
}

// MARK: - MapZoomControls

struct MapZoomControls: View {
    var onZoomIn: () -> Void
    var onZoomOut: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Button(action: onZoomIn) {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
            }
            .help("Hineinzoomen")
            Button(action: onZoomOut) {
                Image(systemName: "minus")
                    .frame(width: 28, height: 28)
            }
            .help("Herauszoomen")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
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
