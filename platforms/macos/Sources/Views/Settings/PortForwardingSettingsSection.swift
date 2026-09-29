/// PortForwardingSettingsSection - Port forwarding dependencies settings
///
/// Displays port forwarding settings including:
/// - kubectl path and custom path input
/// - socat path and custom path input
/// - Auto-start toggle

import SwiftUI
import Defaults

struct PortForwardingSettingsSection: View {
    @AppStorage("portForwardAutoStart") private var autoStart = false

    var body: some View {
        SettingsGroup(L("settings.section.portForwarding"), icon: "point.3.connected.trianglepath.dotted") {
            VStack(spacing: 0) {
                // Auto-start toggle
                SettingsToggleRow(
                    title: L("settings.portForwarding.autoStart"),
                    subtitle: L("settings.portForwarding.autoStart.subtitle"),
                    isOn: $autoStart
                )

                SettingsDivider()

                // kubectl dependency
                DependencySettingsRow(
                    name: "kubectl",
                    dependency: DependencyChecker.shared.kubectl,
                    autoPath: DependencyChecker.shared.kubectl.installedPath,
                    customPathKey: .customKubectlPath
                )

                SettingsDivider()

                // socat dependency
                DependencySettingsRow(
                    name: "socat",
                    dependency: DependencyChecker.shared.socat,
                    autoPath: DependencyChecker.shared.socat.installedPath,
                    customPathKey: .customSocatPath
                )
            }
        }
    }
}

// MARK: - Dependency Settings Row

private struct DependencySettingsRow: View {
    let name: String
    let dependency: PortForwardDependency
    let autoPath: String?
    let customPathKey: Defaults.Key<String?>

    @Default private var customPath: String?
    @State private var isInstalling = false
    @State private var pathInput = ""

    init(name: String, dependency: PortForwardDependency, autoPath: String?, customPathKey: Defaults.Key<String?>) {
        self.name = name
        self.dependency = dependency
        self.autoPath = autoPath
        self.customPathKey = customPathKey
        self._customPath = Default(customPathKey)
    }

    private var effectivePath: String? {
        if let custom = customPath, !custom.isEmpty, FileManager.default.fileExists(atPath: custom) {
            return custom
        }
        return autoPath
    }

    private var isUsingCustom: Bool {
        if let custom = customPath, !custom.isEmpty, FileManager.default.fileExists(atPath: custom) {
            return true
        }
        return false
    }

    var body: some View {
        SettingsRowContainer {
            VStack(alignment: .leading, spacing: 10) {
                // Title row
                HStack {
                    HStack(spacing: 6) {
                        Text(name)
                            .fontWeight(.medium)

                        if !dependency.isRequired {
                            Text(L("settings.portForwarding.optional"))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    if effectivePath != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(L("settings.portForwarding.installed"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(L("settings.portForwarding.notFound"))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if isInstalling {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Button(L("settings.portForwarding.install")) {
                                    install()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                // Path input
                HStack(spacing: 8) {
                    TextField(L("settings.portForwarding.customPath"), text: $pathInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .onAppear {
                            pathInput = customPath ?? ""
                        }
                        .onChange(of: pathInput) { _, newValue in
                            if newValue.isEmpty {
                                Defaults[customPathKey] = nil
                            } else {
                                Defaults[customPathKey] = newValue
                            }
                        }

                    if !pathInput.isEmpty {
                        Button(L("common.clear")) {
                            pathInput = ""
                            Defaults[customPathKey] = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // Current path info
                if let path = effectivePath {
                    HStack(spacing: 4) {
                        Text(L("settings.portForwarding.using"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(isUsingCustom ? L("settings.portForwarding.custom") : L("settings.portForwarding.auto"))
                            .font(.caption2)
                            .foregroundStyle(isUsingCustom ? Color.orange : Color.gray)
                    }
                } else if let auto = autoPath {
                    HStack(spacing: 4) {
                        Text(L("settings.portForwarding.autoDetected"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(auto)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func install() {
        isInstalling = true
        Task {
            _ = await DependencyChecker.shared.checkAndInstallMissing()
            await MainActor.run { isInstalling = false }
        }
    }
}
