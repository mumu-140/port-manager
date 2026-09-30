import AppKit
import SwiftUI

/// Identifies which editor sheet to present (add vs. edit).
enum ManagedServiceEditorTarget: Identifiable {
    case add
    case edit(ManagedServiceConfig)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let config): return config.id.uuidString
        }
    }

    var config: ManagedServiceConfig? {
        if case .edit(let config) = self { return config }
        return nil
    }
}

/// Add/edit sheet for a local service profile.
struct ManagedServiceEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let editingConfig: ManagedServiceConfig?

    @State private var model = ManagedServiceEditorViewModel()

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 0) {
            Text(L(model.titleKey))
                .font(.title2)
                .bold()
                .padding([.horizontal, .top], 20)

            Form {
                TextField(L("service.field.name"), text: $model.name)

                TextField(L("service.field.port"), text: $model.portText)

                TextField(L("service.field.host"), text: $model.host)

                LabeledContent(L("service.field.workingDirectory")) {
                    HStack(spacing: 8) {
                        TextField("", text: $model.workingDirectory)
                        Button(L("service.field.chooseDirectory")) {
                            chooseDirectory()
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

                if let error = liveError {
                    Text(error.localizedDescription)
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
                    .disabled(liveError != nil)
            }
            .padding(20)
        }
        .frame(width: 540, height: 520)
        .onAppear {
            if let config = editingConfig {
                model.beginEdit(config)
            } else {
                model.beginAdd()
            }
        }
    }

    /// Live validation result for the current draft; nil means Save is allowed.
    private var liveError: ManagedServiceValidationError? {
        model.liveValidationError(
            existing: appState.managedServiceManager.configs,
            directoryValidator: FileSystemWorkingDirectoryValidator()
        )
    }

    private func save() {
        guard liveError == nil else { return }
        let config = model.draftConfig()
        Task {
            let error = editingConfig == nil
                ? await appState.addManagedService(config)
                : await appState.updateManagedService(config)
            guard error == nil else { return }
            dismiss()
        }
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("service.field.chooseDirectory")
        if panel.runModal() == .OK, let url = panel.url {
            model.workingDirectory = url.path
        }
    }
}
