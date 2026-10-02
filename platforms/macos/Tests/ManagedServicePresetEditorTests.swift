import Foundation
import Testing

@testable import PortKiller

/// Preset-mode editor tests: begin/switch/draft/validation, plus the
/// deterministic field extractor used when re-opening preset profiles.
/// All validators are injected; nothing touches the filesystem except
/// temp paths that pass through the injected validator.
@Suite struct ManagedServicePresetEditorTests {
    private struct StubValidator: WorkingDirectoryValidating {
        let isValid: Bool
        func isExistingDirectory(at path: String) -> Bool { isValid }
    }

    private func validatedConfig(
        presetID: String,
        port: Int = 8123,
        existing: [ManagedServiceConfig] = [],
        directoryIsValid: Bool = true
    ) -> ManagedServiceConfig {
        let preset = ManagedServicePresets.preset(withID: presetID)!
        return preset.generate(
            PresetGenerationContext(id: UUID(), name: "Demo", port: port, homeDirectory: "/tmp"),
            preset.defaultFieldValues()
        )
    }

    // MARK: beginPreset

    @Test func beginPresetPrefillsDefaultsAndSuggestedPort() {
        let model = ManagedServiceEditorViewModel()
        model.beginPreset(ManagedServicePresets.preset(withID: "static-file-share")!)
        #expect(model.presetID == "static-file-share")
        #expect(model.portText == "8123")
        #expect(model.fieldValues["directory"] == "")
        #expect(model.isEditing == false)
    }

    @Test func beginPresetWithoutSuggestionLeavesPortEmpty() {
        let model = ManagedServiceEditorViewModel()
        model.beginPreset(ManagedServicePresets.preset(withID: "ssh-local-forward")!)
        #expect(model.portText == "")
    }

    // MARK: beginEdit round trips

    @Test func beginEditReopensPresetFormWithPrefilledDirectory() {
        let config = validatedConfig(presetID: "static-file-share")
        let withDirectory = ManagedServiceConfig(
            id: config.id, name: config.name, port: config.port, host: config.host,
            workingDirectory: "/Users/me/share", startCommand: config.startCommand,
            presetID: config.presetID
        )
        let model = ManagedServiceEditorViewModel()
        model.beginEdit(withDirectory)
        #expect(model.presetID == "static-file-share")
        #expect(model.fieldValues["directory"] == "/Users/me/share")
        #expect(model.name == withDirectory.name)
        #expect(model.portText == String(withDirectory.port))
    }

    @Test func beginEditExtractsSshForwardValues() {
        let preset = ManagedServicePresets.preset(withID: "ssh-local-forward")!
        var values = preset.defaultFieldValues()
        values["sshHost"] = "web.example.com"
        values["remotePort"] = "5432"
        let config = preset.generate(
            PresetGenerationContext(id: UUID(), name: "DB", port: 15432, homeDirectory: "/tmp"),
            values
        )
        let model = ManagedServiceEditorViewModel()
        model.beginEdit(config)
        #expect(model.presetID == "ssh-local-forward")
        #expect(model.fieldValues["sshHost"] == "web.example.com")
        #expect(model.fieldValues["remoteHost"] == "127.0.0.1")
        #expect(model.fieldValues["remotePort"] == "5432")
        #expect(model.fieldValues["keepaliveInterval"] == "15")
        #expect(model.fieldValues["keepaliveCount"] == "3")
    }

    @Test func beginEditExtractsDufsMode() {
        let preset = ManagedServicePresets.preset(withID: "dufs-file-share")!
        var values = preset.defaultFieldValues()
        values["mode"] = "read-write"
        values["directory"] = "/srv"
        let config = preset.generate(
            PresetGenerationContext(id: UUID(), name: "Share", port: 5000, homeDirectory: "/tmp"),
            values
        )
        let model = ManagedServiceEditorViewModel()
        model.beginEdit(config)
        #expect(model.fieldValues["mode"] == "read-write")
        #expect(model.fieldValues["directory"] == "/srv")
    }

    @Test func unknownPresetIDDegradesToCustom() {
        let model = ManagedServiceEditorViewModel()
        model.beginEdit(ManagedServiceConfig(
            id: UUID(), name: "X", port: 80, host: "localhost",
            workingDirectory: "/tmp", startCommand: "serve {port}",
            presetID: "removed-preset"
        ))
        #expect(model.presetID == nil)
        #expect(model.preset == nil)
        #expect(model.startCommand == "serve {port}")
    }

    // MARK: selectPreset

