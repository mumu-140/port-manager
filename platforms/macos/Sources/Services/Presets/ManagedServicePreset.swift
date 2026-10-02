/**
 * ManagedServicePreset.swift
 * PortKiller
 *
 * Static, code-level preset definitions that generate ordinary
 * \`ManagedServiceConfig\` profiles (design: presets-exposure, sections 2 and 4).
 *
 * A preset is metadata plus a pure generator. Presets are never persisted as
 * objects and never bypass the existing validator or manager: the generated
 * profile flows through \`ManagedServiceValidator\` exactly like a hand-written
 * one. Only the resulting profile (plus its \`presetID\` marker) is persisted.
 *
 * Security model (design section 10): the app composes start commands from
 * user-controlled field values, so the app owns safe rendering. On macOS every
 * variable value is POSIX-single-quote escaped; field charsets additionally
 * constrain what users can type. The custom-service editor is NOT a preset and
 * keeps its "user-authored shell, nothing escaped" contract.
 */

import Foundation

// MARK: - Categories

/// Coarse grouping used by the picker UI.
enum PresetCategory: String, Sendable, CaseIterable {
    case general
    case fileShare
    case tunnel
    case notebook
}

// MARK: - Field descriptors

/// How the editor renders one preset field.
enum PresetFieldKind: Sendable, Equatable {
    /// Free-form single-line text.
    case text
    /// TCP port (digits only).
    case port
    /// Existing-directory chooser.
    case directory
    /// Fixed set of choices.
    case singleSelect(options: [PresetSelectOption])
}

/// One choice inside a \`singleSelect\` field.
struct PresetSelectOption: Sendable, Equatable {
    /// Stable value written into the field values dictionary.
    let id: String
    /// Localization key for the human-readable label.
    let titleKey: String
}

/// One editable field of a preset form.
struct PresetField: Identifiable, Sendable, Equatable {
    /// Stable key inside the field-values dictionary.
    let id: String
    /// Localization key for the label.
    let titleKey: String
    /// Localization key for the helper caption, if any.
    let helpKey: String?
    let kind: PresetFieldKind
    /// Character allow-list applied to typed values.
    let charset: PresetFieldCharset
    let defaultValue: String
    let isRequired: Bool
    /// Advanced fields render collapsed under a disclosure group.
    let isAdvanced: Bool

    init(
        id: String,
        titleKey: String,
        helpKey: String? = nil,
        kind: PresetFieldKind = .text,
        charset: PresetFieldCharset,
        defaultValue: String = "",
        isRequired: Bool = false,
        isAdvanced: Bool = false
    ) {
        self.id = id
        self.titleKey = titleKey
        self.helpKey = helpKey
        self.kind = kind
        self.charset = charset
        self.defaultValue = defaultValue
        self.isRequired = isRequired
        self.isAdvanced = isAdvanced
    }
}

// MARK: - Character sets

/// Per-field character allow-lists (design: presets-exposure, section 10.1).
///
/// This is the "constrain" half of constrain-and-quote: instead of escaping
/// hostile characters after the fact, fields reject the characters that would
/// need escaping in the first place. Newlines are rejected everywhere because
/// the start command is single-line.
enum PresetFieldCharset: Sendable, Equatable {
    /// SSH host or alias: letters, digits, dot, dash, underscore, plus
    /// user@host and IPv6 colons.
    case sshHost
    /// Digits only (ports, intervals).
    case integer
    /// Filesystem path: everything except double-quote, percent and newlines.
    case path
    /// Extra SSH options: a conservative flag-list character set with no
    /// shell metacharacters at all.
    case sshExtraOptions
    /// Free text with no newlines (preset names and similar).
    case freeText
}

/// Structured field-validation failures.
enum PresetFieldValueError: Error, Equatable {
    case empty
    case notAnInteger
    case invalidCharacters
}

// MARK: - Preset definition

/// Context the editor supplies around preset fields.
struct PresetGenerationContext: Sendable {
    /// Identifier for the generated profile.
    let id: UUID
    /// User-edited profile name.
    let name: String
    /// User-edited service port (the \`{port}\` placeholder target).
    let port: Int
    /// Platform home directory, used as the working directory for presets
    /// that have no natural one (SSH forwards).
    let homeDirectory: String
}

/// A static service preset: metadata + ordered form fields + pure generator.
struct ManagedServicePreset: Identifiable, Sendable {
    /// Stable identifier persisted as \`ManagedServiceConfig.presetID\`.
    let id: String
    /// Localization key for the picker title.
    let titleKey: String
    /// Localization key for the one-line picker description.
    let summaryKey: String
    /// SF Symbol name shown in the picker.
    let icon: String
    let category: PresetCategory
    /// Binary name to probe for availability (design section 9); nil when the
    /// preset has no external dependency.
    let dependencyBinary: String?
    let fields: [PresetField]
    /// Suggested port for the editor's port field; nil keeps the existing
    /// editor default.
    let suggestedPort: Int?
    /// Localization keys for preset-level warning captions shown in the form.
    let warningKeys: [String]
    /// Pure transformation from field values to a complete profile.
    let generate: @Sendable (PresetGenerationContext, [String: String]) -> ManagedServiceConfig

    /// Field values with every field's default applied.
    func defaultFieldValues() -> [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0.defaultValue) })
    }

    /// Validates one field's value against its charset and requiredness.
    func validate(field: PresetField, value: String) -> PresetFieldValueError? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return field.isRequired ? .empty : nil
        }
        return field.charset.validate(trimmed)
    }

    /// Validates every field; returns the first failing field id.
    func firstInvalidField(in values: [String: String]) -> String? {
        for field in fields {
            if validate(field: field, value: values[field.id] ?? "") != nil {
                return field.id
            }
        }
        return nil
    }
}

// MARK: - Charset validation

extension PresetFieldCharset {
    /// Returns nil when the value satisfies this charset.
    func validate(_ value: String) -> PresetFieldValueError? {
        switch self {
        case .integer:
            return value.allSatisfy(\.isNumber) ? nil : .notAnInteger
        case .sshHost:
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-@:")
            return value.unicodeScalars.allSatisfy { allowed.contains($0) }
                ? nil : .invalidCharacters
        case .path:
            let forbidden = CharacterSet(charactersIn: "\"%").union(.newlines)
            return value.unicodeScalars.contains { forbidden.contains($0) }
                ? .invalidCharacters : nil
        case .sshExtraOptions:
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 =:._/-")
            return value.unicodeScalars.allSatisfy { allowed.contains($0) }
                ? nil : .invalidCharacters
        case .freeText:
            return value.contains(where: { $0.isNewline }) ? .invalidCharacters : nil
        }
    }
}
