using PortKiller.Models;
using System.IO;

namespace PortKiller.Services;

/// <summary>
/// The concrete v1 preset definitions and the registry. Mirrors macOS ManagedServicePresets.
///
/// Every generator is a pure function from field values to a complete profile;
/// the resulting profile still passes through ManagedServiceValidator before it can be saved.
///
/// Fixed invariants rendered by every listening preset:
/// - loopback binding is explicit (python and dufs default to all interfaces);
/// - SSH forwards always carry -N and ExitOnForwardFailure=yes;
/// - Jupyter always carries --no-browser, --ip 127.0.0.1 and --port-retries=0
///   so a busy port surfaces as a Conflict instead of a silent port move;
/// - the {port} placeholder is preserved so future port edits follow.
///
/// Security model (design section 10): constrain-and-quote. Field charsets reject
/// cmd.exe metacharacters. Path values are double-quoted by the renderer.
/// The custom-service editor keeps its "user-authored shell, nothing escaped" contract.
/// </summary>
public static class ManagedServicePresets
{
    /// <summary>All v1 presets in picker order (Custom Service is prepended by the UI).</summary>
    /// <remarks>Lazy: static property initializers run in textual order, so the
    /// list must be built on first access, after the preset properties below
    /// have initialized.</remarks>
    private static readonly Lazy<IReadOnlyList<ManagedServicePreset>> AllLazy = new(
        () => new List<ManagedServicePreset>
        {
            StaticFileShare,
            SshLocalForward,
            SshSocks5Proxy,
            DufsFileShare,
            JupyterLab,
        });

    public static IReadOnlyList<ManagedServicePreset> All => AllLazy.Value;

    /// <summary>Looks a preset up by its persisted ID; null for custom/unknown IDs.</summary>
    public static ManagedServicePreset? PresetWithId(string id) =>
        All.FirstOrDefault(p => p.Id == id);

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private const string SshExitOnForwardFailure = "-o ExitOnForwardFailure=yes";

    private static string SshOptionsTail(IReadOnlyDictionary<string, string> fields)
    {
        var interval = fields.TryGetValue("keepaliveInterval", out var iv) ? iv : "15";
        var count = fields.TryGetValue("keepaliveCount", out var cn) ? cn : "3";
        return " -o ServerAliveInterval=" + interval + " -o ServerAliveCountMax=" + count;
    }

    private static string QuotePath(string path)
    {
        // Double trailing backslash before closing quote per MSVCRT rules
        var trailingBackslashes = 0;
        for (var i = path.Length - 1; i >= 0 && path[i] == '\\'; i--)
        {
            trailingBackslashes++;
        }
        if (trailingBackslashes % 2 == 1)
        {
            path += '\\';
        }
        return "\"" + path + "\"";
    }

    private static string SshHost(string value)
    {
        // Values reaching here already pass SshHost charset (safe for use as-is)
        return value;
    }

    // -------------------------------------------------------------------------
    // Field-key builder
    // -------------------------------------------------------------------------

    private static string FieldKey(string presetId, string fieldId) =>
        $"preset.{presetId}.field.{fieldId}";

    // -------------------------------------------------------------------------
    // Static File Share (python http.server)
    // -------------------------------------------------------------------------

    public static ManagedServicePreset StaticFileShare { get; } = new()
    {
        Id = "static-file-share",
        TitleKey = "preset.static-file-share.title",
        SummaryKey = "preset.static-file-share.summary",
        Icon = "folder",
        Category = PresetCategory.FileShare,
        DependencyBinary = "python",
        SuggestedPort = 8123,
        WarningKeys = new[] { "preset.static-file-share.warning.listing", "preset.static-file-share.warning.symlinks" },
        IsHttpService = true,
        SupportsQuickTunnel = true,
        Fields = new List<PresetField>
        {
            new()
            {
                Id = "directory",
                TitleKey = FieldKey("static-file-share", "directory"),
                HelpKey = FieldKey("static-file-share", "directory.help"),
                Kind = PresetFieldKind.Directory,
                Charset = PresetFieldCharset.Path,
                DefaultValue = "",
                IsRequired = true,
            },
        },
        Generate = static (ctx, fields) =>
        {
            var directory = fields.TryGetValue("directory", out var d) ? d.Trim() : "";
            var executable = ctx.ResolvedExecutablePath is string pyPath ? QuotePath(pyPath) : "python";
            var command = $"{executable} -m http.server {{port}} --bind 127.0.0.1 --directory {QuotePath(directory)}";
            return new ManagedServiceConfig
            {
                Id = ctx.Id,
                Name = ctx.Name,
                Port = ctx.Port,
                Host = "localhost",
                WorkingDirectory = directory,
                StartCommand = command,
                PresetId = "static-file-share",
            };
        },
    };

