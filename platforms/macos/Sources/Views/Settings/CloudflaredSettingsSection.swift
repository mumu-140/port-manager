/// CloudflaredSettingsSection - Cloudflare tunnel preferences
///
/// Displays cloudflared settings including:
/// - Transport protocol selection (HTTP/2 or QUIC)

import SwiftUI
import Defaults

struct CloudflaredSettingsSection: View {
    @Default(.cloudflaredProtocol) private var protocolSelection
    @Default(.customCloudflaredPath) private var customPath
    @State private var pathInput = ""

    private let service = CloudflaredService()

    private var effectivePath: String? {
        if let custom = customPath, !custom.isEmpty, FileManager.default.fileExists(atPath: custom) {
            return custom
        }
        return service.autoDetectedPath
    }

    var body: some View {
        SettingsGroup(L("settings.section.cloudflare"), icon: "cloud.fill") {
            VStack(spacing: 0) {
                SettingsRowContainer {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("settings.cloudflared.protocol"))
                                .fontWeight(.medium)
                            Text(L("settings.cloudflared.protocol.subtitle"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Picker("", selection: $protocolSelection) {
                            ForEach(CloudflaredProtocol.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 160)
                    }
                }

                SettingsDivider()

                SettingsRowContainer {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(L("settings.cloudflared.path"))
                                .fontWeight(.medium)

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
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                    Text(L("settings.portForwarding.notFound"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        HStack(spacing: 8) {
                            TextField(L("settings.portForwarding.customPath"), text: $pathInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                                .onAppear {
                                    pathInput = customPath ?? ""
                                }
                                .onChange(of: pathInput) { _, newValue in
                                    if newValue.isEmpty {
                                        Defaults[.customCloudflaredPath] = nil
                                    } else {
                                        Defaults[.customCloudflaredPath] = newValue
                                    }
                                }

                            if !pathInput.isEmpty {
                                Button(L("common.clear")) {
                                    pathInput = ""
                                    Defaults[.customCloudflaredPath] = nil
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        if let path = effectivePath {
                            HStack(spacing: 4) {
                                Text(L("settings.portForwarding.using"))
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(path)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(service.isUsingCustomPath ? L("settings.portForwarding.custom") : L("settings.portForwarding.auto"))
                                    .font(.caption2)
                                    .foregroundStyle(service.isUsingCustomPath ? Color.orange : Color.gray)
                            }
                        }
                    }
                }
            }
        }
    }
}
