using System.Windows;
using System.Windows.Controls;
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

    private void Edit_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm || vm.SelectedService is null) return;
        var editor = new ManagedServiceEditorWindow(vm, vm.SelectedService.Config) { Owner = Window.GetWindow(this) };
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

    private async void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (ViewModel is not { } vm || vm.SelectedService is null) return;
        var confirm = MessageBox.Show(
            $"Delete \"{vm.SelectedService.Name}\"? A running service is stopped first.",
            "Delete service", MessageBoxButton.OKCancel, MessageBoxImage.Warning);
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
