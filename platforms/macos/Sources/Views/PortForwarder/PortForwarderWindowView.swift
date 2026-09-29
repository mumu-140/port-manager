import SwiftUI
import AppKit

struct PortForwarderWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(Localization.self) private var localization
    @State private var discoveryManager: KubernetesDiscoveryManager?

    var body: some View {
        TabView {
            ConnectionsTab(discoveryManager: $discoveryManager)
                .tabItem {
                    Label(L("portForwarder.tab.connections"), systemImage: "point.3.connected.trianglepath.dotted")
                }

            ServiceBrowserTab()
                .tabItem {
                    Label(L("portForwarder.tab.browse"), systemImage: "magnifyingglass")
                }

            PortForwarderSettingsTab()
                .tabItem {
                    Label(L("portForwarder.tab.settings"), systemImage: "gear")
                }
        }
        .frame(minWidth: 850, idealWidth: 1000, minHeight: 600, idealHeight: 700)
        // Rebuild only the tab content on language change; the sheet below stays
        // attached to this stable view, so an in-progress service browse survives.
        .id(localization.language)
        .sheet(item: $discoveryManager) { dm in
            ServiceBrowserView(
                discoveryManager: dm,
                onServiceSelected: { config in
                    appState.portForwardManager.addConnection(config)
                    discoveryManager = nil
                },
                onCancel: {
                    discoveryManager = nil
                }
            )
        }
    }
}
