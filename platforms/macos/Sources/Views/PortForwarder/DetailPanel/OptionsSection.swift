import SwiftUI

struct OptionsSection: View {
    @Binding var proxyEnabled: Bool
    @Binding var useDirectExec: Bool
    @Binding var autoReconnect: Bool
    @Binding var isEnabled: Bool
    @Binding var notifyOnConnect: Bool
    @Binding var notifyOnDisconnect: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("k8s.options"), systemImage: "gearshape")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                Toggle(isOn: $proxyEnabled) {
                    Label(L("k8s.proxy"), systemImage: "network")
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if proxyEnabled {
                    Toggle(isOn: $useDirectExec) {
                        Label(L("k8s.multiConn"), systemImage: "arrow.triangle.branch")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(L("k8s.enableMultipleHelp"))
                }

                Spacer()
            }

            HStack(spacing: 20) {
                Toggle(isOn: $autoReconnect) {
                    Label(L("k8s.autoReconnect"), systemImage: "arrow.clockwise")
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $isEnabled) {
                    Label(L("common.enabled"), systemImage: "power")
                }
                .toggleStyle(.checkbox)

                Spacer()
            }
            .font(.callout)

            HStack(spacing: 20) {
                Toggle(isOn: $notifyOnConnect) {
                    Label(L("k8s.notifyOnConnect"), systemImage: "bell")
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $notifyOnDisconnect) {
                    Label(L("k8s.notifyOnDisconnect"), systemImage: "bell.slash")
                }
                .toggleStyle(.checkbox)

                Spacer()
            }
            .font(.callout)
        }
    }
}
