import SwiftUI

/// Fortschrittsanzeige für längere Operationen (Grid-Laden, GRIB-Export).
struct ProgressOverlayView: View {
    let title: String
    let completed: Int
    let total: Int

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
            ProgressView(value: fraction)
                .frame(width: 180)
            Text("\(completed) / \(total)  (\(Int(fraction * 100)) %)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}
