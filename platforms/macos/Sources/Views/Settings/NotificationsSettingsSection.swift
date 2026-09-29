import SwiftUI
import Defaults

struct NotificationsSettingsSection: View {
    @Default(.notifyProcessTypes) private var enabledTypes

    var body: some View {
        SettingsGroup(L("settings.notifications.title"), icon: "bell.fill") {
            VStack(spacing: 0) {
                SettingsRowContainer {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.notifications.header"))
                            .fontWeight(.medium)
                        Text(L("settings.notifications.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(ProcessType.allCases) { type in
                    SettingsDivider()
                    processTypeToggle(type)
                }
            }
        }
    }

    private func processTypeToggle(_ type: ProcessType) -> some View {
        SettingsRowContainer {
            Toggle(isOn: Binding(
                get: { enabledTypes.contains(type.rawValue) },
                set: { enabled in
                    if enabled {
                        Defaults[.notifyProcessTypes].insert(type.rawValue)
                    } else {
                        Defaults[.notifyProcessTypes].remove(type.rawValue)
                    }
                }
            )) {
                HStack(spacing: 8) {
                    Image(systemName: type.icon)
                        .foregroundStyle(type.color)
                        .frame(width: 20)
                    Text(type.rawValue)
                }
            }
        }
    }
}