    // -------------------------------------------------------------------------
    // SSH Local Forward
    // -------------------------------------------------------------------------

    public static ManagedServicePreset SshLocalForward { get; } = new()
    {
        Id = "ssh-local-forward",
        TitleKey = "preset.ssh-local-forward.title",
        SummaryKey = "preset.ssh-local-forward.summary",
        Icon = "arrow.down.forward",
        Category = PresetCategory.Tunnel,
        DependencyBinary = "ssh",
        WarningKeys = Array.Empty<string>(),
        Fields = new List<PresetField>
        {
            new() { Id = "sshHost", TitleKey = FieldKey("ssh", "host"), HelpKey = FieldKey("ssh", "host.help"), Kind = PresetFieldKind.Text, Charset = PresetFieldCharset.SshHost, DefaultValue = "", IsRequired = true },
            new() { Id = "remoteHost", TitleKey = FieldKey("ssh", "remoteHost"), HelpKey = FieldKey("ssh", "remoteHost.help"), Kind = PresetFieldKind.Text, Charset = PresetFieldCharset.SshHost, DefaultValue = "127.0.0.1", IsRequired = true, IsAdvanced = true },
            new() { Id = "remotePort", TitleKey = FieldKey("ssh", "remotePort"), Kind = PresetFieldKind.Port, Charset = PresetFieldCharset.TcpPort, DefaultValue = "", IsRequired = true },
            new() { Id = "keepaliveInterval", TitleKey = FieldKey("ssh", "keepaliveInterval"), HelpKey = FieldKey("ssh", "keepaliveInterval.help"), Kind = PresetFieldKind.Port, Charset = PresetFieldCharset.Integer, DefaultValue = "15", IsAdvanced = true },
            new() { Id = "keepaliveCount", TitleKey = FieldKey("ssh", "keepaliveCount"), Kind = PresetFieldKind.Port, Charset = PresetFieldCharset.Integer, DefaultValue = "3", IsAdvanced = true },
        },
        Generate = static (ctx, fields) =>
        {
            var host = fields.TryGetValue("sshHost", out var h) ? h.Trim() : "";
            var remoteHost = fields.TryGetValue("remoteHost", out var rh) ? rh.Trim() : "127.0.0.1";
            var remotePort = fields.TryGetValue("remotePort", out var rp) ? rp.Trim() : "";
            // The listener bind is spelled out: it must never depend on the
            // user's ssh_config GatewayPorts settings.
            var executable = ctx.ResolvedExecutablePath is string sshPath ? QuotePath(sshPath) : "ssh";
            var command = $"{executable} -N -L 127.0.0.1:{{port}}:{remoteHost}:{remotePort} {SshExitOnForwardFailure}{SshOptionsTail(fields)} {SshHost(host)}";
            return new ManagedServiceConfig
            {
                Id = ctx.Id,
                Name = ctx.Name,
                Port = ctx.Port,
                Host = "localhost",
                WorkingDirectory = ctx.HomeDirectory,
                StartCommand = command,
                PresetId = "ssh-local-forward",
            };
        },
    };

    // -------------------------------------------------------------------------
    // SSH SOCKS5 Proxy
    // -------------------------------------------------------------------------

    public static ManagedServicePreset SshSocks5Proxy { get; } = new()
    {
        Id = "ssh-socks5-proxy",
        TitleKey = "preset.ssh-socks5-proxy.title",
        SummaryKey = "preset.ssh-socks5-proxy.summary",
        Icon = "globe",
        Category = PresetCategory.Tunnel,
        DependencyBinary = "ssh",
        WarningKeys = Array.Empty<string>(),
        Fields = new List<PresetField>
        {
            new() { Id = "sshHost", TitleKey = FieldKey("ssh", "host"), HelpKey = FieldKey("ssh", "host.help"), Kind = PresetFieldKind.Text, Charset = PresetFieldCharset.SshHost, DefaultValue = "", IsRequired = true },
            new() { Id = "keepaliveInterval", TitleKey = FieldKey("ssh", "keepaliveInterval"), HelpKey = FieldKey("ssh", "keepaliveInterval.help"), Kind = PresetFieldKind.Port, Charset = PresetFieldCharset.Integer, DefaultValue = "15", IsAdvanced = true },
            new() { Id = "keepaliveCount", TitleKey = FieldKey("ssh", "keepaliveCount"), Kind = PresetFieldKind.Port, Charset = PresetFieldCharset.Integer, DefaultValue = "3", IsAdvanced = true },
        },
        Generate = static (ctx, fields) =>
        {
            var host = fields.TryGetValue("sshHost", out var h) ? h.Trim() : "";
            var executable = ctx.ResolvedExecutablePath is string proxyPath ? QuotePath(proxyPath) : "ssh";
            var command = $"{executable} -N -D 127.0.0.1:{{port}} {SshExitOnForwardFailure}{SshOptionsTail(fields)} {SshHost(host)}";
            return new ManagedServiceConfig
            {
                Id = ctx.Id,
                Name = ctx.Name,
                Port = ctx.Port,
                Host = "localhost",
                WorkingDirectory = ctx.HomeDirectory,
                StartCommand = command,
                PresetId = "ssh-socks5-proxy",
            };
        },
    };

