/**
 * ShortcutsSection.swift
 * PortKiller
 *
 * Keyboard shortcuts configuration section for settings.
 * Allows users to customize global keyboard shortcuts.
 */

import SwiftUI
import KeyboardShortcuts
import ApplicationServices

/// Keyboard shortcuts configuration section
///
/// Displays configurable keyboard shortcuts with:
/// - Inline recorder for setting shortcuts
/// - Reset to default button
/// - Accessibility permission warning when needed
struct ShortcutsSection: View {
    @State private var hasAccessibility = AXIsProcessTrusted()

    var body: some View {
        SettingsGroup(L("settings.section.shortcuts"), icon: "command.square.fill") {
            VStack(spacing: 0) {
                // Toggle Main Window Shortcut
                SettingsRowContainer {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("settings.shortcuts.toggleMainWindow"))
                                .fontWeight(.medium)
                            Text(L("settings.shortcuts.toggleMainWindow.subtitle"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        KeyboardShortcuts.Recorder(for: .toggleMainWindow)
                            .frame(width: 130)

                        Button {
                            KeyboardShortcuts.reset(.toggleMainWindow)
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help(L("settings.shortcuts.resetHelp"))
                    }
                }

                // Accessibility Permission Warning
                if !hasAccessibility {
                    SettingsDivider()

                    SettingsRowContainer {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("settings.shortcuts.accessibilityRequired"))
                                    .fontWeight(.medium)
                                Text(L("settings.shortcuts.accessibilityRequired.subtitle"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(L("settings.permissions.grantAccess")) {
                                promptAccessibility()
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .onAppear {
            hasAccessibility = AXIsProcessTrusted()
        }
    }

    /// Prompts user to grant accessibility permission
    private func promptAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
