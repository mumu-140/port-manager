using System;
using System.ComponentModel;
using System.Globalization;
using System.Resources;
using PortKiller.Models;

namespace PortKiller.Services;

/// <summary>
/// Runtime localization. XAML binds through the Loc markup extension
/// (<c>{loc:Loc settings.title}</c>); C# uses <c>Instance["key"]</c>.
/// Changing the language raises <see cref="INotifyPropertyChanged"/> for the
/// indexer so every bound string refreshes live.
/// </summary>
public sealed class LocalizationService : INotifyPropertyChanged
{
    public static LocalizationService Instance { get; } = new();

    private readonly ResourceManager _resources =
        new("PortKiller.Resources.Strings", typeof(LocalizationService).Assembly);

    private CultureInfo _culture = ResolveCulture(AppLanguage.System);

    private LocalizationService() { }

    public event PropertyChangedEventHandler? PropertyChanged;

    /// <summary>Localized string for key; falls back to "!key!" when missing.</summary>
    public string this[string key]
    {
        get
        {
            try
            {
                return _resources.GetString(key, _culture) ?? $"!{key}!";
            }
            catch
            {
                return $"!{key}!";
            }
        }
    }

    public string Format(string key, params object[] args)
    {
        try
        {
            return string.Format(_culture, this[key], args);
        }
        catch
        {
            return this[key];
        }
    }

    public void SetLanguage(AppLanguage language)
    {
        _culture = ResolveCulture(language);
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs("Item[]"));
    }

    public static CultureInfo ResolveCulture(AppLanguage language)
    {
        return language switch
        {
            AppLanguage.SimplifiedChinese => new CultureInfo("zh-CN"),
            AppLanguage.English => new CultureInfo("en"),
            _ => CultureInfo.CurrentUICulture.Name.StartsWith("zh", StringComparison.OrdinalIgnoreCase)
                ? new CultureInfo("zh-CN")
                : new CultureInfo("en"),
        };
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
