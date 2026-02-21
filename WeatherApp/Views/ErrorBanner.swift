import SwiftUI

struct ErrorBanner: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .foregroundStyle(.primary)
            Spacer()
            Button("Wiederholen", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding()
        .background(.red.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}
