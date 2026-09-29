/// GeneralSettingsSection - General app preferences
///
/// Displays general settings including:
/// - Interface language (follow system / English / 简体中文)
/// - Launch at login toggle
///
/// - Note: Uses LaunchAtLogin package for login item management.

import SwiftUI
import LaunchAtLogin
import Defaults

struct GeneralSettingsSection: View {
    @Default(.hideSystemProcesses) private var hideSystemProcesses
    @Default(.skipKillConfirmation) private var skipKillConfirmation
    @Environment(Localization.self) private var localization

    var body: some View {
        @Bindable var localization = localization

        SettingsGroup(L("settings.section.general"), icon: "gearshape.fill") {
            // Interface language
            SettingsRowContainer {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.language"))
                            .fontWeight(.medium)
                        Text(L("settings.language.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $localization.language) {
                        Text(L("settings.language.system")).tag(AppLanguage.system)
                        Text(L("settings.language.english")).tag(AppLanguage.english)
                        Text(L("settings.language.simplifiedChinese")).tag(AppLanguage.simplifiedChinese)
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            SettingsDivider()

            SettingsRowContainer {
                LaunchAtLogin.Toggle {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.general.launchAtLogin"))
                            .fontWeight(.medium)
                        Text(L("settings.general.launchAtLogin.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            SettingsDivider()

            SettingsToggleRow(
                title: L("settings.general.hideSystemProcesses"),
                subtitle: L("settings.general.hideSystemProcesses.subtitle"),
                isOn: $hideSystemProcesses
            )

            SettingsDivider()

            SettingsToggleRow(
                title: L("settings.general.skipKillConfirmation"),
                subtitle: L("settings.general.skipKillConfirmation.subtitle"),
                isOn: $skipKillConfirmation
            )
        }
    }
}
