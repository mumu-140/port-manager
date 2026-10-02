/**
 * ManagedServicePresets.swift
 * PortKiller
 *
 * The concrete v1 preset definitions and the registry (design:
 * presets-exposure, section 2). Every generator is a pure function from field
 * values to a complete profile; the resulting profile still passes through
 * \`ManagedServiceValidator\` before it can be saved.
 *
 * Fixed invariants rendered by every listening preset:
 * - loopback binding is explicit (python and dufs default to all interfaces);
 * - SSH forwards always carry -N and ExitOnForwardFailure=yes;
 * - Jupyter always carries --no-browser, --ip 127.0.0.1 and --port-retries=0
 *   so a busy port surfaces as a Conflict instead of a silent port move;
 * - the \`{port}\` placeholder is preserved so future port edits follow.
 *
 * The Custom Service picker entry is the existing editor, not a preset: it is
 * hardcoded in the picker UI and its profiles keep \`presetID == nil\`.
 */

import Foundation

// MARK: - Localization keys

/// Builds a field key: "preset.<presetID>.field.<fieldID>".
private func presetFieldKey(_ presetID: String, _ fieldID: String) -> String {
    "preset.\(presetID).field.\(fieldID)"
}

// MARK: - Registry

enum ManagedServicePresets {
    /// All v1 presets in picker order (Custom Service is prepended by the UI).
    static let all: [ManagedServicePreset] = [
        staticFileShare,
        sshLocalForward,
        sshSocks5Proxy,
        dufsFileShare,
        jupyterLab,
    ]

    /// Looks a preset up by its persisted ID; nil for custom/unknown IDs.
    static func preset(withID id: String) -> ManagedServicePreset? {
        all.first { $0.id == id }
    }
}

// MARK: - Static File Share

extension ManagedServicePresets {
    static let staticFileShare = ManagedServicePreset(
        id: "static-file-share",
        titleKey: "preset.static-file-share.title",
        summaryKey: "preset.static-file-share.summary",
        icon: "folder",
        category: .fileShare,
        dependencyBinary: "python3",
        fields: [
            PresetField(
                id: "directory",
                titleKey: presetFieldKey("static-file-share", "directory"),
                helpKey: presetFieldKey("static-file-share", "directory.help"),
                kind: .directory,
                charset: .path,
                defaultValue: "",
                isRequired: true
            ),
        ],
        suggestedPort: 8123,
        warningKeys: [
            "preset.static-file-share.warning.listing",
            "preset.static-file-share.warning.symlinks",
        ],
        isHTTPService: true,
        supportsQuickTunnel: true,
        generate: { context, fields in
            let directory = fields["directory"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let executable = context.resolvedExecutablePath.map { ManagedServicePresetCommandRenderer.shellSingleQuoted($0) } ?? "python3"
            let command = "\(executable) -m http.server {port} --bind 127.0.0.1 --directory "
                + ManagedServicePresetCommandRenderer.shellSingleQuoted(directory)
            return ManagedServiceConfig(
                id: context.id,
                name: context.name,
                port: context.port,
                host: "localhost",
                workingDirectory: directory,
                startCommand: command,
                presetID: "static-file-share"
            )
        }
    )
}

// MARK: - SSH family

extension ManagedServicePresets {
    private static let sshExitOnForwardFailure = "-o ExitOnForwardFailure=yes"