    @Test func switchingToCustomKeepsGeneratedCommand() {
        let model = ManagedServiceEditorViewModel()
        model.beginPreset(ManagedServicePresets.preset(withID: "static-file-share")!)
        model.name = "Share"
        model.portText = "9000"
        model.fieldValues["directory"] = "/tmp/srv"
        let generated = model.draftConfig()
        model.selectPreset(nil)
        #expect(model.presetID == nil)
        #expect(model.startCommand == generated.startCommand)
        #expect(model.workingDirectory == "/tmp/srv")
    }

    @Test func switchingPresetCarriesDirectory() {
        let model = ManagedServiceEditorViewModel()
        model.beginPreset(ManagedServicePresets.preset(withID: "static-file-share")!)
        model.fieldValues["directory"] = "/tmp/srv"
        model.selectPreset(ManagedServicePresets.preset(withID: "dufs-file-share")!)
        #expect(model.presetID == "dufs-file-share")
        #expect(model.fieldValues["directory"] == "/tmp/srv")
        #expect(model.fieldValues["mode"] == "read-only")
    }

    // MARK: draftConfig

    @Test func draftCarriesPresetIDAndPortPlaceholder() {
        let model = ManagedServiceEditorViewModel()
        model.beginPreset(ManagedServicePresets.preset(withID: "static-file-share")!)
        model.name = "Share"
        model.portText = "9000"
        model.fieldValues["directory"] = "/tmp/srv"
        let draft = model.draftConfig()
        #expect(draft.presetID == "static-file-share")
        #expect(draft.port == 9000)
        #expect(draft.startCommand.contains("{port}"))
        #expect(draft.workingDirectory == "/tmp/srv")
    }

    // MARK: Validation

    @Test func emptyRequiredFieldBlocksSave() {
        let model = ManagedServiceEditorViewModel()
        model.beginPreset(ManagedServicePresets.preset(withID: "static-file-share")!)
        #expect(model.invalidPresetField?.field.id == "directory")
        #expect(model.invalidPresetField?.error == .empty)
    }

    @Test func invalidCharsetBlocksSave() {
        let model = ManagedServiceEditorViewModel()
        model.beginPreset(ManagedServicePresets.preset(withID: "ssh-local-forward")!)
        model.fieldValues["sshHost"] = "a;b"
        model.fieldValues["remotePort"] = "5432"
        #expect(model.invalidPresetField?.field.id == "sshHost")
        #expect(model.invalidPresetField?.error == .invalidCharacters)
    }

    @Test func validFieldsPlusValidatedDraftPass() {
        let model = ManagedServiceEditorViewModel()
        model.beginPreset(ManagedServicePresets.preset(withID: "ssh-local-forward")!)
        model.name = "Tunnel"
        model.portText = "15432"
        model.fieldValues["sshHost"] = "web.example.com"
        model.fieldValues["remotePort"] = "5432"
        #expect(model.invalidPresetField == nil)
        let error = model.validate(
            existing: [],
            directoryValidator: StubValidator(isValid: true)
        )
        #expect(error == nil)
    }

    @Test func duplicateNameStillRejectedInPresetMode() {
        let existing = ManagedServiceConfig(
            id: UUID(), name: "Tunnel", port: 9999, host: "localhost",
            workingDirectory: "/tmp", startCommand: "serve {port}"
        )
        let model = ManagedServiceEditorViewModel()
        model.beginPreset(ManagedServicePresets.preset(withID: "ssh-local-forward")!)
        model.name = "Tunnel"
        model.portText = "15432"
        model.fieldValues["sshHost"] = "web.example.com"
        model.fieldValues["remotePort"] = "5432"
        let error = model.validate(
            existing: [existing],
            directoryValidator: StubValidator(isValid: true)
        )
        #expect(error != nil)
    }

    // MARK: Extractor edge cases

    @Test func extractorFallsBackToDefaultsOnGarbage() {
        let preset = ManagedServicePresets.preset(withID: "ssh-local-forward")!
        let config = ManagedServiceConfig(
            id: UUID(), name: "X", port: 1, host: "localhost",
            workingDirectory: "/tmp", startCommand: "not a generated command",
            presetID: "ssh-local-forward"
        )
        let values = ManagedServicePresetFieldExtractor.extractFieldValues(
            for: preset, from: config, homeDirectory: "/tmp")
        #expect(values["sshHost"] == "")
        #expect(values["remoteHost"] == "127.0.0.1")
    }

