import SwiftUI

struct PortForwarderStatusBar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            // Connection count
            let manager = appState.portForwardManager
            if manager.connections.isEmpty {
                Text(L("k8s.noConnections"))
            } else {
                Text(L("k8s.connectedCount", manager.connectedCount, manager.connections.count))
            }

            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