    /// Renders the shared keepalive tail shared by the SSH presets. ExitOnForwardFailure makes bind failures fail fast (Failed
    /// state) instead of idling; ServerAlive* detects dead connections through
    /// the encrypted channel.
    private static func sshOptionsTail(_ fields: [String: String]) -> String {
        let interval = fields["keepaliveInterval"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "15"
        let count = fields["keepaliveCount"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "3"
        return " -o ServerAliveInterval=\(interval) -o ServerAliveCountMax=\(count)"
    }

    /// SSH host field shared by both SSH presets.
    private static let sshHostField = PresetField(
        id: "sshHost",
        titleKey: presetFieldKey("ssh", "host"),
        helpKey: presetFieldKey("ssh", "host.help"),
        kind: .text,
        charset: .sshHost,
        defaultValue: "",
        isRequired: true
    )

    private static let keepaliveIntervalField = PresetField(
        id: "keepaliveInterval",
        titleKey: presetFieldKey("ssh", "keepaliveInterval"),
        helpKey: presetFieldKey("ssh", "keepaliveInterval.help"),
        kind: .port,
        charset: .integer,
        defaultValue: "15",
        isAdvanced: true
    )

    private static let keepaliveCountField = PresetField(
        id: "keepaliveCount",
        titleKey: presetFieldKey("ssh", "keepaliveCount"),
        kind: .port,
        charset: .integer,
        defaultValue: "3",
        isAdvanced: true
    )

    static let sshLocalForward = ManagedServicePreset(
        id: "ssh-local-forward",
        titleKey: "preset.ssh-local-forward.title",
        summaryKey: "preset.ssh-local-forward.summary",
        icon: "arrow.down.forward",
        category: .tunnel,
        dependencyBinary: "ssh",
        fields: [
            sshHostField,
            PresetField(
                id: "remoteHost",
                titleKey: presetFieldKey("ssh", "remoteHost"),
                helpKey: presetFieldKey("ssh", "remoteHost.help"),
                kind: .text,
                charset: .sshHost,
                defaultValue: "127.0.0.1",
                isRequired: true,
                isAdvanced: true
            ),
            PresetField(
                id: "remotePort",
                titleKey: presetFieldKey("ssh", "remotePort"),
                kind: .port,
                charset: .tcpPort,
                defaultValue: "",
                isRequired: true
            ),
            keepaliveIntervalField,
            keepaliveCountField,
        ],
        suggestedPort: nil,
        warningKeys: [],
        generate: { context, fields in
            let host = fields["sshHost"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let remoteHost = fields["remoteHost"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "127.0.0.1"
            let remotePort = fields["remotePort"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // The listener bind is spelled out: it must never depend on the
            // user's ssh_config GatewayPorts settings.
            let executable = context.resolvedExecutablePath.map { ManagedServicePresetCommandRenderer.shellSingleQuoted($0) } ?? "ssh"
            let command = "\(executable) -N -L 127.0.0.1:{port}:\(remoteHost):\(remotePort) \(sshExitOnForwardFailure)\(sshOptionsTail(fields)) "
                + ManagedServicePresetCommandRenderer.shellSingleQuoted(host)
            return ManagedServiceConfig(
                id: context.id,
                name: context.name,
                port: context.port,
                host: "localhost",
                workingDirectory: context.homeDirectory,
                startCommand: command,
                presetID: "ssh-local-forward"
            )
        }
    )

    static let sshSocks5Proxy = ManagedServicePreset(
        id: "ssh-socks5-proxy",
        titleKey: "preset.ssh-socks5-proxy.title",
        summaryKey: "preset.ssh-socks5-proxy.summary",
        icon: "globe",
        category: .tunnel,
        dependencyBinary: "ssh",
        fields: [
            sshHostField,
            keepaliveIntervalField,
            keepaliveCountField,
        ],
        suggestedPort: nil,
        warningKeys: [],
        generate: { context, fields in
            let host = fields["sshHost"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let executable = context.resolvedExecutablePath.map { ManagedServicePresetCommandRenderer.shellSingleQuoted($0) } ?? "ssh"
            let command = "\(executable) -N -D 127.0.0.1:{port} \(sshExitOnForwardFailure)\(sshOptionsTail(fields)) "
                + ManagedServicePresetCommandRenderer.shellSingleQuoted(host)
            return ManagedServiceConfig(
                id: context.id,
                name: context.name,
                port: context.port,
                host: "localhost",
                workingDirectory: context.homeDirectory,
                startCommand: command,
                presetID: "ssh-socks5-proxy"
            )
        }
    )
}

// MARK: - Dufs

extension ManagedServicePresets {
    private static let dufsModeField = PresetField(
        id: "mode",
        titleKey: presetFieldKey("dufs-file-share", "mode"),
        helpKey: presetFieldKey("dufs-file-share", "mode.help"),
        kind: .singleSelect(options: [
            PresetSelectOption(id: "read-only", titleKey: "preset.dufs-file-share.mode.readOnly"),
            PresetSelectOption(id: "upload", titleKey: "preset.dufs-file-share.mode.upload"),
            PresetSelectOption(id: "read-write", titleKey: "preset.dufs-file-share.mode.readWrite"),
        ]),
        charset: .freeText,
        defaultValue: "read-only"
    )

    static let dufsFileShare = ManagedServicePreset(
        id: "dufs-file-share",
        titleKey: "preset.dufs-file-share.title",
        summaryKey: "preset.dufs-file-share.summary",
        icon: "externaldrive",
        category: .fileShare,
        dependencyBinary: "dufs",
        fields: [
            PresetField(
                id: "directory",
                titleKey: presetFieldKey("dufs-file-share", "directory"),
                kind: .directory,
                charset: .path,
                defaultValue: "",
                isRequired: true
            ),
            dufsModeField,
        ],
        suggestedPort: 5000,
        warningKeys: [
            "preset.dufs-file-share.warning.noAuth",
            "preset.dufs-file-share.warning.writable",
        ],
        isHTTPService: true,
        supportsQuickTunnel: true,
        generate: { context, fields in
            let directory = fields["directory"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let mode = fields["mode"] ?? "read-only"
            var flags = "--port {port} --bind 127.0.0.1"
            if mode == "upload" || mode == "read-write" {
                flags += " --allow-upload"
            }
            if mode == "read-write" {
                flags += " --allow-delete"
            }
            let executable = context.resolvedExecutablePath.map { ManagedServicePresetCommandRenderer.shellSingleQuoted($0) } ?? "dufs"
            let command = "\(executable) \(flags) "
                + ManagedServicePresetCommandRenderer.shellSingleQuoted(directory)
            return ManagedServiceConfig(
                id: context.id,
                name: context.name,
                port: context.port,
                host: "localhost",
                workingDirectory: directory,
                startCommand: command,
                presetID: "dufs-file-share"
            )
        }
    )
}

// MARK: - Jupyter Lab

extension ManagedServicePresets {
    static let jupyterLab = ManagedServicePreset(
        id: "jupyter-lab",
        titleKey: "preset.jupyter-lab.title",
        summaryKey: "preset.jupyter-lab.summary",
        icon: "book",
        category: .notebook,
        dependencyBinary: "jupyter",
        fields: [
            PresetField(
                id: "directory",
                titleKey: presetFieldKey("jupyter-lab", "directory"),
                helpKey: presetFieldKey("jupyter-lab", "directory.help"),
                kind: .directory,
                charset: .path,
                defaultValue: "",
                isRequired: true
            ),
        ],
        suggestedPort: 8888,
        warningKeys: [
            "preset.jupyter-lab.warning.token",
            "preset.jupyter-lab.warning.public",
        ],
        isHTTPService: true,
        supportsQuickTunnel: true,
        generate: { context, fields in
            let directory = fields["directory"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let executable = context.resolvedExecutablePath.map { ManagedServicePresetCommandRenderer.shellSingleQuoted($0) } ?? "jupyter"
            let command = "\(executable) lab --no-browser --ip 127.0.0.1 --port-retries=0 --port {port} --notebook-dir "
                + ManagedServicePresetCommandRenderer.shellSingleQuoted(directory)
            return ManagedServiceConfig(
                id: context.id,
                name: context.name,
                port: context.port,
                host: "localhost",
                workingDirectory: directory,
                startCommand: command,
                presetID: "jupyter-lab"
            )
        }
    )
}
