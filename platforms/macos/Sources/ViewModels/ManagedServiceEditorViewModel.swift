import Foundation
import Observation

/**
 * Editor form model backing the managed service add/edit sheet.
 *
 * Deliberately not actor-isolated so it can be created as SwiftUI state and
 * unit-tested without a main actor hop; validation delegates to the pure
 * `ManagedServiceValidator`.
 */
@Observable
final class ManagedServiceEditorViewModel {

    var name: String = ""
    var portText: String = ""
    var host: String = "localhost"
    var workingDirectory: String = ""
    var startCommand: String = ""

    private(set) var validationError: ManagedServiceValidationError?
    private(set) var editingID: UUID?

    var isEditing: Bool { editingID != nil }

    var titleKey: String {
        isEditing ? "service.editor.editTitle" : "service.editor.addTitle"
    }

    var parsedPort: Int {
        Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    func beginAdd() {
        editingID = nil
        name = ""
        portText = ""
        host = "localhost"
        workingDirectory = ""
        startCommand = ""
        validationError = nil
    }

    func beginEdit(_ config: ManagedServiceConfig) {
        editingID = config.id
        name = config.name
        portText = String(config.port)
        host = config.host
        workingDirectory = config.workingDirectory
        startCommand = config.startCommand
        validationError = nil
    }

    /// Builds a trimmed draft config; the port falls back to 0 so validation
    /// reports a range error for non-numeric input.
    func draftConfig() -> ManagedServiceConfig {
        ManagedServiceConfig(
            id: editingID ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            port: parsedPort,
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            workingDirectory: workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines),
            startCommand: startCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    @discardableResult
    func validate(
        existing: [ManagedServiceConfig],
        directoryValidator: WorkingDirectoryValidating
    ) -> ManagedServiceValidationError? {
        let error = ManagedServiceValidator.validate(
            draftConfig(),
            existing: existing,
            directoryValidator: directoryValidator
        )
        validationError = error
        return error
    }
}
