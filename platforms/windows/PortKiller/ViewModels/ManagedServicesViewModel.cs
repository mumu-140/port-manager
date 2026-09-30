using System.Collections.ObjectModel;
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
    private readonly Dispatcher _dispatcher;

    [ObservableProperty] private ObservableCollection<ManagedServiceState> _services = new();
    [ObservableProperty] private ObservableCollection<ManagedServiceState> _filteredServices = new();
    [ObservableProperty] private ManagedServiceState? _selectedService;
    [ObservableProperty] private string _searchText = string.Empty;
    [ObservableProperty] private string? _statusMessage;

    public ManagedServicesViewModel(ManagedServiceManager manager, Dispatcher dispatcher)
    {
        _manager = manager;
        _dispatcher = dispatcher;
    }

    public bool HasSelection => SelectedService is not null;
    public bool CanEdit => SelectedService is { IsTransitioning: false };
    public bool HasConflict => SelectedService?.Conflict is not null;

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
