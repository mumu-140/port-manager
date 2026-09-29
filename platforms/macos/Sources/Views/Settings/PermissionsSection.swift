/// PermissionsSection - Permission management UI
///
/// Manages accessibility and notification permissions:
/// - Shows current permission status with visual indicators
/// - Provides buttons to grant or configure permissions
/// - Displays helpful status messages
///
/// - Note: Accessibility is required for global keyboard shortcuts.
/// - Important: Notification permission only works in .app bundles.

import SwiftUI
import ApplicationServices
@preconcurrency import UserNotifications

struct PermissionsSection: View {
    @Binding var hasAccessibility: Bool
    @Binding var notificationStatus: UNAuthorizationStatus
    let onRequestNotification: () -> Void
    let onOpenNotificationSettings: () -> Void

    var body: some View {
        SettingsGroup(L("settings.section.permissions"), icon: "lock.shield.fill") {
            VStack(spacing: 0) {
                // Accessibility Permission
                SettingsRowContainer {
                    HStack(spacing: 12) {
                        Image(systemName: hasAccessibility ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(hasAccessibility ? .green : .orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("settings.permissions.accessibility"))
                                .fontWeight(.medium)
                            Text(hasAccessibility ? L("settings.permissions.accessibility.granted") : L("settings.permissions.accessibility.required"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if hasAccessibility {
                            Text(L("settings.permissions.grantedBadge"))
                                .font(.caption)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.green.opacity(0.1))
                                .clipShape(Capsule())
                        } else {
                            Button(L("settings.permissions.grantAccess")) {
                                promptAccessibility()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }

                SettingsDivider()

                // Notification Permission
                SettingsRowContainer {
                    HStack(spacing: 12) {
                        Image(systemName: notificationStatusIcon)
                            .font(.title2)
                            .foregroundStyle(notificationStatusColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("settings.permissions.notifications"))
                                .fontWeight(.medium)
                            Text(notificationStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if notificationStatus == .authorized {
                            Text(L("common.enabled"))
                                .font(.caption)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.green.opacity(0.1))
                                .clipShape(Capsule())
                        } else if notificationStatus == .notDetermined {
                            Button(L("common.enable")) {
                                onRequestNotification()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else {
                            Button(L("settings.permissions.openSettings")) {
                                onOpenNotificationSettings()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Notification Status Helpers

    /// Returns appropriate icon for notification status
    private var notificationStatusIcon: String {
        switch notificationStatus {
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .notDetermined: return "questionmark.circle.fill"
        case .provisional, .ephemeral: return "checkmark.circle.fill"
        @unknown default: return "questionmark.circle.fill"
        }
    }

    /// Returns color for notification status indicator
    private var notificationStatusColor: Color {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        @unknown default: return .secondary
        }
    }

    /// Returns descriptive text for notification status
    private var notificationStatusText: String {
        switch notificationStatus {
        case .authorized: return L("settings.permissions.notif.authorized")
        case .denied: return L("settings.permissions.notif.denied")
        case .notDetermined: return L("settings.permissions.notif.notDetermined")
        case .provisional: return L("settings.permissions.notif.provisional")
        case .ephemeral: return L("settings.permissions.notif.ephemeral")
        @unknown default: return L("settings.permissions.notif.unknown")
        }
    }
}

// MARK: - Accessibility Prompt

/// Prompts user to grant accessibility permission
private func promptAccessibility() {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
}
