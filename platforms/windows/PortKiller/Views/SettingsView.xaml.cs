using System.ComponentModel;
using System.Reflection;
using System.Windows.Controls;
using PortKiller.Services;

namespace PortKiller.Views;

/// <summary>
/// Settings page. Binds to <see cref="ViewModels.MainViewModel"/> via the
/// inherited DataContext from MainWindow.
/// </summary>
public partial class SettingsView : UserControl
{
    public SettingsView()
    {
        InitializeComponent();
        UpdateVersionText();
        LocalizationService.Instance.PropertyChanged += OnLanguageChanged;
        Unloaded += (_, _) => LocalizationService.Instance.PropertyChanged -= OnLanguageChanged;
    }

    private void OnLanguageChanged(object? sender, PropertyChangedEventArgs e)
    {
        UpdateVersionText();
    }

    private void UpdateVersionText()
    {
        var version = Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "1.0.0";
        VersionText.Text = LocalizationService.Instance.Format("settings.about.version", version);
    }
}
