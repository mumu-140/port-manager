import SwiftUI

struct DependencyWarningBanner: View {
    @State private var isInstalling = false

    var body: some View {
        AlertBanner(
            icon: "exclamationmark.triangle.fill",
            title: L("k8s.missingDependencies"),
            message: L("k8s.kubectlRequiredForForwarding")
        ) {
            if isInstalling {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button(L("common.install")) {
                    installDependencies()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func installDependencies() {
        isInstalling = true
        Task {
            _ = await DependencyChecker.shared.checkAndInstallMissing()
            await MainActor.run { isInstalling = false }
        }
    }
}
