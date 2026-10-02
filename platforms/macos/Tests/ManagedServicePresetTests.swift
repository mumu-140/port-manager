import Foundation
import Testing
@testable import PortKiller

/**
 * Pure preset tests: registry integrity, charset validation, generator output
 * shape, and the single-quote rendering contract. The one integration test
 * spawns /bin/zsh to prove the escaping round-trips through the exact shell
 * the app executes commands with; everything else never touches a process.
 */
struct ManagedServicePresetTests {

    // MARK: - Fixtures

    private let directory = "/tmp/portkiller-preset-test"
    private let home = "/Users/preset-tester"

    private var validator: FakePresetDirectoryValidator {
        FakePresetDirectoryValidator(existing: [directory, home])
    }

    private struct FakePresetDirectoryValidator: WorkingDirectoryValidating {
        let existing: Set<String>

        func isExistingDirectory(at path: String) -> Bool {
            existing.contains(path)
        }
    }

    private func context(
        id: UUID = UUID(),
        name: String = "Preset Demo",
        port: Int = 8123
    ) -> PresetGenerationContext {
        PresetGenerationContext(id: id, name: name, port: port, homeDirectory: home)
    }

    private func values(_ preset: ManagedServicePreset, _ overrides: [String: String] = [:]) -> [String: String] {
        var v = preset.defaultFieldValues()
        for (key, value) in overrides { v[key] = value }
        return v
    }

    private func generatedCommand(
        _ presetID: String,
        _ overrides: [String: String] = [:],
        port: Int = 8123
    ) -> String {
        let preset = ManagedServicePresets.preset(withID: presetID)!
        let config = preset.generate(context(port: port), values(preset, overrides))
        return config.startCommand
    }

    // MARK: - Registry

