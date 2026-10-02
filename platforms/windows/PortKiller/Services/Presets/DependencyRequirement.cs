using System.Runtime.InteropServices;

namespace PortKiller.Services;

/// <summary>
/// One external binary a preset depends on (design section 9).
/// Mirrors macOS DependencyRequirement. Pure data; probes stay read-only.
/// </summary>
public sealed class DependencyRequirement
{
    /// <summary>Executable file name, e.g. "python", "ssh", "dufs", "jupyter".</summary>
    public string BinaryName { get; init; } = string.Empty;

    /// <summary>Absolute paths checked before the PATH search.</summary>
    public IReadOnlyList<string> KnownPaths { get; init; } = Array.Empty<string>();

    /// <summary>Version command arguments, display only (never run for detection).</summary>
    public IReadOnlyList<string> VersionArgs { get; init; } = new[] { "--version" };

    /// <summary>Localized key of the explanation shown when the binary is missing.</summary>
    public string NotInstalledKey { get; init; } = string.Empty;

    /// <summary>Documentation URL surfaced in the not-installed banner.</summary>
    public string InstallDocumentsURL { get; init; } = string.Empty;

    /// <summary>Localized key with tailored copy for the WindowsApps python
    /// stub case (Microsoft Store alias that opens the Store instead of running).</summary>
    public string StubCopyKey { get; init; }

    /// <summary>v1 requirements (per research known-path tables).</summary>

    /// Windows OpenSSH client. System32 is preferred over Git-bundled ssh.
    public static DependencyRequirement Ssh { get; } = new()
    {
        BinaryName = "ssh",
        KnownPaths = new[]
        {
            Environment.SystemDirectory + "\\ssh.exe",
            @"C:\Program Files\OpenSSH\ssh.exe",
        },
        VersionArgs = new[] { "-V" },
        NotInstalledKey = "dependency.ssh.notInstalled",
        InstallDocumentsURL = "https://learn.microsoft.com/windows/terminal/open-terminal-ssh",
    };

    /// Windows python. PATH first; the WindowsApps Store stub is filtered by
    /// the probe; the py launcher is a documented fallback.
    public static DependencyRequirement Python { get; } = new()
    {
        BinaryName = "python",
        KnownPaths = Array.Empty<string>(),
        NotInstalledKey = "dependency.python.notInstalled",
        InstallDocumentsURL = "https://www.python.org/downloads/windows/",
        StubCopyKey = "dependency.python.stub",
    };

    /// Windows dufs (scoop shim or a downloaded exe on PATH).
    public static DependencyRequirement Dufs { get; } = new()
    {
        BinaryName = "dufs",
        KnownPaths = new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) + @"\\scoop\\shims\\dufs.exe",
        },
        NotInstalledKey = "dependency.dufs.notInstalled",
        InstallDocumentsURL = "https://github.com/sigoden/dufs#installation",
    };

    /// Windows jupyter (pip/conda Scripts directory on PATH).
    public static DependencyRequirement Jupyter { get; } = new()
    {
        BinaryName = "jupyter",
        KnownPaths = Array.Empty<string>(),
        NotInstalledKey = "dependency.jupyter.notInstalled",
        InstallDocumentsURL = "https://docs.jupyter.org/en/latest/install/install-official.html",
    };

    /// <summary>Requirement attached to a preset ID (mirrors macOS table).</summary>
    public static DependencyRequirement? RequirementForPresetId(string? presetId) => presetId switch
    {
        "static-file-share" => Python,
        "ssh-local-forward" or "ssh-socks5-proxy" or "ssh-reverse-forward" => Ssh,
        "dufs-file-share" => Dufs,
        "jupyter-lab" => Jupyter,
        _ => null,
    };
}
