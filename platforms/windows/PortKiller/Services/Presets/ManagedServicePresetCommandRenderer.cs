namespace PortKiller.Services;

/// <summary>
/// Pure rendering helpers for preset start commands on Windows.
/// Mirrors macOS ManagedServicePresetCommandRenderer (different strategy).
///
/// Presets differ from the custom editor: the app composes the command from
/// user-controlled field values, so the app owns safe rendering. The launcher
/// runs commands via cmd.exe /d /s /c, whose parse rules (percent expansion
/// even inside double quotes, quote stripping, backslash-quote rules) make
/// after-the-fact escaping unreliable. The strategy is therefore
/// constrain-and-quote: field charsets reject the metacharacters, and
/// path-like values are double-quoted here (with trailing-backslash doubling
/// per MSVCRT/CommandLineToArgvW rules).
///
/// The custom-command renderer (ManagedServiceCommandRenderer) is deliberately
/// untouched: custom service stays user-authored shell input.
/// </summary>
public static class ManagedServicePresetCommandRenderer
{
    /// <summary>
    /// Wraps a path-like value in double quotes. Values reaching this must
    /// already pass PresetFieldCharset.Path (no double-quote, no percent, no
    /// newlines), so quoting is safe. Doubles a trailing backslash so the
    /// closing quote is not treated as an escaped literal quote.
    /// </summary>
    public static string QuotePath(string value)
    {
        var trailingBackslashes = 0;
        for (var i = value.Length - 1; i >= 0 && value[i] == '\\'; i--)
        {
            trailingBackslashes++;
        }
        if (trailingBackslashes % 2 == 1)
        {
            value += '\\';
        }
        return "\"" + value + "\"";
    }
}
