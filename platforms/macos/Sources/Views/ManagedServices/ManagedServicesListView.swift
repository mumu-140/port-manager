import AppKit
import SwiftUI

/**
 * Content-column list of local service profiles.
 *
 * Selection drives the detail column through the shared
 * `ManagedServiceManager.selectedServiceID`.
 */
struct ManagedServicesListView: View {
    @Environment(AppState.self) private var appState

    @State private var editorTarget: ManagedServiceEditorTarget?
    @State private var pendingDeleteID: UUID?

    var body: some View {
        Group {
            if filteredServices.isEmpty {
                ContentUnavailableView {
                    Label(L("service.empty.title"), systemImage: "server.rack")
                } description: {
                    Text(appState.managedServiceManager.services.isEmpty
                         ? L("service.empty.detail")
                         : L("service.noSelection.detail"))
                }
            } else {
                List(selection: selectionBinding) {
                    ForEach(filteredServices) { service in
                        ManagedServiceRow(service: service)
                            .tag(service.id)
                            .contextMenu { contextMenu(for: service) }
                    }
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorTarget = .add
                } label: {
                    Label(L("service.add"), systemImage: "plus")
                }
                .help(L("service.addHelp"))
            }
        }
        .sheet(item: $editorTarget) { target in
            ManagedServiceEditorView(editingConfig: target.config)
        }
        .confirmationDialog(
            L("service.delete.title"),
            isPresented: isDeleteDialogPresented,
            titleVisibility: .visible
        ) {
            Button(L("service.delete.confirm"), role: .destructive) {
                if let id = pendingDeleteID {
                    Task { await appState.deleteManagedService(id: id) }
                }
                pendingDeleteID = nil
            }
            Button(L("service.cancel"), role: .cancel) {
                pendingDeleteID = nil
            }
        } message: {
            Text(L("service.delete.message"))
        }
    }

    private var filteredServices: [ManagedServiceState] {
        let query = appState.filter.searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let services = appState.managedServiceManager.services
        guard !query.isEmpty else { return services }
        return services.filter { service in
            service.name.lowercased().contains(query)
                || service.config.host.lowercased().contains(query)
                || service.config.startCommand.lowercased().contains(query)
                || String(service.port).contains(query)
        }
    }

    /// Selection is proxied manually because `managedServiceManager` is a
    /// `let` on `AppState`, which cannot form a reference-writable key path.
    private var selectionBinding: Binding<UUID?> {
        Binding(
            get: { appState.managedServiceManager.selectedServiceID },
            set: { appState.managedServiceManager.selectedServiceID = $0 }
        )
    }

    private var isDeleteDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteID != nil },
            set: { presented in
                if !presented { pendingDeleteID = nil }
            }
        )
    }

    @ViewBuilder
    private func contextMenu(for service: ManagedServiceState) -> some View {
        if service.status == .running || service.status == .starting {
            Button(L("service.stop")) {
                Task { await appState.stopManagedService(id: service.id) }
            }
            Button(L("service.restart")) {
                Task { await appState.restartManagedService(id: service.id) }
            }
        } else {
            Button(L("service.start")) {
                Task { await appState.startManagedService(id: service.id) }
            }
        }

        if service.status == .conflict {
            Button(L("service.conflict.killAndStart")) {
                Task { await appState.resolveManagedServiceConflict(id: service.id) }
            }
        }

        Divider()

        Button(L("service.open")) { open(service) }
            .disabled(service.status != .running)

        Button(L("service.edit")) { editorTarget = .edit(service.config) }
            .disabled(service.isOwned || service.isTransitioning)
            .help(L("service.editor.stopBeforeEdit"))

        Divider()

        Button(L("service.delete"), role: .destructive) {
            pendingDeleteID = service.id
        }
    }

    private func open(_ service: ManagedServiceState) {
        guard let url = service.config.openURL else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Compact sidebar-style row for one service profile.
struct ManagedServiceRow: View {
    let service: ManagedServiceState

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(ManagedServiceStatusBadge.color(for: service.status))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .fontWeight(.medium)
                Text(":\(service.port) · \(service.config.host)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(L(service.status.localizationKey))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
