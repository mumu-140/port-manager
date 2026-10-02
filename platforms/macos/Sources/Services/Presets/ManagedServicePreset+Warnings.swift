import Foundation

extension ManagedServicePreset {
    /// Warnings that apply right now given the current field values (design
    /// section 10.2). Static warningKeys with mode-dependent refinement — a
    /// read-only Dufs share is not writable, so the writable warning does
    /// not apply — plus the serving-scope home-root warning when a directory
    /// field points at the home directory itself.
    func activeWarningKeys(fieldValues: [String: String], homeDirectory: String) -> [String] {
        var keys = warningKeys
        if id == "dufs-file-share",
           (fieldValues["mode"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "read-only") == "read-only" {
            keys.removeAll { $0 == "preset.dufs-file-share.warning.writable" }
        }
        if fields.contains(where: { $0.kind == .directory }),
           let directory = fieldValues["directory"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !directory.isEmpty,
           Self.isHomeRoot(directory, homeDirectory: homeDirectory) {
            keys.append("preset.file-share.warning.homeRoot")
        }
        return keys
    }

    /// Treats the home root with or without a trailing slash as the same
    /// location; deeper paths never match.
    private static func isHomeRoot(_ directory: String, homeDirectory: String) -> Bool {
        func trimmed(_ path: String) -> String {
            var value = path
            while value.count > 1 && value.hasSuffix("/") { value.removeLast() }
            return value
        }
        return trimmed(directory) == trimmed(homeDirectory)
    }
}
