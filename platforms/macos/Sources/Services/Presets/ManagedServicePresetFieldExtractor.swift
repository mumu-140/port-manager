import Foundation

/// Deterministic field extraction for re-opening the preset form from a
/// persisted profile (design section 4.1: presetID profiles "re-open the
/// preset form pre-filled").
///
/// The start command is app-generated and its structure is fixed per preset,
/// so parsing our own output is not intent guessing: every preset family has
/// one generated shape and this parser reverses exactly that shape.
/// Best effort: anything unparseable falls back to the field default.
enum ManagedServicePresetFieldExtractor {

    static func extractFieldValues(
        for preset: ManagedServicePreset,
        from config: ManagedServiceConfig,
        homeDirectory: String
    ) -> [String: String] {
        var values = preset.defaultFieldValues()
        let command = config.startCommand
        let tokens = command.split(separator: " ").map(String.init)

        switch preset.id {
        case "static-file-share", "dufs-file-share", "jupyter-lab":
            // File-share presets set workingDirectory to the shared directory.
            values["directory"] = config.workingDirectory
            if preset.id == "dufs-file-share" {
                values["mode"] = dufsMode(command: command) ?? values["mode"]
            }

        case "ssh-local-forward":
            if let spec = forwardSpec(command: command, flag: "-L", localIsFirst: true) {
                values["remoteHost"] = spec.host
                values["remotePort"] = spec.remotePort
            }
            applySSHTail(tokens: tokens, to: &values)

        case "ssh-socks5-proxy":
            applySSHTail(tokens: tokens, to: &values)

        default:
            break
        }
        return values
    }

    // MARK: - Parsers

    /// -L 127.0.0.1:{port}:<host>:<remotePort> (localIsFirst). Legacy
    /// profiles saved before the explicit loopback bind (-L {port}:<host>:<remotePort>)
    /// still parse so re-editing them keeps their values.
    private static func forwardSpec(command: String, flag: String, localIsFirst: Bool) -> (host: String, remotePort: String)? {
        let tokens = command.split(separator: " ").map(String.init)
        for (index, token) in tokens.enumerated() where token == flag {
            guard index + 1 < tokens.count else { continue }
            let parts = tokens[index + 1].split(separator: ":").map(String.init)
            if localIsFirst {
                if parts.count == 4, parts[0] == "127.0.0.1" {
                    return (host: parts[2], remotePort: parts[3])
                }
                if parts.count == 3 {
                    return (host: parts[1], remotePort: parts[2])
                }
                continue
            } else {
                continue
            }
        }
        return nil
    }

    /// sshHost is the final token of every generated SSH command; keepalive
    /// values come from their fixed -o options. The first token may be a
    /// quoted absolute executable path (dependency-resolved generation), so
    /// the guard matches on its basename. Only runs on the generated shape
    /// (ssh ... with a forward flag); anything else keeps the defaults.
    private static func applySSHTail(tokens: [String], to values: inout [String: String]) {
        guard let firstToken = tokens.first,
              (shellSingleUnquote(firstToken) as NSString).lastPathComponent == "ssh",
              tokens.contains(where: { $0 == "-L" || $0 == "-D" }),
              let hostIndex = tokens.lastIndex(where: { !$0.hasPrefix("-") && !$0.contains(":") }) else { return }
        values["sshHost"] = shellSingleUnquote(tokens[hostIndex])

        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            guard token == "-o", index + 1 < tokens.count else {
                index += 1
                continue
            }
            let option = tokens[index + 1]
            if option.hasPrefix("ServerAliveInterval=") {
                values["keepaliveInterval"] = String(option.dropFirst("ServerAliveInterval=".count))
            } else if option.hasPrefix("ServerAliveCountMax=") {
                values["keepaliveCount"] = String(option.dropFirst("ServerAliveCountMax=".count))
            }
            index += 2
        }
    }

    /// dufs permission flags → mode id (generator order: upload then delete).
    private static func dufsMode(command: String) -> String? {
        if command.contains("--allow-delete") { return "read-write" }
        if command.contains("--allow-upload") { return "upload" }
        return command.contains("--port") ? "read-only" : nil
    }

    /// Reverses ManagedServicePresetCommandRenderer.shellSingleQuoted:
    /// strip the outer quotes and turn the '\'' escape back into a quote.
    private static func shellSingleUnquote(_ value: String) -> String {
        guard value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 else { return value }
        let inner = value.dropFirst().dropLast()
        return String(inner).replacingOccurrences(of: "'\\''", with: "'")
    }
}
