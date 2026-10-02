import AppKit
import SwiftUI

/**
 * Detail-column view for the selected local service: status, actions,
 * conflict resolution, quick tunnel, and bounded log output.
 */
struct ManagedServiceDetailView: View {
    @Environment(AppState.self) private var appState

    @State private var editorTarget: ManagedServiceEditorTarget?
    @State private var showDeleteConfirmation = false
    @State private var pendingExposureWarning: String?
    @State private var stopAndEditRequest: ManagedServiceStopAndEditRequest?

    var body: some View {
        if let service = selectedService {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(service)
                    actionBar(service)
                    if let error = service.lastError {
                        errorBanner(error)
                    }
                    if service.status == .conflict, let conflict = service.conflict {
                        conflictSection(service, conflict)
                    }
                    detailsSection(service)
                    exposureSection(service)
                    ManagedServiceLogView(service: service)
                }
                .padding(18)
            }
            .sheet(item: $editorTarget) { target in
                ManagedServiceEditorView(editingConfig: target.config)
            }
            .confirmationDialog(
                L("service.delete.title"),
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(L(deleteCopy.buttonKey), role: .destructive) {
                    let id = service.id
                    Task { await appState.deleteManagedService(id: id) }
                }
                Button(L("service.cancel"), role: .cancel) {}
            } message: {
                Text(messageText(deleteCopy))
            }
            .managedServiceStopAndEditConfirmation($stopAndEditRequest) { id in
                Task { await stopAndEdit(id: id) }
            }
            .confirmationDialog(
                L("exposure.confirm.title"),
                isPresented: exposureConfirmationBinding,
                titleVisibility: .visible
            ) {
                Button(L("exposure.confirm.start"), role: .destructive) {
                    if let service = selectedService {
                        appState.tunnelManager.startTunnel(for: service.port)
                    }
                    pendingExposureWarning = nil
                }
                Button(L("service.cancel"), role: .cancel) {
                    pendingExposureWarning = nil
                }
            } message: {
                Text(L(pendingExposureWarning ?? ""))
            }
        } else {
            ContentUnavailableView {
                Label(L("service.noSelection.title"), systemImage: "server.rack")
            } description: {
                Text(L("service.noSelection.detail"))
            }
        }
    }

    private var selectedService: ManagedServiceState? {
        guard let id = appState.managedServiceManager.selectedServiceID else { return nil }
        return appState.managedServiceManager.service(id: id)
    }

    /// Semantic delete copy for the selected service (design section 8.1).
    private var deleteCopy: ManagedServiceDeleteConfirmation.Copy {
        let service = selectedService
        return ManagedServiceDeleteConfirmation.copy(for: ManagedServiceDeleteContext(
            name: service?.name ?? "",
            port: service?.port ?? 0,
            isOwnedRunning: service?.isOwned ?? false,
            isConflict: service?.status == .conflict,
            hasQuickTunnel: service.map { appState.tunnelManager.hasTunnel(for: $0.port) } ?? false
        ))
    }

    private func messageText(_ copy: ManagedServiceDeleteConfirmation.Copy) -> String {
        if let port = copy.port {
            return L(copy.messageKey, copy.name, port)
        }
        return L(copy.messageKey, copy.name)
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

    // MARK: - Sections

    private func header(_ service: ManagedServiceState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(service.name)
                    .font(.title2)
                    .bold()
                Spacer()
                ManagedServiceStatusBadge(status: service.status)
            }
            Text(":\(service.port) · \(service.config.host)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func actionBar(_ service: ManagedServiceState) -> some View {
        HStack(spacing: 8) {
            if service.status == .running || service.status == .starting {
                Button(L("service.stop")) {
                    Task { await appState.stopManagedService(id: service.id) }
                }
                .disabled(service.status == .starting)

                Button(L("service.restart")) {
                    Task { await appState.restartManagedService(id: service.id) }
                }
                .disabled(service.status != .running)
            } else {
                Button(L("service.start")) {
                    Task { await appState.startManagedService(id: service.id) }
                }
                .disabled(service.status == .conflict || service.status == .stopping)
            }

            if isHTTPService(service) {
                Button(L("service.open")) { open(service) }
                    .disabled(service.status != .running)
            }

            Button(L("service.edit")) { beginEdit(service) }
                .disabled(service.isTransitioning)
                .help(L("service.editor.stopBeforeEdit"))

            Spacer()

            Button(L("service.delete"), role: .destructive) {
                showDeleteConfirmation = true
            }
            .disabled(service.isTransitioning)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.red)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func conflictSection(
        _ service: ManagedServiceState,
        _ conflict: ManagedServiceConflict
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("service.conflict.title"))
                .font(.headline)
            Text(L("service.conflict.message", conflict.port))
                .font(.callout)

            ForEach(conflict.occupants) { occupant in
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("service.conflict.occupant", occupant.processName, occupant.pid, occupant.user))
                        .font(.callout)
                        .bold()
                    Text(occupant.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(occupant.command)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack {
                Button(L("service.conflict.killAndStart"), role: .destructive) {
                    Task { await appState.resolveManagedServiceConflict(id: service.id) }
                }
                // Cancel is deliberately non-destructive: the conflict stays
                // until reconciliation verifies the port is free (6.4, 9.1).
                Button(L("service.conflict.cancel"), role: .cancel) {}
                Spacer()
            }

            Text(L("service.conflict.startHelp"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func detailsSection(_ service: ManagedServiceState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("service.detail.command"))
                .font(.headline)

            detailRow("service.detail.workingDirectory", service.config.workingDirectory)
            detailRow("service.detail.command", service.config.startCommand)
            detailRow("service.detail.rootPID", service.rootPID.map(String.init) ?? "—")
            detailRow(
                "service.detail.listenerPIDs",
                service.listenerPIDs.isEmpty
                    ? "—"
                    : service.listenerPIDs.map(String.init).joined(separator: ", ")
            )

            if let startedAt = service.startedAt {
                detailRow(
                    "service.detail.startedAt",
                    startedAt.formatted(date: .abbreviated, time: .standard)
                )
            }

            if let exitCode = service.lastExitCode {
                detailRow("service.detail.exitCode", String(exitCode))
            }
        }
    }

    /// Network Access section (design section 7.2): Local row always, the
    /// Temporary public (unchanged Quick Tunnel runtime) and Stable public
    /// deep-link rows only for HTTP services — Quick Tunnel proxies an HTTP
    /// endpoint, so non-HTTP presets (SSH forwards) do not offer it.
    @ViewBuilder
    private func exposureSection(_ service: ManagedServiceState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("service.exposure.title"))
                .font(.headline)

            localRow(service)

            if isHTTPService(service) {
                temporaryPublicRow(service)
                stablePublicRow()
            }
        }
    }

    /// Preset capability check: HTTP services expose Open and Quick Tunnel
    /// actions; custom services (no preset ID) and unknown preset IDs keep
    /// the existing behavior for compatibility.
    private func isHTTPService(_ service: ManagedServiceState) -> Bool {
        guard let presetID = service.config.presetID else { return true }
        return ManagedServicePresets.preset(withID: presetID)?.isHTTPService ?? true
    }

    /// Local row: formalizes what Open already does, with Copy added.
    @ViewBuilder
    private func localRow(_ service: ManagedServiceState) -> some View {
        HStack(spacing: 8) {
            Text(L("service.exposure.local"))
                .font(.caption)
            Spacer()
            if service.status == .running, let url = service.config.openURL {
                Text(url.absoluteString)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                Button(L("service.tunnel.copy")) {
                    ClipboardService.copy(url.absoluteString)
                }
                Button(L("service.tunnel.open")) {
                    open(service)
                }
            } else {
                Text(L("service.exposure.localIdle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Temporary public: the Quick Tunnel runtime is untouched; the section
    /// slot gains an intent-based label and helper copy. Without cloudflared
    /// installed the user gets guidance instead of an apparently valid Start
    /// button (design notes, section 15).
    @ViewBuilder
    private func temporaryPublicRow(_ service: ManagedServiceState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("service.exposure.temporaryPublic"))
                .font(.caption)
            Text(L("service.exposure.temporaryPublicHelper"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if !appState.tunnelManager.isCloudflaredInstalled {
                Text(L("service.tunnel.unavailable"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let tunnel = appState.tunnelManager.tunnelState(for: service.port) {
                tunnelStateView(tunnel, service: service)
            } else if service.status == .running {
                Button(L("service.tunnel.start")) {
                    startTunnelWithExposureGate(service)
                }
            } else {
                Text(L("service.tunnel.stopped"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Exposure double-warning gate (design section 10.2): writable Dufs and
    /// public Jupyter confirm before their Quick Tunnel starts; everything
    /// else starts exactly as today.
    private func startTunnelWithExposureGate(_ service: ManagedServiceState) {
        if let messageKey = ManagedServiceExposureWarning.messageKey(for: service.config) {
            pendingExposureWarning = messageKey
        } else {
            appState.tunnelManager.startTunnel(for: service.port)
        }
    }

    private var exposureConfirmationBinding: Binding<Bool> {
        Binding(
            get: { pendingExposureWarning != nil },
            set: { presented in
                if !presented { pendingExposureWarning = nil }
            }
        )
    }

    /// Stable public: a pure deep-link into the existing global tunnels UI.
    /// No new runtime, no manager coupling (design section 7.2).
    private func stablePublicRow() -> some View {
        Button {
            appState.selectedSidebarItem = .cloudflareTunnels
        } label: {
            Text(L("service.exposure.stablePublic"))
                .font(.caption)
        }
        .buttonStyle(.link)
    }

    @ViewBuilder
    private func tunnelStateView(
        _ tunnel: CloudflareTunnelState,
        service: ManagedServiceState
    ) -> some View {
        switch tunnel.status {
        case .starting, .stopping:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(L("service.tunnel.starting"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L("service.tunnel.stop")) {
                    appState.tunnelManager.stopTunnel(for: service.port)
                }
            }
        case .active:
            HStack {
                Text(tunnel.tunnelURL ?? L("service.tunnel.starting"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button(L("service.tunnel.copy")) {
                    appState.tunnelManager.copyURL(for: service.port)
                }
                Button(L("service.tunnel.open")) {
                    appState.tunnelManager.openURL(for: service.port)
                }
                Button(L("service.tunnel.stop")) {
                    appState.tunnelManager.stopTunnel(for: service.port)
                }
            }
        case .error:
            VStack(alignment: .leading, spacing: 6) {
                Text(tunnel.lastError ?? L("service.error.tunnel"))
                    .font(.caption)
                    .foregroundStyle(.red)
                HStack {
                    Button(L("service.tunnel.retry")) {
                        appState.tunnelManager.startTunnel(for: service.port)
                    }
                    Button(L("service.tunnel.stop")) {
                        appState.tunnelManager.stopTunnel(for: service.port)
                    }
                }
            }
        case .idle:
            Button(L("service.tunnel.start")) {
                appState.tunnelManager.startTunnel(for: service.port)
            }
        }
    }

    private func detailRow(_ titleKey: String, _ value: String) -> some View {
        LabeledContent(L(titleKey)) {
            Text(value)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
        }
    }

    private func open(_ service: ManagedServiceState) {
        guard let url = service.config.openURL else { return }
        NSWorkspace.shared.open(url)
    }
}
