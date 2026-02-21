import SwiftUI

struct ObservationsView: View {
    var weatherVM: WeatherViewModel

    var body: some View {
        Group {
            if weatherVM.isLoading {
                ProgressView("Lade Beobachtungen…")
            } else if let obs = weatherVM.observation {
                ObservationDetailView(observation: obs)
            } else {
                ContentUnavailableView(
                    "Keine Beobachtungen",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text("Für den gewählten Ort sind keine DWD-Stationsdaten verfügbar.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ObservationDetailView: View {
    let observation: Observation

    private var timeString: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "de_DE")
        return f.string(from: observation.time)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Station", value: observation.stationName)
                LabeledContent("Messung", value: timeString)
            }
            Section("Messwerte") {
                if let t = observation.temperature {
                    LabeledContent("Temperatur", value: String(format: "%.1f °C", t))
                }
                if let w = observation.windSpeed {
                    LabeledContent("Wind", value: String(format: "%.0f km/h", w))
                }
                if let d = observation.windDirection {
                    LabeledContent("Windrichtung", value: "\(Int(d))°")
                }
                if let p = observation.precipitation {
                    LabeledContent("Niederschlag", value: String(format: "%.1f mm", p))
                }
                if let c = observation.cloudCover {
                    LabeledContent("Bewölkung", value: "\(Int(c)) %")
                }
                if let cond = observation.condition {
                    LabeledContent("Bedingung", value: cond)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
