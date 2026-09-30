import SwiftUI

/// Small colored status indicator with the localized lifecycle label.
struct ManagedServiceStatusBadge: View {
    let status: ManagedServiceStatus

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Self.color(for: status))
                .frame(width: 8, height: 8)
            Text(L(status.localizationKey))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    static func color(for status: ManagedServiceStatus) -> Color {
        switch status {
        case .stopped: return .secondary
        case .starting, .stopping: return .orange
        case .running: return .green
        case .conflict: return .yellow
        case .failed: return .red
        }
    }
}
