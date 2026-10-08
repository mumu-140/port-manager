using System;
using System.ComponentModel;
using PortKiller.Models;

namespace PortKiller.Services;

/// <summary>
/// Runtime localization. XAML binds through the Loc markup extension
/// (<c>{loc:Loc settings.title}</c>); C# uses <c>Instance["key"]</c>.
/// Changing the language raises <see cref="INotifyPropertyChanged"/> for the
/// indexer so every bound string refreshes live. Strings live in compiled
/// dictionaries (<see cref="LocalizedStrings"/>) so lookup can never fail
/// due to satellite-assembly/publish issues.
/// </summary>
public sealed class LocalizationService : INotifyPropertyChanged
{
    public static LocalizationService Instance { get; } = new();

    private System.Collections.Generic.Dictionary<string, string> _strings =
        LocalizedStrings.En;

    private LocalizationService() { }

    public event PropertyChangedEventHandler? PropertyChanged;

    /// <summary>Localized string for key; falls back to "!key!" when missing.</summary>
    public string this[string key]
    {
        get
        {
            if (_strings.TryGetValue(key, out var value))
                return value;
            // Fall back to English before giving up.
            if (LocalizedStrings.En.TryGetValue(key, out var en))
                return en;
            return $"!{key}!";
        }
    }

    public string Format(string key, params object[] args)
    {
        try
        {
            return string.Format(this[key], args);
        }
        catch
        {
            return this[key];
        }
    }

    public void SetLanguage(AppLanguage language)
    {
        _strings = language switch
        {
            AppLanguage.SimplifiedChinese => LocalizedStrings.ZhCn,
            AppLanguage.English => LocalizedStrings.En,
            _ => IsChineseCulture() ? LocalizedStrings.ZhCn : LocalizedStrings.En,
        };
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs("Item[]"));
    }

    private static bool IsChineseCulture()
    {
        try
        {
            return System.Globalization.CultureInfo.CurrentUICulture.Name
                .StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            return false;
        }
    }

    public static string GetDisplayName(AppLanguage language, LocalizationService? loc = null)
    {
        loc ??= Instance;
        return language switch
        {
            AppLanguage.System => loc["settings.language.system"],
            AppLanguage.English => loc["settings.language.english"],
            AppLanguage.SimplifiedChinese => loc["settings.language.simplifiedChinese"],
            _ => language.ToString(),
        };
    }
}
