using System;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using Microsoft.Win32;
using PortKiller.Models;

namespace PortKiller.Services;

/// <summary>
/// Applies the selected color theme by inserting a code-built
/// ResourceDictionary at the front of the app's merged dictionaries.
/// Brushes are created in code (not loaded from XAML files) so theme
/// switching can never fail due to pack-URI/resource issues.
/// All app brushes are referenced via DynamicResource, so they update live.
/// </summary>
public static class ThemeService
{
    private const string ThemeDictionaryMarker = "PortKiller.Theme";

    public static void ApplyTheme(AppTheme theme)
    {
        var app = Application.Current;
        if (app == null) return;

        var resolved = ResolveTheme(theme);
        var dict = CreateThemeDictionary(resolved);

        // Remove the previously applied theme dictionary (if any).
        var existing = app.Resources.MergedDictionaries
            .FirstOrDefault(d => d.Contains(ThemeDictionaryMarker));
        if (existing != null)
            app.Resources.MergedDictionaries.Remove(existing);

        // Insert at the front so theme brushes win over later dictionaries.
        app.Resources.MergedDictionaries.Insert(0, dict);
    }

    public static AppTheme ResolveTheme(AppTheme theme)
    {
        if (theme == AppTheme.Light) return AppTheme.Light;
        if (theme == AppTheme.Dark) return AppTheme.Dark;
        return IsSystemDark() ? AppTheme.Dark : AppTheme.Light;
    }

    private static bool IsSystemDark()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            var value = key?.GetValue("AppsUseLightTheme");
            // 0 = dark mode, 1 (or missing) = light mode.
            return value is int i && i == 0;
        }
        catch
        {
            return false;
        }
    }

    private static SolidColorBrush B(string hex)
    {
        hex = hex.TrimStart('#');
        byte a = 0xFF, r, g, b;
        if (hex.Length == 8)
        {
            a = Convert.ToByte(hex.Substring(0, 2), 16);
            r = Convert.ToByte(hex.Substring(2, 2), 16);
            g = Convert.ToByte(hex.Substring(4, 2), 16);
            b = Convert.ToByte(hex.Substring(6, 2), 16);
        }
        else
        {
            r = Convert.ToByte(hex.Substring(0, 2), 16);
            g = Convert.ToByte(hex.Substring(2, 2), 16);
            b = Convert.ToByte(hex.Substring(4, 2), 16);
        }
        var brush = new SolidColorBrush(Color.FromArgb(a, r, g, b));
        brush.Freeze();
        return brush;
    }

    private static ResourceDictionary CreateThemeDictionary(AppTheme theme)
    {
        var dict = new ResourceDictionary();
        if (theme == AppTheme.Dark)
        {
            dict["BrushBackground"] = B("#1A1A1A");
            dict["BrushSurface"] = B("#1E1E1E");
            dict["BrushCard"] = B("#252525");
            dict["BrushCardHover"] = B("#2C2C2C");
            dict["BrushField"] = B("#2A2A2A");
            dict["BrushBorder"] = B("#303030");
            dict["BrushBorderHover"] = B("#3D3D3D");
            dict["BrushTextPrimary"] = B("#F0F0F0");
            dict["BrushTextSecondary"] = B("#A8A8A8");
            dict["BrushTextTertiary"] = B("#6F6F6F");
            dict["BrushAccent"] = B("#4EA1F3");
            dict["BrushSuccess"] = B("#2ECC71");
            dict["BrushWarning"] = B("#F4AB3A");
            dict["BrushDanger"] = B("#E74C3C");
            dict["BrushFavorite"] = B("#FFC933");
            dict["BrushSuccessTint"] = B("#262ECC71");
            dict["BrushWarningTint"] = B("#26F4AB3A");
            dict["BrushDangerTint"] = B("#26E74C3C");
            dict["BrushAccentTint"] = B("#264EA1F3");
        }
        else
        {
            dict["BrushBackground"] = B("#F3F3F3");
            dict["BrushSurface"] = B("#FFFFFF");
            dict["BrushCard"] = B("#FFFFFF");
            dict["BrushCardHover"] = B("#F5F5F5");
            dict["BrushField"] = B("#F5F5F5");
            dict["BrushBorder"] = B("#E2E2E2");
            dict["BrushBorderHover"] = B("#C9C9C9");
            dict["BrushTextPrimary"] = B("#1A1A1A");
            dict["BrushTextSecondary"] = B("#5C5C5C");
            dict["BrushTextTertiary"] = B("#8A8A8A");
            dict["BrushAccent"] = B("#2B7CD3");
            dict["BrushSuccess"] = B("#1E9E5A");
            dict["BrushWarning"] = B("#B87A1A");
            dict["BrushDanger"] = B("#D33F2E");
            dict["BrushFavorite"] = B("#9A7B00");
            dict["BrushSuccessTint"] = B("#261E9E5A");
            dict["BrushWarningTint"] = B("#26B87A1A");
            dict["BrushDangerTint"] = B("#26D33F2E");
            dict["BrushAccentTint"] = B("#262B7CD3");
        }
        dict[ThemeDictionaryMarker] = theme.ToString();
        return dict;
    }
}
