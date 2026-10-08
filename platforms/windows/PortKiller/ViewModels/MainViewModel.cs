using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using System.Windows.Threading;
using PortKiller.Models;
using PortKiller.Services;

namespace PortKiller.ViewModels;

/// <summary>
/// Main view model managing application state and port operations.
/// Equivalent to macOS AppState.swift
/// </summary>
public partial class MainViewModel : ObservableObject, IPortScanCoordinator
{
    private readonly PortScannerService _scanner;
    private readonly ProcessKillerService _killer;
    private readonly SettingsService _settings;
    private readonly NotificationService _notifications;
    private readonly Dispatcher _dispatcher;
    private readonly ManagedServiceManager? _managedServices;
    
    private CancellationTokenSource? _refreshCancellation;
    private Dictionary<int, bool> _previousPortStates = new();

    // Observable Properties
    [ObservableProperty]
    private ObservableCollection<PortInfo> _ports = new();

    [ObservableProperty]
    private ObservableCollection<PortInfo> _filteredPorts = new();

    [ObservableProperty]
    private bool _isScanning;

    [ObservableProperty]
    private PortInfo? _selectedPort;

    [ObservableProperty]
    private SidebarItem _selectedSidebarItem = SidebarItem.AllPorts;

    [ObservableProperty]
    private PortFilter _filter = new();

    [ObservableProperty]
    private HashSet<int> _favorites = new();

    [ObservableProperty]
    private List<WatchedPort> _watchedPorts = new();

    [ObservableProperty]
    private int _refreshInterval = 5;

    [ObservableProperty]
    private bool _showNotifications = true;

    [ObservableProperty]
    private bool _autoStart;

    [ObservableProperty]
    private Models.AppLanguage _language = Models.AppLanguage.System;

    [ObservableProperty]
    private Models.AppTheme _theme = Models.AppTheme.System;

    [ObservableProperty]
    private bool _hideSystemProcesses;

    [ObservableProperty]
    private bool _skipKillConfirmation;

    public MainViewModel(
        PortScannerService scanner,
        ProcessKillerService killer,
        SettingsService settings,
        NotificationService notifications,
        Dispatcher dispatcher,
        ManagedServiceManager? managedServices = null)
    {
        _scanner = scanner;
        _killer = killer;
        _settings = settings;
        _notifications = notifications;
        _dispatcher = dispatcher;
        _managedServices = managedServices;

        LoadSettings();
    }

    partial void OnSelectedSidebarItemChanged(SidebarItem value)
    {
        UpdateFilteredPorts();
    }

    partial void OnFilterChanged(PortFilter value)
    {
        UpdateFilteredPorts();
    }

    partial void OnAutoStartChanged(bool value)
    {
        _settings.SaveAutoStart(value);
        _settings.SetStartupRegistered(value);
    }

    partial void OnRefreshIntervalChanged(int value)
    {
        _settings.SaveRefreshInterval(value);
    }

    partial void OnShowNotificationsChanged(bool value)
    {
        _settings.SaveShowNotifications(value);
    }

    partial void OnLanguageChanged(Models.AppLanguage value)
    {
        _settings.SaveLanguage(value.ToString());
        Services.LocalizationService.Instance.SetLanguage(value);
    }

    partial void OnThemeChanged(Models.AppTheme value)
    {
        _settings.SaveTheme(value.ToString());
        Services.ThemeService.ApplyTheme(value);
    }

    partial void OnHideSystemProcessesChanged(bool value)
    {
        _settings.SaveHideSystemProcesses(value);
        UpdateFilteredPorts();
    }

    partial void OnSkipKillConfirmationChanged(bool value)
    {
        _settings.SaveSkipKillConfirmation(value);
    }

    // Initialization
    public async Task InitializeAsync()
    {
        _notifications.Initialize();
        await RefreshPortsAsync();
        StartAutoRefresh();
    }

