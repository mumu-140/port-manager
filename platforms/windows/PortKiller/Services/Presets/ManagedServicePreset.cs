using PortKiller.Models;

namespace PortKiller.Services;

/// <summary>
/// Coarse grouping used by the picker UI. Mirrors macOS PresetCategory.
/// </summary>
public enum PresetCategory
{
    General,
    FileShare,
    Tunnel,
    Notebook,
}

/// <summary>
/// How the editor renders one preset field. Mirrors macOS PresetFieldKind.
/// </summary>
public enum PresetFieldKind
{
    Text,
    Port,
    Directory,
    SingleSelect,
}

/// <summary>One choice inside a SingleSelect field.</summary>
public sealed class PresetSelectOption
{
    public string Id { get; init; } = string.Empty;
    public string TitleKey { get; init; } = string.Empty;
}

/// <summary>
/// Per-field character allow-lists (design: presets-exposure, section 10.1).
/// This is the "constrain" half of constrain-and-quote: fields reject the
/// characters that would need cmd.exe escaping in the first place. Newlines
/// are rejected everywhere because the start command is single-line.
/// Mirrors macOS PresetFieldCharset.
/// </summary>
public enum PresetFieldCharset
{
    /// <summary>
    /// SSH host or alias: letters, digits, dot, dash, underscore, plus user@host.
    /// IPv6 literals are deferred (v1 constrains forward targets to
    /// hostname/IPv4 so colon-concatenated forward specs stay parseable).
    /// </summary>
    SshHost,

    /// <summary>Digits only (ServerAliveInterval / ServerAliveCountMax — integers
    /// with their own semantics, deliberately not TCP-port bounded).</summary>
    Integer,

    /// <summary>TCP port number: digits in 1...65535.</summary>
    TcpPort,

    /// <summary>Filesystem path: everything except double-quote, percent and newlines.</summary>
    Path,

    /// <summary>Extra SSH options: a conservative flag-list set with no shell metacharacters at all.</summary>

    /// <summary>Free text with no newlines.</summary>
    FreeText,
}

/// <summary>Structured field-validation failures. Mirrors macOS PresetFieldValueError.</summary>
public enum PresetFieldValueErrorKind
{
    Empty,
    NotAnInteger,
    InvalidCharacters,

    /// <summary>Numeric value outside the field's semantic range (TCP ports).</summary>
    OutOfRange,

    /// <summary>Directory field points at a filesystem root (Jupyter guard).</summary>
    RootDirectory,
}

/// <summary>One editable field of a preset form. Mirrors macOS PresetField.</summary>
public sealed class PresetField
{
    public string Id { get; init; } = string.Empty;
    public string TitleKey { get; init; } = string.Empty;
    public string? HelpKey { get; init; }
    public PresetFieldKind Kind { get; init; }
    public PresetFieldCharset Charset { get; init; }
    public string DefaultValue { get; init; } = string.Empty;
    public bool IsRequired { get; init; }
    /// <summary>Advanced fields render collapsed under an expander.</summary>
    public bool IsAdvanced { get; init; }
    public IReadOnlyList<PresetSelectOption> Options { get; init; } = Array.Empty<PresetSelectOption>();
}

/// <summary>Context the editor supplies around preset fields. Mirrors macOS PresetGenerationContext.</summary>
public sealed class PresetGenerationContext
{
    public Guid Id { get; init; }
    public string Name { get; init; } = string.Empty;
    /// <summary>User-edited service port (the {port} placeholder target).</summary>
    public int Port { get; init; }
    /// <summary>Platform home directory, used as the working directory for presets
    /// that have no natural one (SSH forwards).</summary>
    public string HomeDirectory { get; init; } = string.Empty;

    /// <summary>
    /// Absolute executable path the dependency probe resolved for this
    /// preset's binary, when available. Generators render this path (quoted)
    /// instead of the bare binary name so the command always executes the
    /// binary the probe reported as available — a fallback/known-path hit
    /// must not silently degrade to a bare name the shell may not resolve.
    /// </summary>
    public string? ResolvedExecutablePath { get; init; }
}

/// <summary>
/// A static service preset: metadata + ordered form fields + pure generator.
/// Mirrors macOS ManagedServicePreset.
///
/// Presets are never persisted as objects and never bypass the existing
/// validator or manager: the generated profile flows through
/// ManagedServiceValidator exactly like a hand-written one. Only the resulting
/// profile (plus its PresetId marker) is persisted.
///
/// Security model (design section 10): the app composes start commands from
/// user-controlled field values, so the app owns safe rendering. On Windows
/// the strategy is constrain-and-quote: field charsets reject cmd.exe
/// metacharacters and path-like values are double-quoted by the renderer. The
/// custom-service editor is NOT a preset and keeps its "user-authored shell,
/// nothing escaped" contract.
/// </summary>
public sealed class ManagedServicePreset
{
    public required string Id { get; init; }
    public required string TitleKey { get; init; }
    public required string SummaryKey { get; init; }
    public required string Icon { get; init; }
    public required PresetCategory Category { get; init; }
    /// <summary>Binary name to probe for availability (design section 9); null when the preset has no external dependency.</summary>
    public string? DependencyBinary { get; init; }
    public required IReadOnlyList<PresetField> Fields { get; init; }
    /// <summary>Suggested port for the editor's port field; null keeps the existing editor default.</summary>
    public int? SuggestedPort { get; init; }
    public IReadOnlyList<string> WarningKeys { get; init; } = Array.Empty<string>();

    /// <summary>Whether the preset serves HTTP on {port}: gates the Open-in-browser
    /// action. SSH forwards are not HTTP services.</summary>
    public bool IsHttpService { get; init; }

