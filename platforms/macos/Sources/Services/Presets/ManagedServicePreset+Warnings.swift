import Foundation

extension ManagedServicePreset {
    /// Warnings that apply right now given the current field values (design
    /// section 10.2). Static warningKeys minus the GatewayPorts warning while
    /// the SSH reverse remote bind is still 127.0.0.1, plus the serving-scope
    /// home-root warning when a directory field points at the home directory
    /// itself.
    func activeWarningKeys(fieldValues: [String: String], homeDirectory: String) -> [String] {
        var keys = warningKeys
        if id == "ssh-reverse-forward" {
            let remoteBind = fieldValues["remoteBind"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "127.0.0.1"
            if remoteBind == "127.0.0.1" {
                keys.removeAll { $0 == "preset.ssh-reverse-forward.warning.gatewayports" }
            }
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
