import AppKit
import SwiftUI

/// Identifies which editor sheet to present (add vs. edit vs. preset add).
enum ManagedServiceEditorTarget: Identifiable {
    case add
    case edit(ManagedServiceConfig)
    case addPreset(ManagedServicePreset)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let config): return config.id.uuidString
        case .addPreset(let preset): return "preset:" + preset.id
        }
    }

    var config: ManagedServiceConfig? {
        if case .edit(let config) = self { return config }
        return nil
    }

    var preset: ManagedServicePreset? {
        if case .addPreset(let preset) = self { return preset }
        return nil
    }
}

/// Add/edit sheet for a local service profile.
///
/// Top of the form is a type picker: Custom Service (the original form,
/// byte-for-byte unchanged) or one of the six presets, which drives a
/// generated form from the preset definition (design sections 3, 5).
struct ManagedServiceEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let editingConfig: ManagedServiceConfig?
    /// Non-nil when the sheet opens straight into a preset (picker flow).
    let openingPreset: ManagedServicePreset?

    init(editingConfig: ManagedServiceConfig?, openingPreset: ManagedServicePreset? = nil) {
        self.editingConfig = editingConfig
        self.openingPreset = openingPreset
    }

    @State private var model = ManagedServiceEditorViewModel()
    @State private var dependencyStates: [String: DependencyProbeState] = [:]

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 0) {
            Text(L(model.titleKey))
                .font(.title2)
                .bold()
                .padding([.horizontal, .top], 20)

            Form {
                Picker(L("preset.picker.typeLabel"), selection: typeSelection) {
                    Text(L("preset.custom.title")).tag("")
                    ForEach(ManagedServicePresets.all, id: \.id) { preset in
                        Text(pickerTitle(for: preset)).tag(preset.id)
                    }
                }

                if let preset = model.preset {
                    Text(L(preset.summaryKey))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    presetDependencyBanner(for: preset)
                    presetWarnings(for: preset)
                    presetFields(for: preset)
                } else {
                    customFields
                }

                if let error = liveError {
                    Text(error.localizedDescription)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
                if let fieldError = model.invalidPresetField {
                    Text(L(errorKey(for: fieldError.error), L(fieldError.field.titleKey)))
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(L("service.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("service.save")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(liveError != nil || model.invalidPresetField != nil)
            }
            .padding(20)
        }
        .frame(width: 560, height: 540)
        .onAppear {
            if let openingPreset {
                model.beginPreset(openingPreset)
            } else if let config = editingConfig {
                model.beginEdit(config)
            } else {
                model.beginAdd()
            }
            refreshDependencyStates()
        }
        .onChange(of: model.presetID) {
            refreshDependencyStates()
        }
    }

    // MARK: - Type picker

    private var typeSelection: Binding<String> {
        Binding(
            get: { model.presetID ?? "" },
            set: { newValue in
                if newValue.isEmpty {
                    model.selectPreset(nil)
                } else if let preset = ManagedServicePresets.preset(withID: newValue) {
                    model.selectPreset(preset)
                }
            }
        )
    }

    private func pickerTitle(for preset: ManagedServicePreset) -> String {
        var title = L(preset.titleKey)
        if case .notInstalled = dependencyState(for: preset) {
            title += " — " + L("dependency.notInstalled")
        }
        return title
    }

    // MARK: - Custom form (unchanged)

    @ViewBuilder private var customFields: some View {
        @Bindable var model = model
        TextField(L("service.field.name"), text: $model.name)

        TextField(L("service.field.port"), text: $model.portText)

        TextField(L("service.field.host"), text: $model.host)

        LabeledContent(L("service.field.workingDirectory")) {
            HStack(spacing: 8) {
                TextField("", text: $model.workingDirectory)
                Button(L("service.field.chooseDirectory")) {
                    chooseDirectory(target: \.workingDirectory)
                }
            }
        }

        Section {
            TextField(L("service.field.startCommand"), text: $model.startCommand)
            Text(L("service.help.portPlaceholder"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(L("service.help.foreground"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(L("service.help.secrets"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Preset form

    @ViewBuilder private func presetDependencyBanner(for preset: ManagedServicePreset) -> some View {
        switch dependencyState(for: preset) {
        case .available(let path):
            AlertBanner(
                icon: "checkmark.circle",
                title: L("dependency.availableTitle"),
                message: L("dependency.available", path),
                tint: Theme.Colors.statusSuccess
            ) { EmptyView() }
        case .notInstalled:
            if let requirement = DependencyRequirement.requirement(forPresetID: preset.id) {
                AlertBanner(
                    icon: "exclamationmark.triangle",
                    title: L("dependency.notInstalledTitle", requirement.binaryName),
                    message: L(requirement.notInstalledKey),
                ) {
                    Button(L("dependency.viewInstallDocs")) {
                        openInstallDocuments(requirement)
                    }
                }
            }
        }
    }

    /// Preset warnings (design section 10.2): static keys, with mode-dependent
    /// refinement (a read-only Dufs share hides the writable warning) and a
    /// home-root scope warning for directory presets.
    @ViewBuilder private func presetWarnings(for preset: ManagedServicePreset) -> some View {
        let keys = preset.activeWarningKeys(
            fieldValues: model.fieldValues,
            homeDirectory: NSHomeDirectory()
        )
        ForEach(keys, id: \.self) { key in
            AlertBanner(
                icon: "exclamationmark.triangle",
                title: L(key),
                message: ""
            ) { EmptyView() }
        }
    }

    @ViewBuilder private func presetFields(for preset: ManagedServicePreset) -> some View {
        @Bindable var model = model
        TextField(L("service.field.name"), text: $model.name)
        TextField(L("service.field.port"), text: $model.portText)

        ForEach(preset.fields.filter { !$0.isAdvanced }, id: \.id) { field in
            presetFieldEditor(field: field, preset: preset)
        }

        let advanced = preset.fields.filter(\.isAdvanced)
        if !advanced.isEmpty {
            Section(L("preset.advanced")) {
                ForEach(advanced, id: \.id) { field in
                    presetFieldEditor(field: field, preset: preset)
                }
            }
        }
    }

    @ViewBuilder private func presetFieldEditor(field: PresetField, preset: ManagedServicePreset) -> some View {
        switch field.kind {
        case .directory:
            LabeledContent(L(field.titleKey)) {
                HStack(spacing: 8) {
                    Text(boundValue(field.id))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(boundValue(field.id).isEmpty ? .secondary : .primary)
                    Button(L("service.field.chooseDirectory")) {
                        chooseDirectoryField(field)
                    }
                }
            }
            if let helpKey = field.helpKey {
                Text(L(helpKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .singleSelect(let options):
            Picker(L(field.titleKey), selection: selectionBinding(field, options: options)) {
                ForEach(options, id: \.id) { option in
                    Text(L(option.titleKey)).tag(option.id)
                }
            }
            if let helpKey = field.helpKey {
                Text(L(helpKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        default:
            TextField(L(field.titleKey), text: textBinding(field))
            if let helpKey = field.helpKey {
                Text(L(helpKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Bindings

    private func boundValue(_ fieldID: String) -> String {
        model.fieldValues[fieldID] ?? ""
    }

    private func textBinding(_ field: PresetField) -> Binding<String> {
        Binding(
            get: { boundValue(field.id) },
            set: { model.fieldValues[field.id] = $0 }
        )
    }

    private func selectionBinding(_ field: PresetField, options: [PresetSelectOption]) -> Binding<String> {
        Binding(
            get: {
                let value = boundValue(field.id)
                return options.contains(where: { $0.id == value }) ? value : (options.first?.id ?? "")
            },
            set: { model.fieldValues[field.id] = $0 }
        )
    }

    // MARK: - Dependencies

    @State private var probe = PathDependencyProbe()

    private func dependencyState(for preset: ManagedServicePreset) -> DependencyProbeState {
        guard let requirement = DependencyRequirement.requirement(forPresetID: preset.id) else {
            return .available(path: "")
        }
        return dependencyStates[requirement.binaryName] ?? .notInstalled
    }

    private func refreshDependencyStates() {
        probe.recheck()
        for requirement in [DependencyRequirement.ssh, .python3, .dufs, .jupyter] {
            dependencyStates[requirement.binaryName] = probe.state(for: requirement)
        }
        // Hand the resolved executable path to the form model so preset
        // generation launches exactly the binary the probe reported.
        if let preset = model.preset,
           case .available(let path) = dependencyState(for: preset) {
            model.resolvedExecutablePath = path
        } else {
            model.resolvedExecutablePath = nil
        }
    }

    private func openInstallDocuments(_ requirement: DependencyRequirement) {
        guard let url = URL(string: requirement.installDocumentsURL) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Errors

    private func errorKey(for error: PresetFieldValueError) -> String {
        switch error {
        case .empty: return "preset.error.empty"
        case .notAnInteger: return "preset.error.notAnInteger"
        case .invalidCharacters: return "preset.error.invalidCharacters"
        case .outOfRange: return "preset.error.outOfRange"
        case .rootDirectory: return "preset.error.rootDirectory"
        }
    }

    // MARK: - Save

    /// Live validation result for the current draft; nil means Save is allowed.
    private var liveError: ManagedServiceValidationError? {
        model.liveValidationError(
            existing: appState.managedServiceManager.configs,
            directoryValidator: FileSystemWorkingDirectoryValidator()
        )
    }

    private func save() {
        guard liveError == nil, model.invalidPresetField == nil else { return }
        let config = model.draftConfig()
        Task {
            let error = editingConfig == nil
                ? await appState.addManagedService(config)
                : await appState.updateManagedService(config)
            guard error == nil else { return }
            dismiss()
        }
    }

    private func chooseDirectory(target: WritableKeyPath<ManagedServiceEditorViewModel, String>) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("service.field.chooseDirectory")
        if panel.runModal() == .OK, let url = panel.url {
            model[keyPath: target] = url.path
        }
    }

    private func chooseDirectoryField(_ field: PresetField) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("service.field.chooseDirectory")
        if panel.runModal() == .OK, let url = panel.url {
            model.fieldValues[field.id] = url.path
        }
    }
}
