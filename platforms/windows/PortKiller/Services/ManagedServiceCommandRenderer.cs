using System.IO;
using PortKiller.Models;

namespace PortKiller.Services;

/// <summary>
/// Pure command rendering. Mirrors macOS ManagedServiceCommandRenderer.
/// </summary>
public static class ManagedServiceCommandRenderer
{
    public const string PortPlaceholder = "{port}";

    private static readonly System.Text.RegularExpressions.Regex PlaceholderPattern =
        new(@"\{([^{}]*)\}", System.Text.RegularExpressions.RegexOptions.Compiled);

    /// <summary>Returns every <c>{...}</c> token that is not exactly <c>{port}</c>.</summary>
    public static IReadOnlyList<string> UnsupportedPlaceholders(string? command)
    {
        var text = command ?? string.Empty;
        var found = new List<string>();
        foreach (System.Text.RegularExpressions.Match match in PlaceholderPattern.Matches(text))
        {
            var token = match.Value;
            if (!string.Equals(token, PortPlaceholder, StringComparison.Ordinal))
            {
                found.Add(token);
            }
        }
        return found;
    }

    /// <summary>Replaces every exact <c>{port}</c> with the decimal port.</summary>
    public static string Render(string? command, int port) =>
        (command ?? string.Empty).Replace(PortPlaceholder, port.ToString(System.Globalization.CultureInfo.InvariantCulture), StringComparison.Ordinal);
}

public enum ManagedServiceValidationErrorKind
{
    EmptyName,
    DuplicateName,
    EmptyHost,
    PortOutOfRange,
    DuplicatePort,
    MissingWorkingDirectory,
    EmptyCommand,
    UnsupportedPlaceholder,
    ServiceRunning,
}

/// <summary>Structured validation failure. Mirrors macOS ManagedServiceValidationError.</summary>
public sealed class ManagedServiceValidationError : IEquatable<ManagedServiceValidationError>
{
    public ManagedServiceValidationError(ManagedServiceValidationErrorKind kind, string? detail = null)
    {
        Kind = kind;
        Detail = detail;
    }

    public ManagedServiceValidationErrorKind Kind { get; }
    public string? Detail { get; }

    public string Message => Kind switch
    {
        ManagedServiceValidationErrorKind.EmptyName => "Enter a service name.",
        ManagedServiceValidationErrorKind.DuplicateName => $"A service named \"{Detail}\" already exists.",
        ManagedServiceValidationErrorKind.EmptyHost => "Enter a host.",
        ManagedServiceValidationErrorKind.PortOutOfRange => $"Port {Detail} must be between 1 and 65535.",
        ManagedServiceValidationErrorKind.DuplicatePort => $"Port {Detail} is already used by another service.",
        ManagedServiceValidationErrorKind.MissingWorkingDirectory => $"Working directory \"{Detail}\" does not exist.",
        ManagedServiceValidationErrorKind.EmptyCommand => "Enter a start command.",
        ManagedServiceValidationErrorKind.UnsupportedPlaceholder => $"Unsupported placeholder \"{Detail}\". Only {{port}} is allowed.",
        ManagedServiceValidationErrorKind.ServiceRunning => "Stop the service before editing it.",
        _ => "Invalid service configuration.",
    };

    public bool Equals(ManagedServiceValidationError? other) =>
        other is not null && Kind == other.Kind && string.Equals(Detail, other.Detail, StringComparison.Ordinal);

    public override bool Equals(object? obj) => Equals(obj as ManagedServiceValidationError);

    public override int GetHashCode() => HashCode.Combine(Kind, Detail);

    public override string ToString() => Message;
}

public interface IManagedServiceDirectoryValidator
{
    bool IsExistingDirectory(string path);
}

public sealed class FileSystemManagedServiceDirectoryValidator : IManagedServiceDirectoryValidator
{
    public bool IsExistingDirectory(string path)
    {
        if (string.IsNullOrWhiteSpace(path)) return false;
        try
        {
            return Directory.Exists(path);
        }
        catch (Exception)
        {
            return false;
        }
    }
}

/// <summary>Pure profile validation. Mirrors macOS ManagedServiceValidator.</summary>
public static class ManagedServiceValidator
{
    /// <summary>
    /// Returns the first validation failure, or null when the profile is valid.
    /// The profile matching <paramref name="config"/>.Id is excluded from duplicate checks.
    /// </summary>
    public static ManagedServiceValidationError? Validate(
        ManagedServiceConfig config,
        IReadOnlyList<ManagedServiceConfig> existing,
        IManagedServiceDirectoryValidator? directoryValidator = null)
    {
        directoryValidator ??= new FileSystemManagedServiceDirectoryValidator();

        var name = (config.Name ?? string.Empty).Trim();
        if (name.Length == 0) return new ManagedServiceValidationError(ManagedServiceValidationErrorKind.EmptyName);

        var others = existing.Where(c => c.Id != config.Id).ToList();
        if (others.Any(c => string.Equals((c.Name ?? string.Empty).Trim(), name, StringComparison.OrdinalIgnoreCase)))
        {
            return new ManagedServiceValidationError(ManagedServiceValidationErrorKind.DuplicateName, name);
        }

        if (config.Port < 1 || config.Port > 65535)
        {
            return new ManagedServiceValidationError(ManagedServiceValidationErrorKind.PortOutOfRange, config.Port.ToString(System.Globalization.CultureInfo.InvariantCulture));
        }
        if (others.Any(c => c.Port == config.Port))
        {
            return new ManagedServiceValidationError(ManagedServiceValidationErrorKind.DuplicatePort, config.Port.ToString(System.Globalization.CultureInfo.InvariantCulture));
        }

        if (string.IsNullOrWhiteSpace(config.Host))
        {
            return new ManagedServiceValidationError(ManagedServiceValidationErrorKind.EmptyHost);
        }

        var command = (config.StartCommand ?? string.Empty).Trim();
        if (command.Length == 0)
        {
            return new ManagedServiceValidationError(ManagedServiceValidationErrorKind.EmptyCommand);
        }

        var placeholder = ManagedServiceCommandRenderer.UnsupportedPlaceholders(command).FirstOrDefault();
        if (placeholder is not null)
        {
            return new ManagedServiceValidationError(ManagedServiceValidationErrorKind.UnsupportedPlaceholder, placeholder);
        }

        var directory = (config.WorkingDirectory ?? string.Empty).Trim();
        if (!directoryValidator.IsExistingDirectory(directory))
        {
            return new ManagedServiceValidationError(ManagedServiceValidationErrorKind.MissingWorkingDirectory, directory);
        }

        return null;
    }
}
