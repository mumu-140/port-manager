using PortKiller.Models;
using System.IO;

namespace PortKiller.Services;

/// <summary>
/// Deterministic field extraction for re-opening the preset form from a
/// persisted profile. Mirrors macOS ManagedServicePresetFieldExtractor:
/// the start command is app-generated with a fixed per-preset shape, so
/// reversing that shape is not intent guessing. Best effort: anything
/// unparseable keeps the field default.
/// </summary>
public static class ManagedServicePresetFieldExtractor
{
    public static Dictionary<string, string> ExtractFieldValues(
        ManagedServicePreset preset, ManagedServiceConfig config, string homeDirectory)
    {
        var values = preset.DefaultFieldValues();
        var command = config.StartCommand ?? string.Empty;
        var tokens = command.Split(new[] { ' ' }, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

        switch (preset.Id)
        {
            case "static-file-share":
            case "dufs-file-share":
            case "jupyter-lab":
                // File-share presets set WorkingDirectory to the shared directory.
                values["directory"] = config.WorkingDirectory;
                if (preset.Id == "dufs-file-share")
                {
                    values["mode"] = DufsMode(command) ?? values["mode"];
                }
                break;

            case "ssh-local-forward":
                if (ForwardSpec(tokens, "-L", localIsFirst: true) is { } localSpec)
                {
                    values["remoteHost"] = localSpec.Host;
                    values["remotePort"] = localSpec.RemotePort;
                }
                ApplySshTail(tokens, values);
                break;

            case "ssh-socks5-proxy":
                ApplySshTail(tokens, values);
                break;
        }
        return values;
    }

    /// <summary>
    /// -L 127.0.0.1:{port}:<host>:<remotePort> (localIsFirst). Legacy
    /// profiles saved before the explicit loopback bind (-L {port}:host:port)
    /// still parse so re-editing them keeps their values.
    /// </summary>
    private static (string Host, string RemotePort)? ForwardSpec(
        string[] tokens, string flag, bool localIsFirst)
    {
        for (var i = 0; i < tokens.Length - 1; i++)
        {
            if (tokens[i] != flag) continue;
            var parts = tokens[i + 1].Split(':');
            if (localIsFirst)
            {
                if (parts.Length == 4 && parts[0] == "127.0.0.1")
                {
                    return (parts[2], parts[3]);
                }
                if (parts.Length == 3)
                {
                    return (parts[1], parts[2]);
                }
            }
        }
        return null;
    }

    /// <summary>
    /// The ssh host is the final token of every generated SSH command; keepalive
    /// values come from their fixed -o options. The first token may be a quoted
    /// absolute executable path (dependency-resolved generation), so the guard
    /// matches on its file name. Only runs on the generated shape (ssh ... with
    /// a forward flag); anything else keeps defaults.
    /// </summary>
    private static void ApplySshTail(string[] tokens, Dictionary<string, string> values)
    {
        if (tokens.Length == 0 || Path.GetFileName(Unquote(tokens[0])) is not ("ssh" or "ssh.exe")) return;
        var hasForwardFlag = Array.Exists(tokens, t => t == "-L" || t == "-D");
        if (!hasForwardFlag) return;

        for (var i = tokens.Length - 1; i >= 0; i--)
        {
            var token = tokens[i];
            if (token.StartsWith("-") || token.Contains(':')) continue;
            values["sshHost"] = Unquote(token);
            break;
        }

        for (var i = 0; i < tokens.Length - 1; i++)
        {
            if (tokens[i] != "-o") continue;
            var option = tokens[i + 1];
            if (option.StartsWith("ServerAliveInterval="))
            {
                values["keepaliveInterval"] = option["ServerAliveInterval=".Length..];
            }
            else if (option.StartsWith("ServerAliveCountMax="))
            {
                values["keepaliveCount"] = option["ServerAliveCountMax=".Length..];
            }
        }
    }

    /// <summary>Reverse of the path quoting applied by the renderer.</summary>
    private static string Unquote(string value)
    {
        if (value.Length >= 2 && value.StartsWith('"') && value.EndsWith('"'))
        {
            return value[1..^1];
        }
        return value;
    }

    /// <summary>dufs permission flags to mode id (generator order: upload then delete).</summary>
    private static string? DufsMode(string command)
    {
        if (command.Contains("--allow-delete")) return "read-write";
        if (command.Contains("--allow-upload")) return "upload";
        return command.Contains("--port") ? "read-only" : null;
    }
}