    // Settings Management
    private void LoadSettings()
    {
        Favorites = _settings.GetFavorites();
        WatchedPorts = _settings.GetWatchedPorts();
        RefreshInterval = _settings.GetRefreshInterval();
        ShowNotifications = _settings.GetShowNotifications();
        // The registry is the source of truth for the toggle; a stored value
        // that drifted (e.g. removed externally) is corrected on change.
        AutoStart = _settings.IsStartupRegistered();
        if (Enum.TryParse<Models.AppLanguage>(_settings.GetLanguage(), out var language))
            Language = language;
        if (Enum.TryParse<Models.AppTheme>(_settings.GetTheme(), out var theme))
            Theme = theme;
        HideSystemProcesses = _settings.GetHideSystemProcesses();
        SkipKillConfirmation = _settings.GetSkipKillConfirmation();
    }

    private void SaveSettings()
    {
        _settings.SaveFavorites(Favorites);
        _settings.SaveWatchedPorts(WatchedPorts);
        _settings.SaveRefreshInterval(RefreshInterval);
        _settings.SaveShowNotifications(ShowNotifications);
    }

    // Port Scanning
    [RelayCommand]
    public async Task RefreshPortsAsync()
    {
        if (IsScanning)
            return;

        IsScanning = true;

        try
        {
            // Snapshot lifecycle generations before scanning so reconciliation
            // never applies this scan across a newer Start/Stop/Restart.
            var lifecycle = _managedServices?.CaptureLifecycleSnapshot();
            var scannedPorts = await _scanner.ScanPortsAsync();
            
            // Update on UI thread
            _dispatcher.Invoke(() =>
            {
                Ports.Clear();
                foreach (var port in scannedPorts)
                {
                    Ports.Add(port);
                }

                UpdateFilteredPorts();
                CheckWatchedPorts();
            });

            // The same scan that refreshes the port list reconciles managed
            // services, so a normal refresh keeps their state honest without a
            // second polling loop (design notes, section 6.4).
            if (_managedServices is not null)
            {
                await _managedServices.ReconcileAsync(
                    scannedPorts,
                    lifecycle ?? _managedServices.CaptureLifecycleSnapshot()).ConfigureAwait(false);
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error refreshing ports: {ex.Message}");
        }
        finally
        {
            IsScanning = false;
        }
    }

    // Auto-refresh
    private void StartAutoRefresh()
    {
        _refreshCancellation?.Cancel();
        _refreshCancellation = new CancellationTokenSource();
        var token = _refreshCancellation.Token;

        Task.Run(async () =>
        {
            while (!token.IsCancellationRequested)
            {
                try
                {
                    await Task.Delay(TimeSpan.FromSeconds(RefreshInterval), token);
                    if (!token.IsCancellationRequested)
                    {
                        await RefreshPortsAsync();
                    }
                }
                catch (TaskCanceledException)
                {
                    break;
                }
            }
        }, token);
    }

    public void StopAutoRefresh()
    {
        _refreshCancellation?.Cancel();
    }

    // Port Operations
    [RelayCommand]
    public async Task KillProcessAsync(PortInfo? port)
    {
        if (port == null || !port.IsActive)
            return;

        try
        {
            // Set UI state for spinner
            port.IsKilling = true;
            
            var success = await _killer.KillProcessGracefullyAsync(port.Pid);
            if (success)
            {
                // Refresh immediately to show change
                await Task.Delay(500);
                await RefreshPortsAsync();
            }
            else
            {
                // Reset state if failed (and still in list)
                port.IsKilling = false;
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Error killing process: {ex.Message}");
            port.IsKilling = false;
        }
    }

    // Favorites Management
    [RelayCommand]
    public void ToggleFavorite(int port)
    {
        if (Favorites.Contains(port))
        {
            Favorites.Remove(port);
        }
        else
        {
            Favorites.Add(port);
        }

        // Trigger property change
        OnPropertyChanged(nameof(Favorites));
        SaveSettings();
        UpdateFilteredPorts();
    }

    public bool IsFavorite(int port) => Favorites.Contains(port);

    // Watched Ports Management
    [RelayCommand]
    public void AddWatchedPort(int port)
    {
        if (!WatchedPorts.Any(w => w.Port == port))
        {
            WatchedPorts.Add(new WatchedPort { Port = port });
            OnPropertyChanged(nameof(WatchedPorts));
            SaveSettings();
            UpdateFilteredPorts();
        }
    }

    [RelayCommand]
    public void RemoveWatchedPort(int port)
    {
        var watched = WatchedPorts.FirstOrDefault(w => w.Port == port);
        if (watched != null)
        {
            WatchedPorts.Remove(watched);
            OnPropertyChanged(nameof(WatchedPorts));
            SaveSettings();
            UpdateFilteredPorts();
        }
    }

    public bool IsWatched(int port) => WatchedPorts.Any(w => w.Port == port);

    // Watched Port Notifications
    private void CheckWatchedPorts()
    {
        if (!ShowNotifications)
            return;

        var activePorts = Ports.Where(p => p.IsActive).Select(p => p.Port).ToHashSet();

        foreach (var watched in WatchedPorts)
        {
            var isActive = activePorts.Contains(watched.Port);
            var wasActive = _previousPortStates.GetValueOrDefault(watched.Port, false);

            // Port just started
            if (isActive && !wasActive && watched.NotifyOnStart)
            {
                var portInfo = Ports.First(p => p.Port == watched.Port);
                _notifications.NotifyPortStarted(watched.Port, portInfo.ProcessName);
            }

            // Port just stopped
            if (!isActive && wasActive && watched.NotifyOnStop)
            {
                _notifications.NotifyPortStopped(watched.Port);
            }

            _previousPortStates[watched.Port] = isActive;
        }
    }

    // Filtering
    private void UpdateFilteredPorts()
    {
        var result = GetFilteredPorts();
        
        FilteredPorts.Clear();
        foreach (var port in result)
        {
            FilteredPorts.Add(port);
        }
    }

    private List<PortInfo> GetFilteredPorts()
    {
        // Start with all or filtered by sidebar
        var result = SelectedSidebarItem switch
        {
            SidebarItem.AllPorts => Ports.ToList(),
            SidebarItem.Favorites => GetFavoritePorts(),
            SidebarItem.Watched => GetWatchedPortInfos(),
            SidebarItem.Settings => new List<PortInfo>(),
            _ when SelectedSidebarItem.GetProcessType() is ProcessType type 
                => Ports.Where(p => p.ProcessType == type).ToList(),
            _ => Ports.ToList()
        };

        // Apply additional filters
        if (Filter.IsActive)
        {
            result = result.Where(p => Filter.Matches(p, Favorites, WatchedPorts)).ToList();
        }

        // Hide system processes (e.g. System, Registry, services) when enabled.
        if (HideSystemProcesses)
        {
            result = result.Where(p => p.ProcessType != ProcessType.System).ToList();
        }

        return result.OrderBy(p => p.Port).ToList();
    }

    private List<PortInfo> GetFavoritePorts()
    {
        var result = new List<PortInfo>();
        var activePorts = Ports.ToLookup(p => p.Port);

        foreach (var favPort in Favorites)
        {
            var activePort = activePorts[favPort].FirstOrDefault();
            if (activePort != null)
            {
                result.Add(activePort);
            }
            else
            {
                result.Add(PortInfo.Inactive(favPort));
            }
        }

        return result;
    }

    private List<PortInfo> GetWatchedPortInfos()
    {
        var result = new List<PortInfo>();
        var activePorts = Ports.ToLookup(p => p.Port);

        foreach (var watched in WatchedPorts)
        {
            var activePort = activePorts[watched.Port].FirstOrDefault();
            if (activePort != null)
            {
                result.Add(activePort);
            }
            else
            {
                result.Add(PortInfo.Inactive(watched.Port));
            }
        }

        return result;
    }

    // Search
    public void Search(string query)
    {
        Filter.SearchText = query;
        OnPropertyChanged(nameof(Filter));
        UpdateFilteredPorts();
    }

    public void ClearSearch()
    {
        Filter.SearchText = string.Empty;
        OnPropertyChanged(nameof(Filter));
        UpdateFilteredPorts();
    }
}
