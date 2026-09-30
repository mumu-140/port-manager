import AppKit
import SwiftUI

/// Bounded, auto-scrolling output panel for a managed service.
struct ManagedServiceLogView: View {
    @Environment(AppState.self) private var appState

    let service: ManagedServiceState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L("service.detail.output"))
                    .font(.headline)
                Spacer()
                Button(L("service.log.copy")) { copyOutput() }
                    .disabled(service.recentOutput.isEmpty)
                Button(L("service.log.clear")) {
                    appState.managedServiceManager.clearOutput(id: service.id)
                }
                .disabled(service.recentOutput.isEmpty)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if service.recentOutput.isEmpty {
                            Text(L("service.detail.noOutput"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(service.recentOutput) { entry in
                            Text(entry.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(entry.stream == .standardError ? Color.red : Color.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .frame(minHeight: 160)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                )
                .onChange(of: service.recentOutput.count) { _, _ in
                    guard let last = service.recentOutput.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func copyOutput() {
        let text = service.recentOutput.map(\.text).joined(separator: "\n")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        _ = pasteboard.setString(text, forType: .string)
    }
}