    @Test func presetIDsAreUnique() {
        let ids = ManagedServicePresets.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func registryResolvesEveryPresetByID() {
        for preset in ManagedServicePresets.all {
            #expect(ManagedServicePresets.preset(withID: preset.id)?.id == preset.id)
        }
    }

    @Test func unknownPresetIDResolvesToNil() {
        #expect(ManagedServicePresets.preset(withID: "custom") == nil)
        #expect(ManagedServicePresets.preset(withID: "removed-preset") == nil)
    }

    @Test func everyPresetHasFieldsAndIcons() {
        for preset in ManagedServicePresets.all {
            #expect(!preset.fields.isEmpty)
            #expect(!preset.titleKey.isEmpty)
            #expect(!preset.summaryKey.isEmpty)
        }
    }

    // MARK: - Generators produce valid profiles

    @Test func staticFileShareGeneratorProducesValidProfile() {
        let preset = ManagedServicePresets.preset(withID: "static-file-share")!
        let config = preset.generate(context(), values(preset, ["directory": directory]))
        #expect(config.presetID == "static-file-share")
        #expect(config.workingDirectory == directory)
        #expect(config.host == "localhost")
        #expect(ManagedServiceValidator.validate(config, existing: [], directoryValidator: validator) == nil)
    }

    @Test func sshLocalForwardGeneratorProducesValidProfile() {
        let preset = ManagedServicePresets.preset(withID: "ssh-local-forward")!
        let config = preset.generate(
            context(port: 15432),
            values(preset, ["sshHost": "web.example.com", "remotePort": "5432"])
        )
        #expect(config.port == 15432)
        #expect(config.workingDirectory == home)
        #expect(ManagedServiceValidator.validate(config, existing: [], directoryValidator: validator) == nil)
    }

    @Test func sshSocks5AndReverseGeneratorsProduceValidProfiles() {
        for id in ["ssh-socks5-proxy", "ssh-reverse-forward"] {
            let preset = ManagedServicePresets.preset(withID: id)!
            let config = preset.generate(context(), values(preset, ["sshHost": "box.lan", "remotePort": "8080"]))
            #expect(ManagedServiceValidator.validate(config, existing: [], directoryValidator: validator) == nil)
        }
    }

    @Test func dufsAndJupyterGeneratorsProduceValidProfiles() {
        for id in ["dufs-file-share", "jupyter-lab"] {
            let preset = ManagedServicePresets.preset(withID: id)!
            let config = preset.generate(context(), values(preset, ["directory": directory]))
            #expect(ManagedServiceValidator.validate(config, existing: [], directoryValidator: validator) == nil)
        }
    }

    // MARK: - Fixed invariants

    @Test func everyGeneratedCommandKeepsThePortPlaceholder() {
        for preset in ManagedServicePresets.all {
            let config = preset.generate(context(), values(preset))
            #expect(config.startCommand.contains("{port}"))
        }
    }

    @Test func listeningPresetsBindLoopbackExplicitly() {
        #expect(generatedCommand("static-file-share").contains("--bind 127.0.0.1"))
        #expect(generatedCommand("dufs-file-share").contains("--bind 127.0.0.1"))
        #expect(generatedCommand("jupyter-lab").contains("--ip 127.0.0.1"))
        #expect(generatedCommand("ssh-socks5-proxy").contains("-D 127.0.0.1:{port}"))
    }

    @Test func jupyterFixedFlagsArePresentExactlyOnce() {
        let command = generatedCommand("jupyter-lab", ["directory": directory])
        #expect(command.components(separatedBy: "--no-browser").count - 1 == 1)
        #expect(command.components(separatedBy: "--port-retries=0").count - 1 == 1)
    }

    @Test func sshPresetsAlwaysCarryNAndExitOnForwardFailure() {
        for id in ["ssh-local-forward", "ssh-socks5-proxy", "ssh-reverse-forward"] {
            let command = generatedCommand(id)
            #expect(command.contains("-N"))
            #expect(command.contains("-o ExitOnForwardFailure=yes"))
            #expect(command.contains("-o ServerAliveInterval=15"))
            #expect(command.contains("-o ServerAliveCountMax=3"))
        }
    }

    @Test func sshLocalForwardRendersForwardSpec() {
        let command = generatedCommand(
            "ssh-local-forward",
            ["sshHost": "web.example.com", "remoteHost": "127.0.0.1", "remotePort": "5432"],
            port: 15432
        )
        #expect(command.contains("-L {port}:127.0.0.1:5432"))
        #expect(command.hasSuffix("'web.example.com'"))
    }

    @Test func sshReverseForwardRendersRemoteBindFirst() {
        let command = generatedCommand(
            "ssh-reverse-forward",
            ["sshHost": "box.lan", "remoteBind": "127.0.0.1", "remotePort": "8080"]
        )
        #expect(command.contains("-R 127.0.0.1:8080:127.0.0.1:{port}"))
    }

    @Test func dufsModesRenderPermissionFlags() {
        #expect(!generatedCommand("dufs-file-share", ["mode": "read-only"]).contains("--allow-"))
        #expect(generatedCommand("dufs-file-share", ["mode": "upload"]).contains("--allow-upload"))
        #expect(!generatedCommand("dufs-file-share", ["mode": "upload"]).contains("--allow-delete"))
        let rw = generatedCommand("dufs-file-share", ["mode": "read-write"])
        #expect(rw.contains("--allow-upload") && rw.contains("--allow-delete"))
    }

    @Test func extraOptionsAreInsertedIntoSshCommands() {
        let command = generatedCommand("ssh-local-forward", ["extraOptions": "-o Compression=yes -vv"])
        #expect(command.contains("-o Compression=yes -vv"))
    }

    // MARK: - Field validation

    @Test func requiredEmptyFieldsAreRejected() {
        let preset = ManagedServicePresets.preset(withID: "static-file-share")!
        #expect(preset.firstInvalidField(in: values(preset, ["directory": "  "])) == "directory")
        #expect(preset.firstInvalidField(in: values(preset, ["directory": directory])) == nil)
    }

    @Test func sshHostCharsetRejectsShellMetacharacters() {
        let preset = ManagedServicePresets.preset(withID: "ssh-local-forward")!
        let field = preset.fields.first { $0.id == "sshHost" }!
        #expect(preset.validate(field: field, value: "web.example.com") == nil)
        #expect(preset.validate(field: field, value: "user@host:2222") == nil)
        #expect(preset.validate(field: field, value: "a b") == .invalidCharacters)
        #expect(preset.validate(field: field, value: "a;b") == .invalidCharacters)
        #expect(preset.validate(field: field, value: "$(x)") == .invalidCharacters)
        #expect(preset.validate(field: field, value: "it's") == .invalidCharacters)
    }

    @Test func integerCharsetRejectsNonDigits() {
        let preset = ManagedServicePresets.preset(withID: "ssh-local-forward")!
        let field = preset.fields.first { $0.id == "remotePort" }!
        #expect(preset.validate(field: field, value: "5432") == nil)
        #expect(preset.validate(field: field, value: "5432x") == .notAnInteger)
        #expect(preset.validate(field: field, value: "port") == .notAnInteger)
    }

    @Test func pathCharsetRejectsQuotePercentAndNewlines() {
        let preset = ManagedServicePresets.preset(withID: "static-file-share")!
        let field = preset.fields.first { $0.id == "directory" }!
        #expect(preset.validate(field: field, value: "/tmp/some folder") == nil)
        #expect(preset.validate(field: field, value: "/tmp/a\"b") == .invalidCharacters)
        #expect(preset.validate(field: field, value: "/tmp/a%b") == .invalidCharacters)
        #expect(preset.validate(field: field, value: "/tmp/a\nb") == .invalidCharacters)
    }

    @Test func extraOptionsCharsetRejectsQuotesDollarsAndBackslashes() {
        let preset = ManagedServicePresets.preset(withID: "ssh-local-forward")!
        let field = preset.fields.first { $0.id == "extraOptions" }!
        #expect(preset.validate(field: field, value: "-o Compression=yes") == nil)
        #expect(preset.validate(field: field, value: "-L 80:bad") == nil)
        #expect(preset.validate(field: field, value: "a'b") == .invalidCharacters)
        #expect(preset.validate(field: field, value: "a$b") == .invalidCharacters)
        #expect(preset.validate(field: field, value: "a\\b") == .invalidCharacters)
        #expect(preset.validate(field: field, value: "a;b") == .invalidCharacters)
    }

    // MARK: - Renderer

    @Test func shellSingleQuotingMatchesThePosixRule() {
        #expect(ManagedServicePresetCommandRenderer.shellSingleQuoted("plain") == "'plain'")
        #expect(ManagedServicePresetCommandRenderer.shellSingleQuoted("it's") == "'it'\\''s'")
        #expect(ManagedServicePresetCommandRenderer.shellSingleQuoted("/tmp/a b") == "'/tmp/a b'")
    }

    /// Integration proof: the escaped value round-trips byte-identically
    /// through /bin/zsh — the exact shell the process controller uses.
    @Test func shellSingleQuotingRoundTripsThroughZsh() throws {
        let hostile = "it's a \"test\" & more $VAR `cmd` \\path"
        let escaped = ManagedServicePresetCommandRenderer.shellSingleQuoted(hostile)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "printf '%s' " + escaped]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        #expect(String(data: data, encoding: .utf8) == hostile)
    }

    // MARK: - presetID model field

    @Test func generatedProfilesCarryPresetID() {
        let preset = ManagedServicePresets.preset(withID: "static-file-share")!
        let config = preset.generate(context(), values(preset))
        #expect(config.presetID == "static-file-share")
    }

    @Test func presetIDRoundTripsThroughCodable() throws {
        var config = ManagedServiceConfig(name: "X", port: 80, workingDirectory: home, startCommand: "serve {port}")
        config.presetID = "static-file-share"
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ManagedServiceConfig.self, from: data)
        #expect(decoded.presetID == "static-file-share")
    }

    /// Profiles persisted before presets existed have no presetID key; the
    /// synthesized Codable must decode them to nil (backwards compatibility).
    @Test func missingPresetIDKeyDecodesToNil() throws {
        let config = ManagedServiceConfig(name: "Legacy", port: 80, workingDirectory: home, startCommand: "serve {port}")
        #expect(config.presetID == nil)
        let data = try JSONEncoder().encode(config)
        let json = String(data: data, encoding: .utf8)!
        #expect(!json.contains("presetID"))
        let decoded = try JSONDecoder().decode(ManagedServiceConfig.self, from: data)
        #expect(decoded.presetID == nil)
    }
}
