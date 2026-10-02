import Foundation

/// One external binary a preset depends on (design section 9).
///
/// Pure data: what to look for, where it is typically installed, and where to
/// point the user when it is missing. No installs, no network, no config
/// writes — discovery is strictly read-only.
struct DependencyRequirement {
    /// Executable file name, e.g. "python3", "ssh", "dufs", "jupyter".
    let binaryName: String

    /// Absolute paths checked before the PATH search (homebrew/opt locations).
    let knownPaths: [String]

    /// Relative directories appended to the PATH search.
    /// Used for per-user tool layouts (e.g. ~/.local/bin for pip tools).
    let fallbackPaths: [String]

    /// Version command arguments, display only (never run for detection).
    let versionArgs: [String]

    /// Localized key of the explanation shown when the binary is missing.
    let notInstalledKey: String

    /// Documentation URL surfaced in the not-installed banner.
    let installDocumentsURL: String

    /// Localized key with tailored copy for the macOS CommandLineTools
    /// python3 stub case (same notInstalled state, different explanation).
    let stubCopyKey: String?

    init(
        binaryName: String,
        knownPaths: [String],
        fallbackPaths: [String] = [],
        versionArgs: [String] = ["--version"],
        notInstalledKey: String,
        installDocumentsURL: String,
        stubCopyKey: String? = nil
    ) {
        self.binaryName = binaryName
        self.knownPaths = knownPaths
        self.fallbackPaths = fallbackPaths
        self.versionArgs = versionArgs
        self.notInstalledKey = notInstalledKey
        self.installDocumentsURL = installDocumentsURL
        self.stubCopyKey = stubCopyKey
    }

    // MARK: v1 requirements (per research known-path tables)

    /// macOS OpenSSH client. Ships with the OS at /usr/bin/ssh.
    static let ssh = DependencyRequirement(
        binaryName: "ssh",
        knownPaths: ["/usr/bin/ssh"],
        versionArgs: ["-V"],
        notInstalledKey: "dependency.ssh.notInstalled",
        installDocumentsURL: "https://support.apple.com/guide/terminal/welcome-apd6b107d3c9/mac"
    )

    /// macOS python3. /usr/bin/python3 may be the CommandLineTools stub, so
    /// a real interpreter is preferred; stubCopyKey carries tailored copy.
    static let python3 = DependencyRequirement(
        binaryName: "python3",
        knownPaths: ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"],
        notInstalledKey: "dependency.python3.notInstalled",
        installDocumentsURL: "https://www.python.org/downloads/",
        stubCopyKey: "dependency.python3.stub"
    )

    /// macOS dufs (single-file file server, usually via homebrew or cargo).
    static let dufs = DependencyRequirement(
        binaryName: "dufs",
        knownPaths: ["/opt/homebrew/bin/dufs", "/usr/local/bin/dufs"],
        notInstalledKey: "dependency.dufs.notInstalled",
        installDocumentsURL: "https://github.com/sigoden/dufs#installation"
    )

    /// macOS jupyter (pip/conda installed; often in ~/.local/bin).
    static let jupyter = DependencyRequirement(
        binaryName: "jupyter",
        knownPaths: [],
        fallbackPaths: ["~/.local/bin"],
        notInstalledKey: "dependency.jupyter.notInstalled",
        installDocumentsURL: "https://docs.jupyter.org/en/latest/install/install-official.html"
    )

    /// Requirement attached to a preset ID (mirrors ManagedServicePreset.dependencyBinary).
    static func requirement(forPresetID presetID: String) -> DependencyRequirement? {
        switch presetID {
        case "static-file-share": return .python3
        case "ssh-local-forward", "ssh-socks5-proxy", "ssh-reverse-forward": return .ssh
        case "dufs-file-share": return .dufs
        case "jupyter-lab": return .jupyter
        default: return nil
        }
    }
}
