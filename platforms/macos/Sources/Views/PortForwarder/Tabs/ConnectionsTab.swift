import SwiftUI

struct ConnectionsTab: View {
    @Environment(AppState.self) private var appState
    @Binding var discoveryManager: KubernetesDiscoveryManager?
    @State private var selectedConnectionId: UUID?

    private var selectedConnection: PortForwardConnectionState? {
        guard let id = selectedConnectionId else { return nil }
        return appState.portForwardManager.connections.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            // Left: Connection list
            VStack(spacing: 0) {
                // Header with action buttons
                HStack {
                    Text(L("k8s.connections"))
                        .font(.headline)

                    Spacer()

                    Button {
                        let config = PortForwardConnectionConfig(
                            name: L("k8s.newConnection"),
                            namespace: "default",
                            service: "service-name",
                            localPort: 8080,
                            remotePort: 80
                        )
                        appState.portForwardManager.addConnection(config)
                    } label: {
                        Label(L("common.add"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.bordered)
                    .help(L("k8s.addConnection"))

                    Button {
                        let dm = KubernetesDiscoveryManager(processManager: appState.portForwardManager.processManager)
                        Task { await dm.loadNamespaces() }
                        discoveryManager = dm
                    } label: {
                        Label(L("k8s.import"), systemImage: "square.and.arrow.down.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!DependencyChecker.shared.allRequiredInstalled)
                    .help(L("k8s.importFromKubernetes"))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Divider()

                // Dependency warning
                if !DependencyChecker.shared.allRequiredInstalled {
                    DependencyWarningBanner()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.portForwardManager.connections) { connection in
                            PortForwardConnectionCard(
                                connection: connection,
                                isSelected: selectedConnectionId == connection.id,
                                onSelect: { selectedConnectionId = connection.id }
                            )
                        }
                    }
                    .padding(16)
                }

                Divider()

                // Status bar
                HStack {
                    let manager = appState.portForwardManager
                    if manager.connections.isEmpty {
                        Text(L("k8s.noConnections"))
                    } else {
                        Text(L("k8s.connectedCount", manager.connectedCount, manager.connections.count))
                    }

                    Spacer()

                    if manager.isKillingProcesses {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(L("k8s.killing"))
                            .foregroundStyle(.secondary)
                    } else if !manager.connections.isEmpty {
                        Button(L("k8s.killAllStuck")) {
                            Task { await manager.killStuckProcesses() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(L("k8s.startAll")) {
                            manager.startAll()
                        }
                        .buttonStyle(.bordered)
                        .disabled(manager.allConnected)

                        Button(L("k8s.stopAll")) {
                            manager.stopAll()
                        }
                        .buttonStyle(.bordered)
                        .disabled(manager.connectedCount == 0)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            .frame(minWidth: 400)

            // Right: Log viewer
            ConnectionLogPanel(connection: selectedConnection)
                .frame(minWidth: 450)
        }
    }
}
