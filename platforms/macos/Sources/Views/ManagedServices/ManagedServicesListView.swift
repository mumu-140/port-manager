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
    @State private var stopAndEditRequest: ManagedServiceStopAndEditRequest?

    private func presetIcon(_ preset: ManagedServicePreset) -> String {
        preset.icon.isEmpty ? "gearshape" : preset.icon
    }

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
                Menu {
                    Button {
                        editorTarget = .add
                    } label: {
                        Label(L("preset.custom.title"), systemImage: "slider.horizontal.3")
                    }
                    Divider()
                    ForEach(ManagedServicePresets.all, id: \.id) { preset in
                        Button {
                            editorTarget = .addPreset(preset)
                        } label: {
                            Label(L(preset.titleKey), systemImage: presetIcon(preset))
                        }
                        .disabled(false)
                    }
                } label: {
                    Label(L("service.add"), systemImage: "plus")
                }
                .help(L("service.addHelp"))
            }
        }
        .sheet(item: $editorTarget) { target in
            ManagedServiceEditorView(
                editingConfig: target.config,
                openingPreset: target.preset
            )
        }
        .confirmationDialog(
            L("service.delete.title"),
            isPresented: isDeleteDialogPresented,
            titleVisibility: .visible
        ) {
            Button(L(deleteCopy?.buttonKey ?? "service.delete.confirm"), role: .destructive) {
                if let id = pendingDeleteID {
                    Task { await appState.deleteManagedService(id: id) }
                }
                pendingDeleteID = nil
            }
            Button(L("service.cancel"), role: .cancel) {
                pendingDeleteID = nil
            }
        } message: {
            if let copy = deleteCopy {
                Text(messageText(copy))
            }
        }
        .managedServiceStopAndEditConfirmation($stopAndEditRequest) { id in
            Task { await stopAndEdit(id: id) }
        }
    }

    private var filteredServices: [ManagedServiceState] {
        let query = appState.managedServiceManager.searchText
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

    private var pendingDeleteService: ManagedServiceState? {
        guard let id = pendingDeleteID else { return nil }
        return appState.managedServiceManager.service(id: id)
    }

    private func messageText(_ copy: ManagedServiceDeleteConfirmation.Copy) -> String {
        if let port = copy.port {
            return L(copy.messageKey, copy.name, port)
        }
        return L(copy.messageKey, copy.name)
    }

    /// Semantic delete copy for the pending deletion (design section 8.1).
    private var deleteCopy: ManagedServiceDeleteConfirmation.Copy? {
        guard let service = pendingDeleteService else { return nil }
        return ManagedServiceDeleteConfirmation.copy(for: ManagedServiceDeleteContext(
            name: service.name,
            port: service.port,
            isOwnedRunning: service.isOwned,
            isConflict: service.status == .conflict,
            hasQuickTunnel: appState.tunnelManager.hasTunnel(for: service.port)
        ))
    }

    /// Running services stop first; everything else opens the editor directly.
    private func beginEdit(_ service: ManagedServiceState) {
        if service.isOwned {
            stopAndEditRequest = ManagedServiceStopAndEditRequest(id: service.id, name: service.name)
        } else {
            editorTarget = .edit(service.config)
        }
    }

    private func stopAndEdit(id: UUID) async {
        guard await appState.prepareManagedServiceForEditing(id: id),
              let service = appState.managedServiceManager.service(id: id) else { return }
        editorTarget = .edit(service.config)
    }

    @ViewBuilder
    private func contextMenu(for service: ManagedServiceState) -> some View {
        if service.status == .running || service.status == .starting {
            Button(L("service.stop")) {
                Task { await appState.stopManagedService(id: service.id) }
            }
            .disabled(service.status != .running)
            Button(L("service.restart")) {
                Task { await appState.restartManagedService(id: service.id) }
            }
            .disabled(service.status != .running)
        } else {
            Button(L("service.start")) {
                Task { await appState.startManagedService(id: service.id) }
            }
            .disabled(service.status == .stopping || service.status == .conflict)
        }

        if service.status == .conflict {
            Button(L("service.conflict.killAndStart")) {
                Task { await appState.resolveManagedServiceConflict(id: service.id) }
            }
        }

        Divider()

        if isOpenable(service) {
            Button(L("service.open")) { open(service) }
                .disabled(service.status != .running)
        }

        Button(L("service.edit")) { beginEdit(service) }
            .disabled(service.isTransitioning)
            .help(L("service.editor.stopBeforeEdit"))

        Divider()

        Button(L("service.delete"), role: .destructive) {
            pendingDeleteID = service.id
        }
        .disabled(service.isTransitioning)
    }

    /// HTTP services expose the Open action; custom services (no preset ID)
    /// keep it for compatibility (preset capability mapping, v1).
    private func isOpenable(_ service: ManagedServiceState) -> Bool {
        guard let presetID = service.config.presetID else { return true }
        return ManagedServicePresets.preset(withID: presetID)?.isHTTPService ?? true
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
