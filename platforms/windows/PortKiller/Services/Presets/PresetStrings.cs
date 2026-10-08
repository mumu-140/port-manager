namespace PortKiller.Services;

/// <summary>
/// Display copy for the preset picker and preset forms, keyed exactly like the
/// macOS ManagedServiceStrings preset/dependency entries. Now backed by the
/// shared <see cref="LocalizationService"/> resource tables so preset UI
/// follows the selected interface language. Call sites are unchanged.
/// </summary>
public static class PresetStrings
{
    /// <summary>Lookup; unknown keys fall back to the key itself (visible, never silent).</summary>
    public static string Lookup(string key) =>
        LocalizationService.Instance[key];

    /// <summary>Formatted lookup for keys with {0}/{1} placeholders.</summary>
    public static string Lookup(string key, params object[] args) =>
        LocalizationService.Instance.Format(key, args);
}
