import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case map          = "Karte"
    case charts       = "Charts"
    case observations = "Aktuell"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .map:          return "map"
        case .charts:       return "chart.line.uptrend.xyaxis"
        case .observations: return "thermometer.medium"
        }
    }
}

struct ContentView: View {
    @State private var locationVM = LocationViewModel()
    @State private var weatherVM  = WeatherViewModel()
    @State private var selectedItem: SidebarItem = .map
    @State private var showLocationSearch = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                Section("Ansichten") {
                    ForEach(SidebarItem.allCases) { item in
                        Label(item.rawValue, systemImage: item.icon)
                            .tag(item)
                    }
                }
                if !locationVM.favorites.isEmpty {
                    Section("Favoriten") {
                        ForEach(locationVM.favorites) { loc in
                            Button(loc.name) {
                                locationVM.selectedLocation = loc
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(
                                locationVM.selectedLocation?.id == loc.id ? Color.accentColor : .primary
                            )
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            VStack(spacing: 0) {
                if let error = weatherVM.error {
                    ErrorBanner(message: error) {
                        Task {
                            if let loc = locationVM.selectedLocation {
                                await weatherVM.loadAll(for: loc)
                            }
                        }
                    }
                }
                switch selectedItem {
                case .map:
                    MapWeatherView(weatherVM: weatherVM, locationVM: locationVM)
                case .charts:
                    ChartsView(weatherVM: weatherVM)
                case .observations:
                    ObservationsView(weatherVM: weatherVM)
                }
            }
            .navigationTitle(selectedItem.rawValue)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        showLocationSearch = true
                    } label: {
                        Label(locationVM.selectedLocation?.name ?? "Ort wählen", systemImage: "location")
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Picker("Wind", selection: $weatherVM.windSpeedUnit) {
                        ForEach(WindSpeedUnit.allCases) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)

                    Picker("Modell", selection: $weatherVM.selectedModel) {
                        ForEach(WeatherModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
        }
        .sheet(isPresented: $showLocationSearch) {
            LocationSearchView(locationVM: locationVM)
        }
        .task(id: locationVM.selectedLocation?.id) {
            if let loc = locationVM.selectedLocation {
                await weatherVM.loadAll(for: loc)
            }
        }
        .onChange(of: weatherVM.selectedModel) { _, _ in
            weatherVM.reloadGridForCurrentRegion()
        }
    }
}
