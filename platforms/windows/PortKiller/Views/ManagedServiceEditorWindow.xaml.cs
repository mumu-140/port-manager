using System.Globalization;
using System.Windows;
using PortKiller.Models;
using PortKiller.ViewModels;

namespace PortKiller.Views;

public partial class ManagedServiceEditorWindow : Window
{
    private readonly ManagedServicesViewModel _viewModel;
    private readonly ManagedServiceConfig _config;
    private readonly bool _isNew;

    public ManagedServiceEditorWindow(ManagedServicesViewModel viewModel, ManagedServiceConfig? existing)
    {
        InitializeComponent();
        _viewModel = viewModel;
        _isNew = existing is null;
        _config = existing?.Clone() ?? new ManagedServiceConfig { Host = "localhost" };

        NameBox.Text = _config.Name;
        PortBox.Text = _config.Port > 0 ? _config.Port.ToString(CultureInfo.InvariantCulture) : string.Empty;
        HostBox.Text = _config.Host;
        DirectoryBox.Text = _config.WorkingDirectory;
        CommandBox.Text = _config.StartCommand;
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        if (!int.TryParse(PortBox.Text.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var port))
        {
            ErrorText.Text = "Port must be a number.";
            return;
        }

        _config.Name = NameBox.Text.Trim();
        _config.Port = port;
        _config.Host = HostBox.Text.Trim();
        _config.WorkingDirectory = DirectoryBox.Text.Trim();
        _config.StartCommand = CommandBox.Text;

        var error = _viewModel.SaveProfile(_config, _isNew);
        if (error is not null)
        {
            ErrorText.Text = error.Message;
            return;
        }

        DialogResult = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
