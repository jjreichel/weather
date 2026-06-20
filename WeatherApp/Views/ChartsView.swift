import SwiftUI
import Charts

struct ChartsView: View {
    var weatherVM: WeatherViewModel

    var body: some View {
        Group {
            if weatherVM.isLoading {
                ProgressView("Lade Vorhersage…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if weatherVM.forecasts.isEmpty {
                ContentUnavailableView(
                    "Keine Daten",
                    systemImage: "cloud.slash",
                    description: Text("Kein Ort ausgewählt oder keine Daten verfügbar.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        ChartSection(title: "Temperatur (°C)") {
                            Chart {
                                ForEach(WeatherModel.allCases) { model in
                                    if let forecast = weatherVM.forecasts[model] {
                                        ForEach(forecast.hourly.prefix(48), id: \.time) { entry in
                                            if let temp = entry.temperature {
                                                LineMark(
                                                    x: .value("Zeit", entry.time),
                                                    y: .value("Temperatur", temp)
                                                )
                                                .foregroundStyle(by: .value("Modell", model.displayName))
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(height: 200)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                                    AxisGridLine()
                                    AxisValueLabel(format: .dateTime.weekday(.abbreviated).hour())
                                }
                            }
                        }

                        ChartSection(title: "Niederschlag (mm)") {
                            Chart {
                                ForEach(WeatherModel.allCases) { model in
                                    if let forecast = weatherVM.forecasts[model] {
                                        ForEach(forecast.hourly.prefix(48), id: \.time) { entry in
                                            if let precip = entry.precipitation {
                                                BarMark(
                                                    x: .value("Zeit", entry.time),
                                                    y: .value("mm", precip)
                                                )
                                                .foregroundStyle(by: .value("Modell", model.displayName))
                                                .opacity(0.7)
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(height: 150)
                        }

                        ChartSection(title: "Windgeschwindigkeit (\(weatherVM.windSpeedUnit.displayName))") {
                            Chart {
                                ForEach(WeatherModel.allCases) { model in
                                    if let forecast = weatherVM.forecasts[model] {
                                        ForEach(forecast.hourly.prefix(48), id: \.time) { entry in
                                            if let wind = entry.windSpeed {
                                                LineMark(
                                                    x: .value("Zeit", entry.time),
                                                    y: .value(weatherVM.windSpeedUnit.displayName,
                                                              weatherVM.windSpeedUnit.chartValue(kmh: wind))
                                                )
                                                .foregroundStyle(by: .value("Modell", model.displayName))
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(height: 150)
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

struct ChartSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }
}
