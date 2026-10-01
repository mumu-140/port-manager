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

        var message = state.Status switch
        {
            ManagedServiceStatus.Running => $"Delete \"{state.Name}\"? The owned service is stopped first.",
            ManagedServiceStatus.Conflict => $"Delete \"{state.Name}\"? The process using port {state.Config.Port} is left running.",
            _ => $"Delete \"{state.Name}\"?",
        };

        var confirm = MessageBox.Show(message, "Delete service", MessageBoxButton.OKCancel, MessageBoxImage.Warning);
        if (confirm != MessageBoxResult.OK) return;
        await vm.DeleteCommand.ExecuteAsync(null);
    }

    private async void ResolveConflict_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm) return;
        await vm.ResolveConflictCommand.ExecuteAsync(null);
    }

    private async void Share_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm) return;
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
