using System.Windows;
using System.Windows.Controls;
using PortKiller.Models;
using PortKiller.ViewModels;

namespace PortKiller.Views;

public partial class ManagedServicesView : UserControl
{
    public ManagedServicesView()
    {
        InitializeComponent();
    }

    private ManagedServicesViewModel? ViewModel => DataContext as ManagedServicesViewModel;

    private void Add_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm) return;
        var editor = new ManagedServiceEditorWindow(vm, null) { Owner = Window.GetWindow(this) };
        editor.ShowDialog();
    }

    /// <summary>
    /// Editing always stops a running service first (design notes, section 12).
    /// The editor opens only once the service has reached Stopped, and saving
    /// never restarts it.
    /// </summary>
    private async void Edit_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm || vm.SelectedService is not { } state) return;
        if (state.IsTransitioning) return;

        if (state.IsOwned)
        {
            var confirm = MessageBox.Show(
                $"Stop \"{state.Name}\" before editing? The service is stopped first and is not restarted automatically.",
                "Edit service", MessageBoxButton.OKCancel, MessageBoxImage.Question);
            if (confirm != MessageBoxResult.OK) return;

            var stopped = await vm.PrepareForEditAsync();
            if (!stopped || state.IsOwned || state.Status != ManagedServiceStatus.Stopped)
            {
                MessageBox.Show(
                    vm.StatusMessage ?? $"Could not stop \"{state.Name}\".",
                    "Edit service", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
        }

        var editor = new ManagedServiceEditorWindow(vm, state.Config) { Owner = Window.GetWindow(this) };
        editor.ShowDialog();
    }

    private async void Refresh_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm) return;
        await vm.RefreshAsync();
    }

    private async void Start_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm) return;
        await vm.StartCommand.ExecuteAsync(null);
    }

    private async void Stop_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm) return;
        await vm.StopCommand.ExecuteAsync(null);
    }

    private async void Restart_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm) return;
        await vm.RestartCommand.ExecuteAsync(null);
    }

    private void Open_Click(object sender, RoutedEventArgs e)
    {
        ViewModel?.OpenCommand.Execute(null);
    }

    /// <summary>
    /// Deleting a conflict profile removes configuration only; the process
    /// holding the port is never signalled from here.
    /// </summary>
    private async void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm || vm.SelectedService is not { } state) return;
        if (state.IsTransitioning)
        {
            MessageBox.Show(
                $"Wait for \"{state.Name}\" to finish its current operation.",
                "Delete service", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        // Semantic delete copy (design section 8.1): state -> message + destructive
        // button text, presented as a native task dialog so the button label can
        // carry the semantics (Stop & Delete / Delete / Delete Configuration Only).
        var copy = PortKiller.Services.ManagedServiceDeleteCopy.For(new PortKiller.Services.ManagedServiceDeleteContext
        {
            Name = state.Name,
            Port = state.Config.Port,
            IsOwnedRunning = state.Status == ManagedServiceStatus.Running && state.IsOwned,
            IsConflict = state.Status == ManagedServiceStatus.Conflict,
            HasQuickTunnel = vm.HasServiceTunnel,
        });

        var confirmButton = new System.Windows.Forms.TaskDialogButton(copy.ButtonText);
        var page = new System.Windows.Forms.TaskDialogPage
        {
            Caption = "Delete service",
            Text = copy.Message,
            Icon = System.Windows.Forms.TaskDialogIcon.Warning,
            Buttons = { confirmButton, System.Windows.Forms.TaskDialogButton.Cancel },
        };

        var owner = new System.Windows.Interop.WindowInteropHelper(Window.GetWindow(this)).Handle;
        var result = System.Windows.Forms.TaskDialog.ShowDialog(owner, page);
        if (result != confirmButton) return;
        await vm.DeleteCommand.ExecuteAsync(null);
    }

    private async void ResolveConflict_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm) return;
        await vm.ResolveConflictCommand.ExecuteAsync(null);
    }

    private async void Share_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm || vm.SelectedService is not { } state) return;

        // Exposure double-warning gate (design section 10.2): writable Dufs
        // and public Jupyter confirm before their Quick Tunnel starts;
        // everything else shares exactly as today.
        var warning = PortKiller.Services.ManagedServiceExposureWarning.MessageFor(state.Config);
        if (warning is not null)
        {
            var confirm = MessageBox.Show(
                PortKiller.Services.PresetStrings.Lookup(warning),
                PortKiller.Services.PresetStrings.Lookup("exposure.confirm.title"),
                MessageBoxButton.OKCancel, MessageBoxImage.Warning);
            if (confirm != MessageBoxResult.OK) return;
        }

        await vm.ShareServiceCommand.ExecuteAsync(null);
    }

    private async void StopTunnel_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm) return;
        await vm.StopTunnelCommand.ExecuteAsync(null);
    }

    private void CopyTunnelUrl_Click(object sender, RoutedEventArgs e)
    {
        ViewModel?.CopyTunnelUrlCommand.Execute(null);
    }

    private void OpenTunnelUrl_Click(object sender, RoutedEventArgs e)
    {
        ViewModel?.OpenTunnelUrlCommand.Execute(null);
    }
}
