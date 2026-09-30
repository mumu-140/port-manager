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

    /// Memoized working-directory stat, keyed by the current path text.
    @ObservationIgnored private var directoryCheckCache: (path: String, isValid: Bool)?

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

    /// Inline validation for the editor, recomputed on every field change so
    /// Save can be disabled before it is ever clicked.
    ///
    /// Pure field checks run on every call; the working-directory check is a
    /// file-system stat memoized per path, so typing the name, port, host or
    /// command never repeats it (design notes, section 16.10).
    func liveValidationError(
        existing: [ManagedServiceConfig],
        directoryValidator: WorkingDirectoryValidating
    ) -> ManagedServiceValidationError? {
        let config = draftConfig()
        let directory = config.workingDirectory
        let directoryIsValid: Bool
        if let cached = directoryCheckCache, cached.path == directory {
            directoryIsValid = cached.isValid
        } else {
            directoryIsValid = directoryValidator.isExistingDirectory(at: directory)
            directoryCheckCache = (path: directory, isValid: directoryIsValid)
        }
        return ManagedServiceValidator.validate(
            config,
            existing: existing,
            directoryValidator: FixedWorkingDirectoryValidator(isValid: directoryIsValid)
        )
    }
}

/// Directory validator that reports a result computed once by the caller.
private struct FixedWorkingDirectoryValidator: WorkingDirectoryValidating {
    let isValid: Bool

    func isExistingDirectory(at path: String) -> Bool { isValid }
}
