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

    /// Preset mode: non-nil while the form is driven by a preset definition
    /// (design section 4.1). nil is the custom editor. Observable on purpose:
    /// the picker binding, the whole preset form, warnings and Save state
    /// read it, so switching presets must be observed.
    private(set) var presetID: String?

    /// Live preset field values, keyed by field id. Observable: every field
    /// binding, the warning banner, invalid-field captions and the Save
    /// button track it.
    var fieldValues: [String: String] = [:]

    /// Executable path the dependency probe resolved for the current preset,
    /// injected by the editor view after its probe refresh. Generation-only
    /// input: nothing renders from it, so observation is unnecessary.
    @ObservationIgnored var resolvedExecutablePath: String?

    /// Memoized working-directory stat, keyed by the current path text.
    @ObservationIgnored private var directoryCheckCache: (path: String, isValid: Bool)?

    var isEditing: Bool { editingID != nil }

    /// Resolved preset definition for the current mode; nil in custom mode and
    /// for unknown preset IDs (which degrade to custom editing, design section 4.1).
    var preset: ManagedServicePreset? {
        guard let presetID else { return nil }
        return ManagedServicePresets.preset(withID: presetID)
    }

    /// The first preset field whose value fails validation, if any.
    var invalidPresetField: (field: PresetField, error: PresetFieldValueError)? {
        guard let preset else { return nil }
        for field in preset.fields {
            if let error = preset.validate(field: field, value: fieldValues[field.id] ?? "") {
                return (field, error)
            }
        }
        return nil
    }

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
        presetID = nil
        fieldValues = [:]
        resolvedExecutablePath = nil
    }

    /// Begins add mode driven by a preset: fields prefill with defaults, the
    /// port prefills with the preset's suggestion.
    func beginPreset(_ preset: ManagedServicePreset) {
        editingID = nil
        presetID = preset.id
        fieldValues = preset.defaultFieldValues()
        name = ""
        portText = preset.suggestedPort.map(String.init) ?? ""
        host = "localhost"
        workingDirectory = ""
        startCommand = ""
        validationError = nil
        resolvedExecutablePath = nil
    }

    func beginEdit(_ config: ManagedServiceConfig) {
        editingID = config.id
        name = config.name
        portText = String(config.port)
        host = config.host
        workingDirectory = config.workingDirectory
        startCommand = config.startCommand
        validationError = nil
        presetID = config.presetID
        // Only known preset IDs re-open the preset form; unknown IDs degrade
        // to custom editing (design section 4.1, no migration).
        if let preset {
            fieldValues = ManagedServicePresetFieldExtractor.extractFieldValues(
                for: preset,
                from: config,
                homeDirectory: NSHomeDirectory()
            )
        } else {
            presetID = nil
            fieldValues = [:]
        }
    }

    /// Mode switch from the editor's picker. Moving to custom keeps the user's
    /// work: name/port/host/directory stay, and the start command becomes the
    /// current draft's generated command. Moving to a preset resets fields to
    /// that preset's defaults, carrying the directory over when it applies.
    func selectPreset(_ preset: ManagedServicePreset?) {
        let currentDraft = draftConfig()
        if let preset {
            presetID = preset.id
            fieldValues = preset.defaultFieldValues()
            if preset.fields.contains(where: { $0.kind == .directory }) {
                fieldValues["directory"] = currentDraft.workingDirectory
            }
            if preset.suggestedPort != nil && !isEditing {
                portText = preset.suggestedPort.map(String.init) ?? portText
            }
        } else {
            presetID = nil
            fieldValues = [:]
            startCommand = currentDraft.startCommand
            if currentDraft.workingDirectory != NSHomeDirectory() {
                workingDirectory = currentDraft.workingDirectory
            }
        }
    }

    /// Builds a trimmed draft config; the port falls back to 0 so validation
    /// reports a range error for non-numeric input.
    ///
    /// In preset mode the draft is produced by the preset's pure generator
    /// (design section 4.2) and carries the preset ID marker; custom mode is
    /// unchanged.
    func draftConfig() -> ManagedServiceConfig {
        if let preset {
            return preset.generate(
                PresetGenerationContext(
                    id: editingID ?? UUID(),
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    port: parsedPort,
                    homeDirectory: NSHomeDirectory(),
                    resolvedExecutablePath: resolvedExecutablePath
                ),
                fieldValues
            )
        }
        return ManagedServiceConfig(
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
