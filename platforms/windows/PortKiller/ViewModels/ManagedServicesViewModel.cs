using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using System.Diagnostics;
using System.Windows.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PortKiller.Models;
using PortKiller.Services;

namespace PortKiller.ViewModels;

/// <summary>
/// WPF-facing wrapper around <see cref="ManagedServiceManager"/>. Lifecycle
/// logic stays in the manager; this type only projects state and marshals
/// commands.
/// </summary>
public partial class ManagedServicesViewModel : ObservableObject
{
    private readonly ManagedServiceManager _manager;
    private readonly TunnelViewModel _tunnels;
    private readonly Dispatcher _dispatcher;

    [ObservableProperty] private ObservableCollection<ManagedServiceState> _services = new();
    [ObservableProperty] private ObservableCollection<ManagedServiceState> _filteredServices = new();
    [ObservableProperty] private ManagedServiceState? _selectedService;
    [ObservableProperty] private string _searchText = string.Empty;
    [ObservableProperty] private string? _statusMessage;

    public ManagedServicesViewModel(ManagedServiceManager manager, TunnelViewModel tunnels, Dispatcher dispatcher)
    {
        _manager = manager;
        _tunnels = tunnels;
        _dispatcher = dispatcher;

        _tunnels.Tunnels.CollectionChanged += OnTunnelCollectionChanged;
        foreach (var tunnel in _tunnels.Tunnels) tunnel.PropertyChanged += OnTunnelPropertyChanged;
    }

    public bool HasSelection => SelectedService is not null;
    public bool CanEdit => SelectedService is { IsTransitioning: false };
    public bool HasConflict => SelectedService?.Conflict is not null;

    // MARK: - Quick Tunnel projection

    public CloudflareTunnel? ServiceTunnel => SelectedService is { } state
        ? _tunnels.Tunnels.FirstOrDefault(t => t.Port == state.Config.Port)
        : null;

    public bool HasServiceTunnel => ServiceTunnel is not null;

    public bool CanShareService =>
        SelectedService?.Status == ManagedServiceStatus.Running && !HasServiceTunnel;

    public bool CanStopTunnel => ServiceTunnel is { Status: not TunnelStatus.Starting };

    public string? ServiceTunnelUrl => ServiceTunnel?.TunnelUrl;

    public bool HasServiceTunnelUrl => !string.IsNullOrEmpty(ServiceTunnelUrl);

    public string ServiceTunnelStatusText => ServiceTunnel switch
    {
        null => "Not shared",
        { Status: TunnelStatus.Starting } => "Tunnel starting",
        { Status: TunnelStatus.Active } => "Public endpoint active",
        { Status: TunnelStatus.Stopping } => "Tunnel stopping",
        { Status: TunnelStatus.Error, LastError: not null } tunnel => tunnel.LastError!,
        { Status: TunnelStatus.Error } => "Tunnel error",
        _ => "Tunnel idle",
    };

    public void Load()
    {
        var states = _manager.Load();
        Services = new ObservableCollection<ManagedServiceState>(states);
        ApplyFilter();
        SelectedService = Services.FirstOrDefault();
    }

    /// <summary>Reconciles runtime state with a fresh scan of the shared scanner.</summary>
    public async Task RefreshAsync()
    {
        await _manager.ReconcileWithScanAsync().ConfigureAwait(true);
        ApplyFilter();
        OnPropertyChanged(nameof(HasConflict));
    }

    partial void OnSearchTextChanged(string value) => ApplyFilter();

    partial void OnSelectedServiceChanged(ManagedServiceState? value)
    {
        OnPropertyChanged(nameof(HasSelection));
        OnPropertyChanged(nameof(CanEdit));
        OnPropertyChanged(nameof(HasConflict));
        NotifyTunnelChanged();
    }

