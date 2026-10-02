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

        case "ssh-reverse-forward":
            // -R <remoteBind>:<remotePort>:127.0.0.1:{port}
            if let spec = forwardSpec(command: command, flag: "-R", localIsFirst: false) {
                values["remoteBind"] = spec.host
                values["remotePort"] = spec.remotePort
            }
            applySSHTail(tokens: tokens, to: &values)

        default:
            break
        }
        return values
    }

    // MARK: - Parsers

    /// -L {port}:<host>:<remotePort> (localIsFirst) or
    /// -R <bind>:<remotePort>:127.0.0.1:{port} (localIsFirst = false).
    private static func forwardSpec(command: String, flag: String, localIsFirst: Bool) -> (host: String, remotePort: String)? {
        let tokens = command.split(separator: " ").map(String.init)
        for (index, token) in tokens.enumerated() where token == flag {
            guard index + 1 < tokens.count else { continue }
            let parts = tokens[index + 1].split(separator: ":").map(String.init)
            if localIsFirst {
                guard parts.count == 3 else { continue }
                return (host: parts[1], remotePort: parts[2])
            } else {
                guard parts.count == 4 else { continue }
                return (host: parts[0], remotePort: parts[1])
            }
        }
        return nil
    }

    /// sshHost is the final token of every generated SSH command; keepalive
    /// values come from their fixed -o options; everything else that is
    /// option-shaped and not one of the fixed flags is the user extraOptions.
    /// Only runs on the generated shape (ssh ... with a forward flag);
    /// anything else keeps the defaults.
    private static func applySSHTail(tokens: [String], to values: inout [String: String]) {
        guard tokens.first == "ssh",
              tokens.contains(where: { $0 == "-L" || $0 == "-D" || $0 == "-R" }),
              let hostIndex = tokens.lastIndex(where: { !$0.hasPrefix("-") && !$0.contains(":") }) else { return }
        values["sshHost"] = shellSingleUnquote(tokens[hostIndex])

        var extras: [String] = []
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
            } else if option != "ExitOnForwardFailure=yes" {
                extras.append(token + " " + option)
            }
            index += 2
        }
        if !extras.isEmpty {
            values["extraOptions"] = extras.joined(separator: " ")
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
