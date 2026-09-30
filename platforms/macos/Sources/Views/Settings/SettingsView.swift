/// SettingsView - Main settings interface
///
/// Displays app settings organized into sections:
/// - General preferences (launch at login)
/// - Keyboard shortcuts (global hotkeys)
/// - Permissions (accessibility, notifications)
/// - Software updates (Sparkle integration)
/// - Sponsors configuration
/// - About information
///
/// - Note: Automatically checks permissions every 5 seconds while visible.
/// - Important: Uses `@Bindable var state: AppState` for state management.

import SwiftUI
import ApplicationServices
@preconcurrency import UserNotifications
import Sparkle
import LaunchAtLogin
import Defaults

struct SettingsView: View {
    @Bindable var state: AppState
    var updateManager: UpdateManager
    @Environment(SponsorManager.self) var sponsorManager
    @Environment(\.openWindow) private var openWindow
    @State private var hasAccessibility = AXIsProcessTrusted()
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var sponsorDisplayInterval = Defaults[.sponsorDisplayInterval]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // MARK: - General
                GeneralSettingsSection()

                // MARK: - Port Forwarding
                PortForwardingSettingsSection()

                // MARK: - Auto-Kill Rules
                AutoKillSettingsSection()

                // MARK: - Notifications
                NotificationsSettingsSection()

                // MARK: - Cloudflare Tunnels
                CloudflaredSettingsSection()

                // MARK: - Keyboard Shortcuts
                ShortcutsSection()

                // MARK: - Permissions
                PermissionsSection(
                    hasAccessibility: $hasAccessibility,
                    notificationStatus: $notificationStatus,
                    onRequestNotification: requestNotificationPermission,
                    onOpenNotificationSettings: openNotificationSettings
                )

                // MARK: - Updates
                SettingsGroup(L("settings.section.updates"), icon: "arrow.triangle.2.circlepath") {
                    VStack(spacing: 0) {
                        SettingsRowContainer {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L("settings.updates.appVersion", AppInfo.versionString))
                                        .fontWeight(.medium)
                                    if let lastCheck = updateManager.lastUpdateCheckDate {
                                        Text(L("settings.updates.lastChecked", lastCheck.formatted(.relative(presentation: .named))))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text(L("settings.updates.neverChecked"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Button(L("settings.updates.checkNow")) {
                                    updateManager.checkForUpdates()
                                }
                                .disabled(!updateManager.canCheckForUpdates)
                            }
                        }

                        SettingsDivider()

                        SettingsToggleRow(
                            title: L("settings.updates.checkAutomatically"),
                            subtitle: L("settings.updates.checkAutomatically.subtitle"),
                            isOn: Binding(
                                get: { updateManager.automaticallyChecksForUpdates },
                                set: { updateManager.automaticallyChecksForUpdates = $0 }
                            )
                        )

                        SettingsDivider()

                        SettingsToggleRow(
                            title: L("settings.updates.downloadAutomatically"),
                            subtitle: L("settings.updates.downloadAutomatically.subtitle"),
                            isOn: Binding(
                                get: { updateManager.automaticallyDownloadsUpdates },
                                set: { updateManager.automaticallyDownloadsUpdates = $0 }
                            )
                        )
                    }
                }

                // MARK: - Sponsors
                SettingsGroup(L("settings.section.sponsors"), icon: "heart.fill") {
                    VStack(spacing: 0) {
                        SettingsRowContainer {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L("settings.sponsors.showWindow"))
                                        .fontWeight(.medium)
                                    Text(L("settings.sponsors.showWindow.subtitle"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Picker("", selection: $sponsorDisplayInterval) {
                                    ForEach(SponsorDisplayInterval.allCases, id: \.self) { interval in
                                        Text(interval.localizedName).tag(interval)
                                    }
                                }
                                .frame(width: 130)
                                .onChange(of: sponsorDisplayInterval) { _, newValue in
                                    Defaults[.sponsorDisplayInterval] = newValue
                                }
                            }
                        }

                        SettingsDivider()

                        SettingsRowContainer {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L("settings.sponsors.view"))
                                        .fontWeight(.medium)
                                    Text(L("settings.sponsors.view.subtitle"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button(L("settings.sponsors.showWindowButton")) {
                                    sponsorManager.showSponsorsWindow()
                                    openWindow(id: "sponsors")
                                }
                            }
                        }
                    }
                }

                // MARK: - About
                SettingsGroup(L("settings.section.about"), icon: "info.circle.fill") {
                    VStack(spacing: 0) {
                        SettingsRowContainer {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L("settings.about.developer"))
                                        .fontWeight(.medium)
                                    Text(AppInfo.maintainer)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }

                        SettingsDivider()

                        SettingsLinkRow(title: "GitHub", subtitle: L("settings.about.github.subtitle"), icon: "star.fill", url: AppInfo.githubRepo)
                        SettingsDivider()
                        SettingsLinkRow(title: L("settings.about.support"), subtitle: L("settings.about.support.subtitle"), icon: "heart.fill", url: AppInfo.supportURL)
                        SettingsDivider()
                        SettingsLinkRow(title: L("settings.about.reportIssue"), subtitle: L("settings.about.reportIssue.subtitle"), icon: "ladybug.fill", url: AppInfo.githubIssues)
                        SettingsDivider()
                        SettingsLinkRow(title: L("settings.about.upstream"), subtitle: L("settings.about.upstream.subtitle"), icon: "arrow.triangle.branch", url: AppInfo.upstreamRepo)
                        SettingsDivider()
                        SettingsButtonRow(
                            title: L("settings.about.showWelcome"),
                            subtitle: L("settings.about.showWelcome.subtitle"),
                            icon: "hand.wave.fill",
                            action: {
                                Defaults[.hasCompletedOnboarding] = false
                            }
                        )
                    }
                }
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            // Periodically check permissions while view is visible
            // Task automatically cancels when view disappears
            while !Task.isCancelled {
                checkPermissions()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    // MARK: - Permission Management

    /// Checks current permission states
    private func checkPermissions() {
        // Check accessibility
        hasAccessibility = AXIsProcessTrusted()

        // Check notification permission (only works in .app bundle)
        guard Bundle.main.bundleIdentifier != nil,
              Bundle.main.bundlePath.hasSuffix(".app") else {
            // Running from debug build, skip notification check
            notificationStatus = .notDetermined
            return
        }

        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            await MainActor.run {
                notificationStatus = settings.authorizationStatus
            }
        }
    }

    /// Requests notification permission from user
    private func requestNotificationPermission() {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return }

        Task {
            do {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
                await MainActor.run {
                    checkPermissions()
                }
            } catch {
                // Permission denied or error
            }
        }
    }

    /// Opens system notification settings for this app
    private func openNotificationSettings() {
        // Open System Settings > Notifications for this app
        if let bundleId = Bundle.main.bundleIdentifier {
            let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleId)")!
            NSWorkspace.shared.open(url)
        }
    }
}
