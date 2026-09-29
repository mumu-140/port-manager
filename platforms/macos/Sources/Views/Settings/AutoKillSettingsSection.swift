import SwiftUI
import Defaults

struct AutoKillSettingsSection: View {
    @Default(.autoKillRules) private var rules
    @State private var editingRule: AutoKillRule?
    @State private var isAddingRule = false

    var body: some View {
        SettingsGroup(L("settings.section.autoKill"), icon: "clock.badge.xmark") {
            VStack(spacing: 0) {
                SettingsRowContainer {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("settings.autoKill.header"))
                            .fontWeight(.medium)
                        Text(L("settings.autoKill.subtitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsDivider()

                if rules.isEmpty {
                    SettingsRowContainer {
                        HStack {
                            Text(L("settings.autoKill.noRules"))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(L("settings.autoKill.addRule")) {
                                isAddingRule = true
                            }
                            .controlSize(.small)
                        }
                    }
                } else {
                    ForEach(rules) { rule in
                        ruleRow(rule)
                        if rule.id != rules.last?.id {
                            SettingsDivider()
                        }
                    }

                    SettingsDivider()

                    SettingsRowContainer {
                        HStack {
                            Spacer()
                            Button(L("settings.autoKill.addRule")) {
                                isAddingRule = true
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isAddingRule) {
            AutoKillRuleEditor(rule: AutoKillRule(name: L("settings.autoKill.newRuleName"))) { newRule in
                rules.append(newRule)
            }
        }
        .sheet(item: $editingRule) { rule in
            AutoKillRuleEditor(rule: rule) { updated in
                if let index = rules.firstIndex(where: { $0.id == updated.id }) {
                    rules[index] = updated
                }
            }
        }
    }

    private func ruleRow(_ rule: AutoKillRule) -> some View {
        SettingsRowContainer {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        StatusDot(color: rule.isEnabled ? Theme.Colors.statusSuccess : .secondary)
                        Text(rule.name.isEmpty ? L("settings.autoKill.unnamedRule") : rule.name)
                            .fontWeight(.medium)
                    }
                    HStack(spacing: 8) {
                        if !rule.processPattern.isEmpty {
                            Text(L("settings.autoKill.rule.process", rule.processPattern))
                        }
                        if rule.port > 0 {
                            Text(L("settings.autoKill.rule.port", rule.port))
                        }
                        Text(L("settings.autoKill.rule.timeout", rule.timeoutMinutes))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        editingRule = rule
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)

                    Button {
                        rules.removeAll { $0.id == rule.id }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Rule Editor

struct AutoKillRuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: AutoKillRule
    let onSave: (AutoKillRule) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text(L("settings.autoKill.editTitle"))
                .font(.headline)
                .padding(.top, 20)

            Form {
                TextField(L("settings.autoKill.ruleName"), text: $rule.name)

                Section(L("settings.autoKill.matchCriteria")) {
                    TextField(L("settings.autoKill.processPattern"), text: $rule.processPattern)
                    TextField(L("settings.autoKill.portField"), value: $rule.port, format: .number)
                }

                Section(L("settings.autoKill.behavior")) {
                    Stepper(L("settings.autoKill.timeoutStepper", rule.timeoutMinutes), value: $rule.timeoutMinutes, in: 1...1440)
                    Toggle(L("settings.autoKill.notifyBeforeKill"), isOn: $rule.notifyBeforeKill)
                    Toggle(L("settings.autoKill.enabled"), isOn: $rule.isEnabled)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 280)

            // Actions
            HStack {
                Button(L("common.cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(L("common.save")) {
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rule.processPattern.isEmpty && rule.port == 0)
            }
            .padding(20)
        }
        .frame(width: 420)
    }
}
