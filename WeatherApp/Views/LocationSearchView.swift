import SwiftUI

struct LocationSearchView: View {
    @Bindable var locationVM: LocationViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ort wählen")
                    .font(.headline)
                Spacer()
                Button("Fertig") { dismiss() }
                    .keyboardShortcut(.return)
            }
            .padding()

            Divider()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Stadt oder Ort suchen…", text: $locationVM.searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: locationVM.searchText) { _, query in
                        Task { await locationVM.search(query: query) }
                    }
                if locationVM.isSearching {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(10)
            .background(.background.secondary)

            Divider()

            List {
                if let current = locationVM.currentLocation {
                    Section {
                        LocationRow(
                            location: current,
                            isSelected: locationVM.selectedLocation?.id == current.id
                        ) {
                            locationVM.selectedLocation = current
                            dismiss()
                        }
                    } header: {
                        Label("Aktueller Standort", systemImage: "location.fill")
                    }
                }

                if !locationVM.searchResults.isEmpty {
                    Section("Suchergebnisse") {
                        ForEach(locationVM.searchResults) { loc in
                            LocationRow(location: loc, isSelected: false) {
                                locationVM.selectedLocation = loc
                                locationVM.addFavorite(loc)
                                dismiss()
                            }
                        }
                    }
                } else if locationVM.searchText.isEmpty && !locationVM.favorites.isEmpty {
                    Section("Favoriten") {
                        ForEach(locationVM.favorites) { loc in
                            LocationRow(
                                location: loc,
                                isSelected: locationVM.selectedLocation?.id == loc.id
                            ) {
                                locationVM.selectedLocation = loc
                                dismiss()
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    locationVM.removeFavorite(loc)
                                } label: {
                                    Label("Entfernen", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 380, minHeight: 520)
    }
}

struct LocationRow: View {
    let location: Location
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(location.name)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
