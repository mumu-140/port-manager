import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    @State private var showAddFavoritePopover = false
    @State private var showAddWatchPopover = false

    var body: some View {
        @Bindable var state = appState

        List(selection: $state.selectedSidebarItem) {
            Section(L("ports.section.categories")) {
                sidebarRow(.allPorts, count: appState.ports.count)

                // Favorites row with add button
                favoritesRow

                // Watched row with add button
                watchedRow
            }

            Section(L("ports.section.networking")) {
                kubernetesPortForwardRow
                cloudflareTunnelsRow
                managedServicesRow
            }

            Section(L("ports.section.processTypes")) {
                ForEach(ProcessType.allCases) { type in
                    sidebarRow(.processType(type), count: countForType(type))
                }
            }

            Section(L("ports.section.filters")) {
                filterControls
            }

            Section {
                Label {
                    Text(L("sponsor.title"))
                } icon: {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.pink)
                }
                .tag(SidebarItem.sponsors)

                Label(L("common.settings"), systemImage: "gear")
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Favorites Row

    private var favoritesRow: some View {
        Label {
            HStack {
                Text(L("ports.favorites"))
                Spacer()

                Button {
                    showAddFavoritePopover = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L("ports.addFavoriteHelp"))
                .popover(isPresented: $showAddFavoritePopover) {
                    AddPortPopover(mode: .favorite) { port, _, _ in
                        appState.favorites.insert(port)
                    }
                }

                Text("\(favoritesCount)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(minWidth: 20)
            }
        } icon: {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
        }
        .tag(SidebarItem.favorites)
        .contextMenu {
            Button {
                showAddFavoritePopover = true
            } label: {
                Label(L("ports.addPort"), systemImage: "plus")
            }
        }
    }

    // MARK: - Watched Row

    private var watchedRow: some View {
        Label {
            HStack {
                Text(L("ports.watched"))
                Spacer()

                Button {
                    showAddWatchPopover = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L("ports.addWatchedHelp"))
                .popover(isPresented: $showAddWatchPopover) {
                    AddPortPopover(mode: .watch) { port, onStart, onStop in
                        appState.watchedPorts.append(
                            WatchedPort(port: port, notifyOnStart: onStart, notifyOnStop: onStop)
                        )
                    }
                }

                Text("\(watchedCount)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(minWidth: 20)
            }
        } icon: {
            Image(systemName: "eye.fill")
                .foregroundStyle(.blue)
        }
        .tag(SidebarItem.watched)
        .contextMenu {
            Button {
                showAddWatchPopover = true
            } label: {
                Label(L("ports.addPort"), systemImage: "plus")
            }
        }
    }

    // MARK: - Kubernetes Port Forward Row

    private var kubernetesPortForwardRow: some View {
        Label {
            HStack {
                Text(L("ports.k8sPortForward"))
                Spacer()

                // Status indicator
                StatusDot(color: appState.portForwardManager.allConnected && !appState.portForwardManager.connections.isEmpty ? Theme.Colors.statusSuccess : Theme.Colors.statusIdle)

                Text("\(appState.portForwardManager.connections.count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(minWidth: 20)
            }
        } icon: {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(.blue)
        }
        .tag(SidebarItem.kubernetesPortForward)
    }

    // MARK: - Cloudflare Tunnels Row

    private var cloudflareTunnelsRow: some View {
        Label {
            HStack {
                Text(L("tunnel.title"))
                Spacer()

                let activeCount = appState.tunnelManager.activeTunnelCount + appState.namedTunnelManager.runningCount
                if activeCount > 0 {
                    StatusDot(color: Theme.Colors.statusSuccess)
                }

                let totalCount = appState.tunnelManager.tunnels.count + appState.namedTunnelManager.tunnels.count
                Text("\(totalCount)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(minWidth: 20)
            }
        } icon: {
            Image(systemName: "cloud.fill")
                .foregroundStyle(.orange)
        }
        .tag(SidebarItem.cloudflareTunnels)
    }

    // MARK: - Local Services Row

    private var managedServicesRow: some View {
        Label {
            HStack {
                Text(L("service.title"))
                Spacer()

                let conflictCount = appState.managedServiceManager.services
                    .filter { $0.status == .conflict }
                    .count
                if conflictCount > 0 {
                    StatusDot(color: .orange)
                } else if appState.managedServiceManager.runningCount > 0 {
                    StatusDot(color: Theme.Colors.statusSuccess)
                }

                Text("\(appState.managedServiceManager.services.count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(minWidth: 20)
            }
        } icon: {
            Image(systemName: "server.rack")
                .foregroundStyle(.green)
        }
        .tag(SidebarItem.managedServices)
    }

    // MARK: - Standard Row

    private func sidebarRow(_ item: SidebarItem, count: Int) -> some View {
        Label {
            HStack {
                Text(item.title)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } icon: {
            Image(systemName: item.icon)
        }
        .tag(item)
    }

    // MARK: - Filter Controls

    @ViewBuilder
    private var filterControls: some View {
        @Bindable var state = appState

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("ports.portRange"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField(L("ports.min"), value: $state.filter.minPort, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                    Text("-")
                        .foregroundStyle(.secondary)
                    TextField(L("ports.max"), value: $state.filter.maxPort, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                }
            }

            if appState.filter.isActive {
                Button(L("ports.resetFilters")) {
                    appState.filter.reset()
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var favoritesCount: Int {
        appState.favorites.count
    }

    private var watchedCount: Int {
        appState.watchedPorts.count
    }

    private func countForType(_ type: ProcessType) -> Int {
        appState.ports.filter { $0.processType == type }.count
    }
}
