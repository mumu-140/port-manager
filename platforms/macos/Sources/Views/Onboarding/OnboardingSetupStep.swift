import SwiftUI
import LaunchAtLogin
import KeyboardShortcuts
@preconcurrency import UserNotifications

struct OnboardingSetupStep: View {
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L("onboarding.setup.title"))
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom, 4)

            // Launch at Login
            VStack(alignment: .leading, spacing: 8) {
                LaunchAtLogin.Toggle {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("onboarding.setup.launchAtLogin"))
                            .fontWeight(.medium)
                        Text(L("onboarding.setup.launchAtLoginDetail"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Notifications
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("common.notifications"))
                            .fontWeight(.medium)
                        Text(L("onboarding.setup.notificationsDetail"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if notificationStatus == .authorized {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(L("common.enabled"))
                                .font(.callout)
                                .foregroundStyle(.green)
                        }
                    } else if notificationStatus == .denied {
                        Button(L("onboarding.openSettings")) {
                            if let bundleId = Bundle.main.bundleIdentifier {
                                let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleId)")!
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    } else {
                        Button(L("common.enable")) {
                            requestPermission()
                        }
                        .controlSize(.small)
                    }
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Keyboard Shortcut
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("onboarding.setup.globalShortcut"))
                            .fontWeight(.medium)
                        Text(L("onboarding.setup.globalShortcutDetail"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    KeyboardShortcuts.Recorder(for: .toggleMainWindow)
                        .frame(width: 150)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Spacer()
        }
        .padding(32)
        .task {
            await checkNotificationStatus()
        }
    }

    private func requestPermission() {
        Task {
            _ = await NotificationService.shared.requestPermission()
            await checkNotificationStatus()
        }
    }

    private func checkNotificationStatus() async {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }
}
