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
    /// <summary>SSH host or alias: letters, digits, dot, dash, underscore, plus user@host and IPv6 colons.</summary>
    SshHost,

    /// <summary>Digits only (ports, intervals).</summary>
    Integer,

    /// <summary>Filesystem path: everything except double-quote, percent and newlines.</summary>
    Path,

    /// <summary>Extra SSH options: a conservative flag-list set with no shell metacharacters at all.</summary>
    SshExtraOptions,

    /// <summary>Free text with no newlines.</summary>
    FreeText,
}

/// <summary>Structured field-validation failures. Mirrors macOS PresetFieldValueError.</summary>
public enum PresetFieldValueErrorKind
{
    Empty,
    NotAnInteger,
    InvalidCharacters,
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
    public required Func<PresetGenerationContext, IReadOnlyDictionary<string, string>, ManagedServiceConfig> Generate { get; init; }

    /// <summary>Field values with every field's default applied.</summary>
    public Dictionary<string, string> DefaultFieldValues() =>
        Fields.ToDictionary(field => field.Id, field => field.DefaultValue);

    /// <summary>Validates one field's value against its charset and requiredness.</summary>
    public PresetFieldValueErrorKind? ValidateField(PresetField field, string? value)
    {
        var trimmed = (value ?? string.Empty).Trim();
        if (trimmed.Length == 0)
        {
            return field.IsRequired ? PresetFieldValueErrorKind.Empty : null;
        }
        return ManagedServicePresetCharsetValidator.Validate(field.Charset, trimmed);
    }

    /// <summary>
    /// Warnings that apply right now given the current field values (design
    /// section 10.2). Static WarningKeys minus the GatewayPorts warning while
    /// the SSH reverse remote bind is still 127.0.0.1, plus the serving-scope
    /// home-root warning when a directory field points at the home directory
    /// itself. Mirrors macOS ManagedServicePreset.activeWarningKeys.
    /// </summary>
    public List<string> ActiveWarningKeys(IReadOnlyDictionary<string, string> fieldValues, string homeDirectory)
    {
        var keys = new List<string>(WarningKeys);
        if (Id == "ssh-reverse-forward")
        {
            var remoteBind = fieldValues.TryGetValue("remoteBind", out var bind) ? bind.Trim() : "127.0.0.1";
            if (remoteBind.Length == 0) remoteBind = "127.0.0.1";
            if (remoteBind == "127.0.0.1")
            {
                keys.RemoveAll(key => key == "preset.ssh-reverse-forward.warning.gatewayports");
            }
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
            case PresetFieldCharset.SshHost:
                return value.All(c => char.IsLetterOrDigit(c) || c is '.' or '-' or '_' or '@' or ':')
                    ? null : PresetFieldValueErrorKind.InvalidCharacters;
            case PresetFieldCharset.Path:
                return value.Any(c => c == '"' || c == '%' || c == '\r' || c == '\n')
                    ? PresetFieldValueErrorKind.InvalidCharacters : null;
            case PresetFieldCharset.SshExtraOptions:
                return value.All(c => char.IsLetterOrDigit(c) || c is ' ' or '=' or ':' or '.' or '_' or '/' or '-')
                    ? null : PresetFieldValueErrorKind.InvalidCharacters;
            case PresetFieldCharset.FreeText:
                return value.Any(char.IsControl) ? PresetFieldValueErrorKind.InvalidCharacters : null;
            default:
                return PresetFieldValueErrorKind.InvalidCharacters;
        }
    }
}
