using System;
using System.Linq;
using System.Windows;
using PortKiller.Models;

namespace PortKiller.Services;

/// <summary>
/// Runtime theme switching. Theme brushes live in Themes/Dark.xaml and
/// Themes/Light.xaml under identical keys; every usage is a DynamicResource
/// so swapping the merged dictionary repaints the whole app live.
/// </summary>
public static class ThemeService
{
    private const string ThemeDictionaryMarker = "PortKiller.Theme";

    public static void ApplyTheme(AppTheme theme)
    {
        var resolved = ResolveTheme(theme);
        var source = new Uri($"pack://application,,,/Themes/{resolved}.xaml", UriKind.Absolute);

        var app = Application.Current;
        if (app == null) return;

        // Remove the previously applied theme dictionary (if any).
        var existing = app.Resources.MergedDictionaries
            .FirstOrDefault(d => d.Contains(ThemeDictionaryMarker));
        if (existing != null)
            app.Resources.MergedDictionaries.Remove(existing);

        var dict = new ResourceDictionary { Source = source };
        // Marker key so we can find and replace this dictionary later.
        dict[ThemeDictionaryMarker] = resolved.ToString();
        // Insert at the front so theme brushes win over later dictionaries.
        app.Resources.MergedDictionaries.Insert(0, dict);
    }

    public static AppTheme ResolveTheme(AppTheme theme)
    {
        if (theme == AppTheme.Light) return AppTheme.Light;
        if (theme == AppTheme.Dark) return AppTheme.Dark;
        return IsSystemLightTheme() ? AppTheme.Light : AppTheme.Dark;
    }

    /// <summary>
    /// Reads the Windows app theme. Missing key or any error means light
    /// (Windows default).
    /// </summary>
    public static bool IsSystemLightTheme()
    {
        try
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", writable: false);
            var value = key?.GetValue("AppsUseLightTheme");
            if (value is int i) return i != 0;
            return true;
        }
        catch
        {
            return true;
        }
    }

    public static string GetDisplayName(AppTheme theme, LocalizationService? loc = null)
    {
        loc ??= LocalizationService.Instance;
        return theme switch
        {
            AppTheme.System => loc["settings.theme.system"],
            AppTheme.Light => loc["settings.theme.light"],
            AppTheme.Dark => loc["settings.theme.dark"],
            _ => theme.ToString(),
        };
    }
}