    /// Explicit loopback bind round-trips through the extractor.
    @Test func extractorParsesExplicitLoopbackForwardSpec() {
        let preset = ManagedServicePresets.preset(withID: "ssh-local-forward")!
        var values = preset.defaultFieldValues()
        values["sshHost"] = "box.lan"
        values["remoteHost"] = "db.internal"
        values["remotePort"] = "8080"
        let config = preset.generate(
            PresetGenerationContext(id: UUID(), name: "X", port: 7000, homeDirectory: "/tmp"),
            values
        )
        #expect(config.startCommand.contains("-L 127.0.0.1:{port}:db.internal:8080"))
        let extracted = ManagedServicePresetFieldExtractor.extractFieldValues(
            for: preset, from: config, homeDirectory: "/tmp")
        #expect(extracted["remoteHost"] == "db.internal")
        #expect(extracted["remotePort"] == "8080")
    }

    /// Legacy profiles saved before the explicit bind still re-open with
    /// their values (compatibility with profiles persisted by 33025d3).
    @Test func extractorStillParsesLegacyForwardSpec() {
        let preset = ManagedServicePresets.preset(withID: "ssh-local-forward")!
        let legacy = ManagedServiceConfig(
            id: UUID(), name: "Legacy", port: 7000, host: "localhost",
            workingDirectory: "/tmp",
            startCommand: "ssh -N -L {port}:db.internal:8080 -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 'box.lan'",
            presetID: "ssh-local-forward"
        )
        let extracted = ManagedServicePresetFieldExtractor.extractFieldValues(
            for: preset, from: legacy, homeDirectory: "/tmp")
        #expect(extracted["remoteHost"] == "db.internal")
        #expect(extracted["remotePort"] == "8080")
        #expect(extracted["sshHost"] == "box.lan")
    }

    /// Dependency-resolved generation quotes the absolute executable; the
    /// extractor must still find the SSH host after it.
    @Test func extractorParsesResolvedExecutableCommand() {
        let preset = ManagedServicePresets.preset(withID: "ssh-local-forward")!
        var values = preset.defaultFieldValues()
        values["sshHost"] = "box.lan"
        values["remotePort"] = "8080"
        let config = preset.generate(
            PresetGenerationContext(
                id: UUID(), name: "X", port: 7000, homeDirectory: "/tmp",
                resolvedExecutablePath: "/opt/homebrew/bin/ssh"),
            values
        )
        #expect(config.startCommand.hasPrefix("'/opt/homebrew/bin/ssh' -N -L 127.0.0.1:"))
        let extracted = ManagedServicePresetFieldExtractor.extractFieldValues(
            for: preset, from: config, homeDirectory: "/tmp")
        #expect(extracted["sshHost"] == "box.lan")
        #expect(extracted["remotePort"] == "8080")
    }

    // MARK: Dependency-resolved generation

    /// The probe's resolved path must land in the generated command: a
    /// fallback/known-path binary may not be on the executor's PATH, so the
    /// bare name would not resolve at start time.
    @Test func resolvedExecutablePathIsRenderedIntoCommands() {
        for id in ["static-file-share", "dufs-file-share", "jupyter-lab", "ssh-local-forward", "ssh-socks5-proxy"] {
            let preset = ManagedServicePresets.preset(withID: id)!
            var values = preset.defaultFieldValues()
            if values["directory"] != nil { values["directory"] = "/tmp/demo" }
            if values["sshHost"] != nil { values["sshHost"] = "box.lan" }
            if values["remotePort"] != nil { values["remotePort"] = "8080" }
            let config = preset.generate(
                PresetGenerationContext(
                    id: UUID(), name: "X", port: 7000, homeDirectory: "/tmp",
                    resolvedExecutablePath: "/opt/tools/bin/" + (id.hasPrefix("ssh") ? "ssh" : id.hasPrefix("dufs") ? "dufs" : id.hasPrefix("jupyter") ? "jupyter" : "python3")),
                values
            )
            #expect(config.startCommand.hasPrefix("'/opt/tools/bin/"), "preset \(id)")
            #expect(!config.startCommand.hasPrefix("ssh ") && !config.startCommand.hasPrefix("python3 ") && !config.startCommand.hasPrefix("dufs ") && !config.startCommand.hasPrefix("jupyter "))
        }
    }

    /// No resolved path falls back to the bare binary name.
    @Test func nilResolvedPathFallsBackToBareBinary() {
        let preset = ManagedServicePresets.preset(withID: "ssh-local-forward")!
        var values = preset.defaultFieldValues()
        values["sshHost"] = "box.lan"
        values["remotePort"] = "8080"
        let config = preset.generate(
            PresetGenerationContext(id: UUID(), name: "X", port: 7000, homeDirectory: "/tmp"),
            values
        )
        #expect(config.startCommand.hasPrefix("ssh -N -L 127.0.0.1:"))
    }
}
