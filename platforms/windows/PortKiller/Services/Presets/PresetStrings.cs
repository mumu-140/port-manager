namespace PortKiller.Services;

/// <summary>
/// Display copy for the preset picker and preset forms, keyed exactly like the
/// macOS ManagedServiceStrings preset/dependency entries. Windows has no
/// localization layer yet (the app's UI strings are English today); this table
/// keeps the same key architecture so a future Windows resource dictionary can
/// replace it without touching call sites.
/// </summary>
public static class PresetStrings
{
    private static readonly Dictionary<string, string> Entries = new()
    {
        ["preset.custom.title"] = "Custom Service",
        ["preset.picker.typeLabel"] = "Type",
        ["preset.advanced"] = "Advanced Options",

        ["preset.static-file-share.title"] = "Static File Share",
        ["preset.static-file-share.summary"] = "Serve a directory over HTTP with Python.",
        ["preset.static-file-share.field.directory"] = "Directory",
        ["preset.static-file-share.field.directory.help"] = "The directory to share.",
        ["preset.static-file-share.warning.listing"] = "Anyone using this PC can browse the shared directory.",
        ["preset.static-file-share.warning.symlinks"] = "Symlinks inside the directory are followed.",

        ["preset.ssh-local-forward.title"] = "SSH Local Forward",
        ["preset.ssh-local-forward.summary"] = "Reach a remote port through an SSH host.",

        ["preset.ssh-socks5-proxy.title"] = "SSH SOCKS5 Proxy",
        ["preset.ssh-socks5-proxy.summary"] = "Route traffic through an SSH host as a SOCKS5 proxy.",


        ["preset.dufs-file-share.title"] = "Dufs File Share",
        ["preset.dufs-file-share.summary"] = "Serve a directory with upload controls via Dufs.",
        ["preset.dufs-file-share.field.directory"] = "Directory",
        ["preset.dufs-file-share.field.mode"] = "Access Mode",
        ["preset.dufs-file-share.field.mode.help"] = "Controls upload and delete permissions.",
        ["preset.dufs-file-share.mode.readOnly"] = "Read only",
        ["preset.dufs-file-share.mode.upload"] = "Upload allowed",
        ["preset.dufs-file-share.mode.readWrite"] = "Read/write",
        ["preset.dufs-file-share.warning.noAuth"] = "This share has no authentication: anyone using this PC can reach it.",
        ["preset.dufs-file-share.warning.writable"] = "Writable shares let others modify the shared directory.",

        ["preset.jupyter-lab.title"] = "Jupyter Lab",
        ["preset.jupyter-lab.summary"] = "Run a Jupyter Lab notebook server on a loopback port.",
        ["preset.jupyter-lab.field.directory"] = "Notebook Directory",
        ["preset.jupyter-lab.field.directory.help"] = "Root directory for notebooks.",
        ["preset.jupyter-lab.warning.token"] = "Jupyter prints its access token to the service log; copy it from there.",
        ["preset.jupyter-lab.warning.public"] = "The server binds to 127.0.0.1; sharing beyond this PC needs a tunnel.",

        ["preset.file-share.warning.homeRoot"] = "Sharing your home directory exposes everything in it. Consider choosing a narrower folder.",

        ["exposure.confirm.title"] = "Share this service publicly?",
        ["exposure.confirm.start"] = "Share",
        ["exposure.warning.dufsWritablePublic"] = "This share is writable and has no authentication. Sharing it publicly lets anyone upload, modify or delete files in the shared directory.",
        ["exposure.warning.dufsPublic"] = "This share has no authentication. Sharing it publicly lets anyone read the shared directory.",
        ["exposure.warning.jupyterPublic"] = "Sharing Jupyter publicly lets anyone run code on this PC through the notebook interface.",

        ["preset.ssh.field.host"] = "SSH Host",
        ["preset.ssh.field.host.help"] = "Alias from your OpenSSH config or user@host.",
        ["preset.ssh.field.remoteHost"] = "Remote Host",
        ["preset.ssh.field.remoteHost.help"] = "Host as seen from the SSH server.",
        ["preset.ssh.field.remotePort"] = "Remote Port",
        ["preset.ssh.field.keepaliveInterval"] = "Keepalive Interval (s)",
        ["preset.ssh.field.keepaliveInterval.help"] = "ServerAliveInterval for the connection.",
        ["preset.ssh.field.keepaliveCount"] = "Keepalive Count",

        ["preset.error.empty"] = "{0} is required.",
        ["preset.error.notAnInteger"] = "{0} must be a number.",
        ["preset.error.invalidCharacters"] = "{0} contains characters that are not allowed here.",
        ["preset.error.outOfRange"] = "{0} is outside the valid range (1-65535 for TCP ports).",
        ["preset.error.rootDirectory"] = "The root directory cannot be shared.",

        ["dependency.notInstalled"] = "Not installed",
        ["dependency.availableTitle"] = "Dependency Ready",
        ["dependency.available"] = "Installed at {0}.",
        ["dependency.notInstalledTitle"] = "{0} is not installed",
        ["dependency.ssh.notInstalled"] = "The OpenSSH client is part of Windows; enable it in Optional Features.",
        ["dependency.python.notInstalled"] = "Install Python from python.org or via winget.",
        ["dependency.python.stub"] = "The Microsoft Store python alias is present but not installed; disable the alias or install Python directly.",
        ["dependency.dufs.notInstalled"] = "Install Dufs via scoop (scoop install dufs) or download it from GitHub.",
        ["dependency.jupyter.notInstalled"] = "Install Jupyter with pip (pip install jupyterlab).",
        ["dependency.viewInstallDocs"] = "View installation docs...",
    };

    /// <summary>Lookup; unknown keys fall back to the key itself (visible, never silent).</summary>
    public static string Lookup(string key) =>
        Entries.TryGetValue(key, out var value) ? value : key;

    /// <summary>Formatted lookup for keys with {0}/{1} placeholders.</summary>
    public static string Lookup(string key, params object[] args) =>
        string.Format(System.Globalization.CultureInfo.InvariantCulture, Lookup(key), args);
}
