import SwiftUI

struct PortForwarderSettingsTab: View {
    @AppStorage("portForwardAutoStart") private var autoStart = false
    @AppStorage("portForwardShowNotifications") private var showNotifications = true

    var body: some View {
        Form {
            Section(L("k8s.startup")) {
                Toggle(L("k8s.autoStartConnections"), isOn: $autoStart)
            }

            Section(L("common.notifications")) {
                Toggle(L("k8s.showNotificationsHelp"), isOn: $showNotifications)
            }

            Section(L("k8s.dependencies")) {
                DependencyRow(
                    name: "kubectl",
                    dependency: DependencyChecker.shared.kubectl,
                    currentPath: DependencyChecker.shared.kubectlPath,
                    isCustom: DependencyChecker.shared.isUsingCustomKubectl,
                    customPathKey: .customKubectlPath
                )

                DependencyRow(
                    name: "socat",
                    dependency: DependencyChecker.shared.socat,
                    currentPath: DependencyChecker.shared.socatPath,
                    isCustom: DependencyChecker.shared.isUsingCustomSocat,
                    customPathKey: .customSocatPath
                )
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
