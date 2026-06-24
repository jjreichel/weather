import AppKit
import UniformTypeIdentifiers

private extension UTType {
    static let grib2 = UTType(filenameExtension: "grib2") ?? .data
}

/// Speicherdialog für GRIB2-Export.
enum GribDownloadPresenter {
    @MainActor
    static func presentSavePanel(weatherVM: WeatherViewModel) {
        let panel = NSSavePanel()
        panel.title = "GRIB2-Raster speichern"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.grib2]
        panel.nameFieldStringValue = "Wettermodell-\(weatherVM.selectedModel.displayName).grib2"

        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            weatherVM.startGridExport(to: url)
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible) {
            panel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            handleResponse(panel.runModal())
        }
    }
}
