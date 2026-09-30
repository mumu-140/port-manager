import SwiftUI

struct NamespacePanel: View {
    let namespaces: [KubernetesNamespace]
    let selectedNamespace: KubernetesNamespace?
    let state: KubernetesDiscoveryState
    let onSelect: (KubernetesNamespace) -> Void
    let onRefresh: () -> Void
    let onAddCustom: ([String]) -> Void
    let onRemoveCustom: (KubernetesNamespace) -> Void

    @State private var showingAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L("k8s.namespaces"))
                    .font(.headline)
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .help(L("k8s.addCustomNamespaceHelp"))
                Button {
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .disabled(state == .loading)
                .help(L("k8s.refreshNamespacesHelp"))
            }
            .padding(12)

            Divider()

            if state == .loading {
                VStack {
                    Spacer()
                    ProgressView()
                    Text(L("common.loading"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if case .error(let msg) = state {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 8) {
                        Button(L("common.retry"), action: onRefresh)
                            .buttonStyle(.bordered)
                        Button(L("k8s.addCustom")) {
                            showingAddSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Spacer()
                }
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(namespaces) { ns in
                            Button { onSelect(ns) } label: {
                                HStack {
                                    Image(systemName: ns.isCustom ? "pencil.and.list.clipboard" : "folder")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(ns.name)
                                        .font(.system(.body, design: .monospaced))
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedNamespace?.id == ns.id ? Color.accentColor.opacity(0.2) : Color.clear)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if ns.isCustom {
                                    Button(L("common.remove"), role: .destructive) {
                                        onRemoveCustom(ns)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddCustomNamespaceSheet(onAdd: onAddCustom)
        }
    }
}
