using System.Windows.Controls;

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
    }
}
