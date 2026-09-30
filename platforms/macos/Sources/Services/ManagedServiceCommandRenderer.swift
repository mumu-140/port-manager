/**
 * ManagedServiceCommandRenderer.swift
 * PortKiller
 *
 * Pure validation and rendering for managed service start commands.
 *
 * The start command is user-authored shell input: only the exact {port}
 * placeholder is substituted, and nothing else is escaped or reconstructed
 * (design notes, sections 5.2 and 21).
 */

import Foundation

// MARK: - Rendering

/// Renders and inspects start commands without touching the process layer.
enum ManagedServiceCommandRenderer {
    /// The only supported template placeholder.
    static let portPlaceholder = "{port}"

    /// Returns brace-style placeholders other than {port}, in source order.
    static func unsupportedPlaceholders(in command: String) -> [String] {
        let pattern = #"\{([^{}]*)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = command as NSString
        var found: [String] = []
        for match in regex.matches(in: command, range: NSRange(location: 0, length: ns.length)) {
            let token = ns.substring(with: match.range)
            if token != portPlaceholder, !found.contains(token) {
                found.append(token)
            }
        }
        return found
    }

    /// Replaces every exact {port} occurrence with the decimal port number.
    static func render(_ command: String, port: Int) -> String {
        command.replacingOccurrences(of: portPlaceholder, with: String(port))
    }
}

// MARK: - Working directory validation

/// Injectable check for whether a working directory exists.
///
/// Injecting the check keeps profile validation pure and unit-testable.
protocol WorkingDirectoryValidating: Sendable {
    func isExistingDirectory(at path: String) -> Bool
}

/// Production validator backed by the file system.
struct FileSystemWorkingDirectoryValidator: WorkingDirectoryValidating {
    func isExistingDirectory(at path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}

// MARK: - Validation

/// Structured profile validation failures.
enum ManagedServiceValidationError: Error, Equatable, LocalizedError {
    case emptyName
    case duplicateName(String)
    case emptyHost
    case portOutOfRange(Int)
    case duplicatePort(Int)
    case missingWorkingDirectory(String)
    case emptyCommand
    case unsupportedPlaceholder(String)
    case serviceRunning

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return L("service.error.emptyName")
        case .duplicateName(let name):
            return L("service.error.duplicateName", name)
        case .emptyHost:
            return L("service.error.emptyHost")
        case .portOutOfRange(let port):
            return L("service.error.portRange", port)
        case .duplicatePort(let port):
            return L("service.error.duplicatePort", port)
        case .missingWorkingDirectory(let path):
            return L("service.error.missingDirectory", path)
        case .emptyCommand:
            return L("service.error.emptyCommand")
        case .unsupportedPlaceholder(let token):
            return L("service.error.unsupportedPlaceholder", token)
        case .serviceRunning:
            return L("service.error.running")
        }
    }
}

/// Validates managed service profiles before any process is touched.
enum ManagedServiceValidator {
    /// Returns the first validation failure, or nil when the profile is valid.
    ///
    /// - Parameters:
    ///   - config: Profile to validate.
    ///   - existing: All known profiles; the matching id is excluded so
    ///     editing a profile does not collide with itself.
    ///   - directoryValidator: Injectable working-directory check.
    static func validate(
        _ config: ManagedServiceConfig,
        existing: [ManagedServiceConfig],
        directoryValidator: WorkingDirectoryValidating = FileSystemWorkingDirectoryValidator()
    ) -> ManagedServiceValidationError? {
        let name = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .emptyName }

        let others = existing.filter { $0.id != config.id }
        let normalizedName = name.lowercased()
        if others.contains(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName
        }) {
            return .duplicateName(name)
        }

        guard (1...65535).contains(config.port) else { return .portOutOfRange(config.port) }
        if others.contains(where: { $0.port == config.port }) {
            return .duplicatePort(config.port)
        }

        guard !config.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .emptyHost
        }

        let command = config.startCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return .emptyCommand }
        if let placeholder = ManagedServiceCommandRenderer.unsupportedPlaceholders(in: command).first {
            return .unsupportedPlaceholder(placeholder)
        }

        let directory = config.workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard directoryValidator.isExistingDirectory(at: directory) else {
            return .missingWorkingDirectory(directory)
        }

        return nil
    }
}