    // -------------------------------------------------------------------------
    // Dufs File Share
    // -------------------------------------------------------------------------

    public static ManagedServicePreset DufsFileShare { get; } = new()
    {
        Id = "dufs-file-share",
        TitleKey = "preset.dufs-file-share.title",
        SummaryKey = "preset.dufs-file-share.summary",
        Icon = "externaldrive",
        Category = PresetCategory.FileShare,
        DependencyBinary = "dufs",
        SuggestedPort = 5000,
        WarningKeys = new[] { "preset.dufs-file-share.warning.noAuth", "preset.dufs-file-share.warning.writable" },
        IsHttpService = true,
        SupportsQuickTunnel = true,
        Fields = new List<PresetField>
        {
            new() { Id = "directory", TitleKey = FieldKey("dufs-file-share", "directory"), Kind = PresetFieldKind.Directory, Charset = PresetFieldCharset.Path, DefaultValue = "", IsRequired = true },
            new()
            {
                Id = "mode",
                TitleKey = FieldKey("dufs-file-share", "mode"),
                HelpKey = FieldKey("dufs-file-share", "mode.help"),
                Kind = PresetFieldKind.SingleSelect,
                Charset = PresetFieldCharset.FreeText,
                DefaultValue = "read-only",
                Options = new List<PresetSelectOption>
                {
                    new() { Id = "read-only", TitleKey = "preset.dufs-file-share.mode.readOnly" },
                    new() { Id = "upload", TitleKey = "preset.dufs-file-share.mode.upload" },
                    new() { Id = "read-write", TitleKey = "preset.dufs-file-share.mode.readWrite" },
                },
            },
        },
        Generate = static (ctx, fields) =>
        {
            var directory = fields.TryGetValue("directory", out var d) ? d.Trim() : "";
            var mode = fields.TryGetValue("mode", out var m) ? m : "read-only";
            var flags = $"--port {{port}} --bind 127.0.0.1";
            if (mode == "upload" || mode == "read-write")
            {
                flags += " --allow-upload";
            }
            if (mode == "read-write")
            {
                flags += " --allow-delete";
            }
            var executable = ctx.ResolvedExecutablePath is string dufsPath ? QuotePath(dufsPath) : "dufs";
            var command = $"{executable} {flags} {QuotePath(directory)}";
            return new ManagedServiceConfig
            {
                Id = ctx.Id,
                Name = ctx.Name,
                Port = ctx.Port,
                Host = "localhost",
                WorkingDirectory = directory,
                StartCommand = command,
                PresetId = "dufs-file-share",
            };
        },
    };

    // -------------------------------------------------------------------------
    // Jupyter Lab
    // -------------------------------------------------------------------------

    public static ManagedServicePreset JupyterLab { get; } = new()
    {
        Id = "jupyter-lab",
        TitleKey = "preset.jupyter-lab.title",
        SummaryKey = "preset.jupyter-lab.summary",
        Icon = "book",
        Category = PresetCategory.Notebook,
        DependencyBinary = "jupyter",
        SuggestedPort = 8888,
        WarningKeys = new[] { "preset.jupyter-lab.warning.token", "preset.jupyter-lab.warning.public" },
        IsHttpService = true,
        SupportsQuickTunnel = true,
        Fields = new List<PresetField>
        {
            new()
            {
                Id = "directory",
                TitleKey = FieldKey("jupyter-lab", "directory"),
                HelpKey = FieldKey("jupyter-lab", "directory.help"),
                Kind = PresetFieldKind.Directory,
                Charset = PresetFieldCharset.Path,
                DefaultValue = "",
                IsRequired = true,
            },
        },
        Generate = static (ctx, fields) =>
        {
            var directory = fields.TryGetValue("directory", out var d) ? d.Trim() : "";
            var executable = ctx.ResolvedExecutablePath is string jupyterPath ? QuotePath(jupyterPath) : "jupyter";
            var command = $"{executable} lab --no-browser --ip 127.0.0.1 --port-retries=0 --port {{port}} --notebook-dir {QuotePath(directory)}";
            return new ManagedServiceConfig
            {
                Id = ctx.Id,
                Name = ctx.Name,
                Port = ctx.Port,
                Host = "localhost",
                WorkingDirectory = directory,
                StartCommand = command,
                PresetId = "jupyter-lab",
            };
        },
    };
}