    private void OnTunnelCollectionChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        if (e.OldItems is not null)
        {
            foreach (CloudflareTunnel tunnel in e.OldItems) tunnel.PropertyChanged -= OnTunnelPropertyChanged;
        }
        if (e.NewItems is not null)
        {
            foreach (CloudflareTunnel tunnel in e.NewItems) tunnel.PropertyChanged += OnTunnelPropertyChanged;
        }
        NotifyTunnelChanged();
    }

    private void OnTunnelPropertyChanged(object? sender, PropertyChangedEventArgs e) => NotifyTunnelChanged();

    private void NotifyTunnelChanged()
    {
        OnPropertyChanged(nameof(ServiceTunnel));
        OnPropertyChanged(nameof(HasServiceTunnel));
        OnPropertyChanged(nameof(CanShareService));
        OnPropertyChanged(nameof(CanStopTunnel));
        OnPropertyChanged(nameof(ServiceTunnelUrl));
        OnPropertyChanged(nameof(HasServiceTunnelUrl));
        OnPropertyChanged(nameof(ServiceTunnelStatusText));
    }

    private void ApplyFilter()
    {
        var query = SearchText?.Trim() ?? string.Empty;
        var items = string.IsNullOrEmpty(query)
            ? Services
            : new ObservableCollection<ManagedServiceState>(
                Services.Where(s =>
                    s.Name.Contains(query, StringComparison.OrdinalIgnoreCase) ||
                    s.Config.Port.ToString().Contains(query, StringComparison.OrdinalIgnoreCase)));

        FilteredServices = new ObservableCollection<ManagedServiceState>(items);
        if (SelectedService is null || !FilteredServices.Contains(SelectedService))
        {
            SelectedService = FilteredServices.FirstOrDefault();
        }
        NotifyTunnelChanged();
    }

    private ManagedServiceState? RequireSelection()
    {
        if (SelectedService is null) StatusMessage = "Select a service first.";
        return SelectedService;
    }

    [RelayCommand]
    private async Task StartAsync()
    {
        if (RequireSelection() is not { } state) return;
        var ok = await _manager.StartAsync(state.Id).ConfigureAwait(true);
        StatusMessage = ok ? $"{state.Name} is running." : state.LastError ?? $"Could not start {state.Name}.";
        ApplyFilter();
    }

    [RelayCommand]
    private async Task StopAsync()
    {
        if (RequireSelection() is not { } state) return;
        var ok = await _manager.StopAsync(state.Id).ConfigureAwait(true);
        StatusMessage = ok ? $"{state.Name} stopped." : state.LastError ?? $"Could not stop {state.Name}.";
        ApplyFilter();
    }

    [RelayCommand]
    private async Task RestartAsync()
    {
        if (RequireSelection() is not { } state) return;
        var ok = await _manager.RestartAsync(state.Id).ConfigureAwait(true);
        StatusMessage = ok ? $"{state.Name} restarted." : state.LastError ?? $"Could not restart {state.Name}.";
        ApplyFilter();
    }

    [RelayCommand]
    private async Task ResolveConflictAsync()
    {
        if (RequireSelection() is not { } state) return;
        var ok = await _manager.ResolveConflictAndStartAsync(state.Id).ConfigureAwait(true);
        StatusMessage = ok ? $"{state.Name} is running." : state.LastError ?? "Conflict could not be resolved.";
        ApplyFilter();
    }

    [RelayCommand]
    private async Task StopForEditAsync()
    {
        if (RequireSelection() is not { } state) return;
        await _manager.StopForEditingAsync(state.Id).ConfigureAwait(true);
        ApplyFilter();
    }

    [RelayCommand]
    private void Open()
    {
        if (RequireSelection() is not { } state) return;
        if (state.Status != ManagedServiceStatus.Running)
        {
            StatusMessage = "Start the service before opening it.";
            return;
        }

        var url = $"http://{state.Config.NormalizedHost}:{state.Config.Port}";
        try
        {
            Process.Start(new ProcessStartInfo { FileName = url, UseShellExecute = true });
            StatusMessage = $"Opened {url}.";
        }
        catch (Exception ex)
        {
            StatusMessage = $"Could not open {url}: {ex.Message}";
        }
    }

    [RelayCommand]
    private async Task ShareServiceAsync()
    {
        if (RequireSelection() is not { } state) return;
        if (state.Status != ManagedServiceStatus.Running)
        {
            StatusMessage = "Start the service before sharing it.";
            return;
        }

        await _tunnels.StartTunnelAsync(state.Config.Port).ConfigureAwait(true);
        NotifyTunnelChanged();
        StatusMessage = $"Sharing {state.Name} on port {state.Config.Port}.";
    }

    [RelayCommand]
    private async Task StopTunnelAsync()
    {
        if (RequireSelection() is not { } state) return;
        var tunnel = _tunnels.Tunnels.FirstOrDefault(t => t.Port == state.Config.Port);
        if (tunnel is null) return;
        await _tunnels.StopTunnelAsync(tunnel).ConfigureAwait(true);
        NotifyTunnelChanged();
        StatusMessage = $"Stopped sharing {state.Name}.";
    }

    [RelayCommand]
    private void CopyTunnelUrl()
    {
        if (ServiceTunnelUrl is { Length: > 0 } url) _tunnels.CopyUrlToClipboard(url);
    }

    [RelayCommand]
    private void OpenTunnelUrl()
    {
        if (ServiceTunnelUrl is { Length: > 0 } url) _tunnels.OpenUrlInBrowser(url);
    }

    [RelayCommand]
    private async Task DeleteAsync()
    {
        if (RequireSelection() is not { } state) return;
        if (state.Status == ManagedServiceStatus.Running || state.IsTransitioning)
        {
            await _manager.StopAsync(state.Id).ConfigureAwait(true);
        }

        await _manager.RemoveAsync(state.Id).ConfigureAwait(true);
        Services.Remove(state);
        ApplyFilter();
        StatusMessage = $"{state.Name} deleted.";
    }

    public ManagedServiceValidationError? SaveProfile(ManagedServiceConfig config, bool isNew)
    {
        var error = isNew ? _manager.Add(config) : _manager.Update(config);
        if (error is not null)
        {
            StatusMessage = error.Message;
            return error;
        }

        if (isNew)
        {
            var state = _manager.Find(config.Id);
            if (state is not null)
            {
                Services.Add(state);
                SelectedService = state;
            }
        }

        ApplyFilter();
        StatusMessage = $"{config.Name} saved.";
        return null;
    }

    public void NotifySelectedChanged()
    {
        OnPropertyChanged(nameof(HasSelection));
        OnPropertyChanged(nameof(CanEdit));
        OnPropertyChanged(nameof(HasConflict));
    }
}
