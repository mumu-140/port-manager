import SwiftUI

struct MainWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(SponsorManager.self) private var sponsorManager
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var showKillAllConfirmation = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } content: {
            searchableContent
                .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: .infinity)
        } detail: {
            detailView
                .navigationSplitViewColumnWidth(min: 400, ideal: 500, max: 600)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            toolbarContent
        }
        .onAppear {
            // Ensure app is properly activated for keyboard input
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .confirmationDialog(
            L("ports.killAllTitle"),
            isPresented: $showKillAllConfirmation
        ) {
            Button(L("ports.killAllCount", appState.filteredPorts.count), role: .destructive) {
                Task {
                    await appState.killAll()
                }
            }
            Button(L("common.cancel"), role: .cancel) {}
        } message: {
            Text(L("ports.killAllConfirm", appState.filteredPorts.count))
        }
        .onKeyPress(.delete) {
            if let port = appState.selectedPort {
                Task {
                    await appState.killPort(port)
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.deleteForward) {
            if let port = appState.selectedPort {
                Task {
                    await appState.killPort(port)
                }
                return .handled
            }
            return .ignored
        }
    }

    /// Search is scoped to the active section. Port pages share the port
    /// filter, the Service Manager keeps its own query, and sections without a
    /// search field get no binding at all, so they can never write into the
    /// port search state (design notes, section 16.9).
    @ViewBuilder
    private var searchableContent: some View {
        if appState.selectedSidebarItem == .managedServices {
            contentView.searchable(
                text: serviceSearchBinding,
                prompt: L("service.searchPlaceholder")
            )
        } else if usesPortSearch {
            contentView.searchable(
                text: portSearchBinding,
                prompt: L("ports.searchPlaceholder")
            )
        } else {
            contentView
        }
    }

    /// Sidebar sections that filter the port list with the port search query.
    private var usesPortSearch: Bool {
        switch appState.selectedSidebarItem {
        case .allPorts, .favorites, .watched, .processType:
            return true
        case .kubernetesPortForward, .cloudflareTunnels, .managedServices, .sponsors, .settings:
            return false
        }
    }

    private var portSearchBinding: Binding<String> {
        Binding(
            get: { appState.filter.searchText },
            set: { appState.filter.searchText = $0 }
        )
    }

    private var serviceSearchBinding: Binding<String> {
        Binding(
            get: { appState.managedServiceManager.searchText },
            set: { appState.managedServiceManager.searchText = $0 }
        )
    }

    @ViewBuilder
    private var contentView: some View {
        switch appState.selectedSidebarItem {
        case .settings:
            SettingsView(state: appState, updateManager: appState.updateManager)
                .id("settings")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationSplitViewColumnWidth(min: 400, ideal: 600, max: .infinity)
        case .sponsors:
            SponsorsPageView(sponsorManager: sponsorManager)
                .id("sponsors")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationSplitViewColumnWidth(min: 400, ideal: 600, max: .infinity)
        case .kubernetesPortForward:
            PortForwarderSidebarContent()
                .id("port-forwarder")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationSplitViewColumnWidth(min: 400, ideal: 600, max: .infinity)
        case .cloudflareTunnels:
            CloudflareTunnelsView()
                .id("cloudflare-tunnels")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationSplitViewColumnWidth(min: 400, ideal: 600, max: .infinity)
        case .managedServices:
            ManagedServicesListView()
                .id("managed-services")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationSplitViewColumnWidth(min: 300, ideal: 400, max: .infinity)
        default:
            VStack(spacing: 0) {
                PortTableView()

                // Status bar
                statusBar
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        if appState.selectedSidebarItem == .settings || appState.selectedSidebarItem == .sponsors {
            EmptyView()
        } else if appState.selectedSidebarItem == .kubernetesPortForward {
            ConnectionLogPanel(connection: appState.selectedPortForwardConnection)
        } else if appState.selectedSidebarItem == .managedServices {
            ManagedServiceDetailView()
        } else if appState.selectedSidebarItem == .cloudflareTunnels {
            if let tunnel = appState.selectedNamedTunnel {
                NamedTunnelDetailView(tunnel: tunnel)
            } else {
                ContentUnavailableView {
                    Label(L("tunnel.noSelectionTitle"), systemImage: "cloud")
                } description: {
                    Text(L("tunnel.noSelectionDetail"))
                }
            }
        } else if let selectedPort = appState.selectedPort {
            PortDetailView(port: selectedPort)
        } else {
            ContentUnavailableView {
                Label(L("ports.noSelectionTitle"), systemImage: "network.slash")
            } description: {
                Text(L("ports.noSelectionDetail"))
            }
        }
    }

    private var statusBar: some View {
        HStack {
            // Port count
            Group {
                if appState.filter.isActive || appState.selectedSidebarItem != .allPorts {
                    Text(L("ports.filteredCount", appState.filteredPorts.count, appState.ports.count))
                } else {
                    Text(L("ports.listeningCount", appState.ports.count))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()

            // Scanning indicator
            if appState.isScanning {
                ProgressView()
                    .controlSize(.small)
                Text(L("ports.scanning"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task {
                    await appState.refresh()
                }
            } label: {
                Label(L("common.refresh"), systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(appState.isScanning)
            .help(L("ports.refreshHelp"))

            Button {
                appState.selectedSidebarItem = .settings
            } label: {
                Label(L("common.settings"), systemImage: "gear")
            }
            .keyboardShortcut(",", modifiers: .command)
            .help(L("common.settingsHelp"))
        }
    }
}
