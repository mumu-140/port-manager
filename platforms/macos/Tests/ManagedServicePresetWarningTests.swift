import Foundation
import Testing

@testable import PortKiller

/// Pure mapping tests for M7 warnings (design section 10.2).
@Suite struct ManagedServicePresetWarningTests {
    private let home = NSHomeDirectory()

    private func makeConfig(_ presetID: String, startCommand: String) -> ManagedServiceConfig {
        ManagedServiceConfig(
            name: "Demo",
            port: 8123,
            host: "localhost",
            workingDirectory: home,
            startCommand: startCommand,
            presetID: presetID,
        )
    }

    // MARK: Active form warnings

    @Test func staticFileShareShowsStaticWarningsPlusHomeRootScope() {
        let preset = ManagedServicePresets.staticFileShare
        var values = preset.defaultFieldValues()
        values["directory"] = home
        let keys = preset.activeWarningKeys(fieldValues: values, homeDirectory: home)
        #expect(keys.contains("preset.static-file-share.warning.listing"))
        #expect(keys.contains("preset.static-file-share.warning.symlinks"))
        #expect(keys.contains("preset.file-share.warning.homeRoot"))
    }

    @Test func deeperDirectorySuppressesHomeRootWarning() {
        let preset = ManagedServicePresets.staticFileShare
        var values = preset.defaultFieldValues()
        values["directory"] = home + "/Sites"
        let keys = preset.activeWarningKeys(fieldValues: values, homeDirectory: home)
        #expect(!keys.contains("preset.file-share.warning.homeRoot"))
    }

    @Test func trailingSlashHomeRootStillWarns() {
        let preset = ManagedServicePresets.staticFileShare
        var values = preset.defaultFieldValues()
        values["directory"] = home + "/"
        let keys = preset.activeWarningKeys(fieldValues: values, homeDirectory: home)
        #expect(keys.contains("preset.file-share.warning.homeRoot"))
    }

    /// Read-only Dufs is not writable: only the no-auth warning applies.
    @Test func readOnlyDufsShowsOnlyNoAuthWarning() {
        let preset = ManagedServicePresets.dufsFileShare
        var values = preset.defaultFieldValues()
        values["mode"] = "read-only"
        let keys = preset.activeWarningKeys(fieldValues: values, homeDirectory: home)
        #expect(keys.contains("preset.dufs-file-share.warning.noAuth"))
        #expect(!keys.contains("preset.dufs-file-share.warning.writable"))
    }

    @Test func writableDufsModesShowNoAuthAndWritableWarnings() {
        let preset = ManagedServicePresets.dufsFileShare
        for mode in ["upload", "read-write"] {
            var values = preset.defaultFieldValues()
            values["mode"] = mode
            let keys = preset.activeWarningKeys(fieldValues: values, homeDirectory: home)
            #expect(keys.contains("preset.dufs-file-share.warning.noAuth"))
            #expect(keys.contains("preset.dufs-file-share.warning.writable"))
        }
    }

    @Test func jupyterShowsTokenAndPublicWarnings() {
        let preset = ManagedServicePresets.jupyterLab
        let values = preset.defaultFieldValues()
        let keys = preset.activeWarningKeys(fieldValues: values, homeDirectory: home)
        #expect(keys.contains("preset.jupyter-lab.warning.token"))
        #expect(keys.contains("preset.jupyter-lab.warning.public"))
    }

    // MARK: Exposure double-warning

    @Test func uploadDufsSharesWithExplicitWarning() {
        let preset = ManagedServicePresets.dufsFileShare
        var values = preset.defaultFieldValues()
        values["mode"] = "upload"
        values["directory"] = home + "/public"
        values["mode"] = "read-write"
        let config = preset.generate(
            PresetGenerationContext(id: UUID(), name: "Demo", port: 5000, homeDirectory: home),
            values)
        #expect(ManagedServiceExposureWarning.messageKey(for: config) == "exposure.warning.dufsWritablePublic")
    }

    @Test func readOnlyDufsSharesWithNoAuthWarning() {
        let preset = ManagedServicePresets.dufsFileShare
        var values = preset.defaultFieldValues()
        values["directory"] = home + "/public"
        let config = preset.generate(
            PresetGenerationContext(id: UUID(), name: "Demo", port: 5000, homeDirectory: home),
            values)
        #expect(ManagedServiceExposureWarning.messageKey(for: config) == "exposure.warning.dufsPublic")
    }

    @Test func jupyterSharesWithStrongWarning() {
        let preset = ManagedServicePresets.jupyterLab
        var values = preset.defaultFieldValues()
        values["directory"] = home + "/notebooks"
        let config = preset.generate(
            PresetGenerationContext(id: UUID(), name: "Demo", port: 8888, homeDirectory: home),
            values)
        #expect(ManagedServiceExposureWarning.messageKey(for: config) == "exposure.warning.jupyterPublic")
    }

    @Test func customAndOtherPresetsShareWithoutExtraWarning() {
        let custom = ManagedServiceConfig(
            name: "Custom",
            port: 8080,
            host: "localhost",
            workingDirectory: home,
            startCommand: "python3 -m http.server {port}",
        )
        #expect(ManagedServiceExposureWarning.messageKey(for: custom) == nil)
        let ssh = makeConfig("ssh-local-forward", startCommand: "ssh -N -L ...")
        #expect(ManagedServiceExposureWarning.messageKey(for: ssh) == nil)
    }
}
