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
    /// user@host. IPv6 literals are deferred (v1 constrains forward targets
    /// to hostname/IPv4 so colon-concatenated forward specs stay parseable).
    case sshHost
    /// Digits only (ServerAliveInterval / ServerAliveCountMax — integers
    /// with their own semantics, deliberately not TCP-port bounded).
    case integer
    /// TCP port number: digits in 1...65535.
    case tcpPort
    /// Filesystem path: everything except double-quote, percent and newlines.
    case path
    /// Free text with no newlines (preset names and similar).
    case freeText
}

/// Structured field-validation failures.
enum PresetFieldValueError: Error, Equatable {
    case empty
    case notAnInteger
    case invalidCharacters
    /// Numeric value outside the field's semantic range (TCP ports).
    case outOfRange
    /// Directory field points at a filesystem root (Jupyter guard).
    case rootDirectory
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
    /// Absolute executable path the dependency probe resolved for this
    /// preset's binary, when available. Generators render this path (quoted)
    /// instead of the bare binary name so the command always executes the
    /// binary the probe reported as available — a fallback/known-path hit
    /// must not silently degrade to a bare name the shell may not resolve.
    let resolvedExecutablePath: String?

    init(
        id: UUID,
        name: String,
        port: Int,
        homeDirectory: String,
        resolvedExecutablePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.port = port
        self.homeDirectory = homeDirectory
        self.resolvedExecutablePath = resolvedExecutablePath
    }
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
    /// Whether the preset serves HTTP on {port}: gates the Open-in-browser
    /// action. SSH forwards are not HTTP services.
    var isHTTPService: Bool = false
    /// Whether the Cloudflare Quick Tunnel flow applies (HTTP services only).
    var supportsQuickTunnel: Bool = false
    /// Pure transformation from field values to a complete profile.
    let generate: @Sendable (PresetGenerationContext, [String: String]) -> ManagedServiceConfig

    /// Field values with every field's default applied.
    func defaultFieldValues() -> [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0.defaultValue) })
    }

    /// Validates one field's value against its charset and requiredness.
    /// Jupyter additionally rejects filesystem roots as the notebook
    /// directory: sharing \`/\` (or a Windows drive root) would publish the
    /// whole volume.
    func validate(field: PresetField, value: String) -> PresetFieldValueError? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return field.isRequired ? .empty : nil
        }
        if id == "jupyter-lab", field.kind == .directory, Self.isRootDirectory(trimmed) {
            return .rootDirectory
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

    /// True for filesystem roots that must never be shared as a Jupyter
    /// notebook directory: the POSIX root and Windows drive roots.
    /// Pure so both platforms' tests exercise the same rule.
    static func isRootDirectory(_ path: String) -> Bool {
        var normalized = path
        while normalized.count > 1 && (normalized.hasSuffix("/") || normalized.hasSuffix("\\")) {
            normalized.removeLast()
        }
        if normalized == "/" || normalized == "\\" { return true }
        let lowered = normalized.lowercased()
        // A Windows drive root ("C:\\") loses its backslash to the trim and
        // survives as "c:" — still a drive root, never a real directory.
        if lowered.count == 2, lowered.hasSuffix(":"),
           let first = lowered.first, first.isASCII, first.isLetter {
            return true
        }
        return false
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
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-@")
            return value.unicodeScalars.allSatisfy { allowed.contains($0) }
                ? nil : .invalidCharacters
        case .path:
            let forbidden = CharacterSet(charactersIn: "\"%").union(.newlines)
            return value.unicodeScalars.contains { forbidden.contains($0) }
                ? .invalidCharacters : nil
        case .tcpPort:
            guard value.allSatisfy(\.isNumber), let port = Int(value), (1...65535).contains(port) else {
                return .outOfRange
            }
            return nil
        case .freeText:
            return value.contains(where: { $0.isNewline }) ? .invalidCharacters : nil
        }
    }
}