    /// <summary>Whether the Cloudflare Quick Tunnel flow applies (HTTP services only).</summary>
    public bool SupportsQuickTunnel { get; init; }

    public required Func<PresetGenerationContext, IReadOnlyDictionary<string, string>, ManagedServiceConfig> Generate { get; init; }

    /// <summary>Field values with every field's default applied.</summary>
    public Dictionary<string, string> DefaultFieldValues() =>
        Fields.ToDictionary(field => field.Id, field => field.DefaultValue);

    /// <summary>
    /// Validates one field's value against its charset and requiredness.
    /// Jupyter additionally rejects filesystem roots as the notebook
    /// directory: sharing / (or a Windows drive root) would publish the
    /// whole volume.
    /// </summary>
    public PresetFieldValueErrorKind? ValidateField(PresetField field, string? value)
    {
        var trimmed = (value ?? string.Empty).Trim();
        if (trimmed.Length == 0)
        {
            return field.IsRequired ? PresetFieldValueErrorKind.Empty : null;
        }
        if (Id == "jupyter-lab" && field.Kind == PresetFieldKind.Directory && IsRootDirectory(trimmed))
        {
            return PresetFieldValueErrorKind.RootDirectory;
        }
        return ManagedServicePresetCharsetValidator.Validate(field.Charset, trimmed);
    }

    /// <summary>
    /// True for filesystem roots that must never be shared as a Jupyter
    /// notebook directory: the POSIX root and Windows drive roots. Pure so
    /// both platforms' tests exercise the same rule.
    /// </summary>
    public static bool IsRootDirectory(string path)
    {
        var normalized = path;
        while (normalized.Length > 1 && (normalized.EndsWith('/') || normalized.EndsWith('\\')))
        {
            normalized = normalized[..^1];
        }
        if (normalized is "/" or "\\") return true;
        var lowered = normalized.ToLowerInvariant();
        // A Windows drive root ("C:\\") loses its backslash to the trim and
        // survives as "c:" — still a drive root, never a real directory.
        if (lowered.Length == 2 && lowered.EndsWith(":") && char.IsAsciiLetter(lowered[0])) return true;
        return false;
    }

    /// <summary>
    /// Warnings that apply right now given the current field values (design
    /// section 10.2). Static WarningKeys with mode-dependent refinement — a
    /// read-only Dufs share is not writable, so the writable warning does
    /// not apply — plus the serving-scope home-root warning when a directory
    /// field points at the home directory itself. Mirrors macOS
    /// ManagedServicePreset.activeWarningKeys.
    /// </summary>
    public List<string> ActiveWarningKeys(IReadOnlyDictionary<string, string> fieldValues, string homeDirectory)
    {
        var keys = new List<string>(WarningKeys);
        var mode = fieldValues.TryGetValue("mode", out var m) ? m.Trim() : "read-only";
        if (Id == "dufs-file-share" && (mode.Length == 0 || mode == "read-only"))
        {
            keys.RemoveAll(key => key == "preset.dufs-file-share.warning.writable");
        }
        if (Fields.Any(field => field.Kind == PresetFieldKind.Directory)
            && fieldValues.TryGetValue("directory", out var directory)
            && directory.Trim().Length > 0
            && IsHomeRoot(directory.Trim(), homeDirectory.Trim()))
        {
            keys.Add("preset.file-share.warning.homeRoot");
        }
        return keys;
    }

    /// <summary>Treats the home root with or without a trailing slash as the
    /// same location; deeper paths never match.</summary>
    private static bool IsHomeRoot(string directory, string homeDirectory)
    {
        static string TrimSlashes(string path)
        {
            while (path.Length > 1 && (path.EndsWith('/') || path.EndsWith('\\')))
            {
                path = path[..^1];
            }
            return path;
        }
        return string.Equals(TrimSlashes(directory), TrimSlashes(homeDirectory), StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>Validates every field; returns the first failing field id.</summary>
    public string? FirstInvalidField(IReadOnlyDictionary<string, string> values)
    {
        foreach (var field in Fields)
        {
            if (ValidateField(field, values.TryGetValue(field.Id, out var value) ? value : null) is not null)
            {
                return field.Id;
            }
        }
        return null;
    }
}

/// <summary>Applies the charset rules. Mirrors macOS PresetFieldCharset.validate.</summary>
public static class ManagedServicePresetCharsetValidator
{
    public static PresetFieldValueErrorKind? Validate(PresetFieldCharset charset, string value)
    {
        switch (charset)
        {
            case PresetFieldCharset.Integer:
                return value.All(char.IsDigit) ? null : PresetFieldValueErrorKind.NotAnInteger;
            case PresetFieldCharset.TcpPort:
                if (!value.All(char.IsDigit) || !int.TryParse(value, out var tcpPort) || tcpPort is < 1 or > 65535)
                {
                    return PresetFieldValueErrorKind.OutOfRange;
                }
                return null;
            case PresetFieldCharset.SshHost:
                return value.All(c => char.IsLetterOrDigit(c) || c is '.' or '-' or '_' or '@')
                    ? null : PresetFieldValueErrorKind.InvalidCharacters;
            case PresetFieldCharset.Path:
                return value.Any(c => c == '"' || c == '%' || c == '\r' || c == '\n')
                    ? PresetFieldValueErrorKind.InvalidCharacters : null;
            case PresetFieldCharset.FreeText:
                return value.Any(char.IsControl) ? PresetFieldValueErrorKind.InvalidCharacters : null;
            default:
                return PresetFieldValueErrorKind.InvalidCharacters;
        }
    }
}
