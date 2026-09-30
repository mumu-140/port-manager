import SwiftUI

struct CloudflaredMissingBanner: View {
    @Environment(AppState.self) private var appState
    @State private var isCopied = false
    @State private var isInstalling = false
    @State private var installError: String?

    private let installCommand = "brew install cloudflared"

    /// Check if Homebrew is installed
    private var brewPath: String? {
        let paths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    private var isBrewInstalled: Bool {
        brewPath != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "cloud.fill")
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L("tunnel.cloudflaredRequired"))
                        .font(.headline)
                    if !isBrewInstalled {
                        Text(L("tunnel.homebrewRequired"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        Text(L("tunnel.installCloudflaredPrompt"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Refresh button to re-check installation
                Button {
                    appState.tunnelManager.recheckInstallation()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help(L("tunnel.checkInstalledHelp"))

                if isBrewInstalled {
                    // Copy command button
                    Button {
                        ClipboardService.copy(installCommand)
                        isCopied = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            isCopied = false
                        }
                    } label: {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .help(L(isCopied ? "common.copied" : "common.copyCommand"))

                    // Install button
                    Button {
                        installCloudflared()
                    } label: {
                        if isInstalling {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                            Text(L("tunnel.installing"))
                        } else {
                            Label(L("common.install"), systemImage: "arrow.down.circle")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInstalling)
                } else {
                    // Open brew.sh button
                    Button {
                        if let url = URL(string: "https://brew.sh") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label(L("tunnel.getHomebrew"), systemImage: "safari")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(12)

            // Error message
            if let error = installError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button(L("tunnel.dismiss")) {
                        installError = nil
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(Theme.Colors.link.opacity(0.1))
        .overlay(
            Rectangle()
                .fill(Theme.Colors.link)
                .frame(height: 2),
            alignment: .top
        )
    }

    private func installCloudflared() {
        guard let brewPath = brewPath else { return }

        isInstalling = true
        installError = nil

        Task {
            let result = await ProcessExecutor.run(brewPath, arguments: ["install", "cloudflared"])
            isInstalling = false
            guard let result else {
                installError = L("k8s.failedToRunBrew")
                return
            }
            if result.succeeded {
                appState.tunnelManager.recheckInstallation()
            } else {
                let combined = result.standardOutput + result.standardError
                let errorOutput = combined.isEmpty ? L("common.unknownError") : combined
                installError = L("k8s.installationFailed", String(errorOutput.prefix(100)))
            }
        }
    }
}
