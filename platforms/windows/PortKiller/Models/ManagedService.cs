using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json.Serialization;

namespace PortKiller.Models;

/// <summary>
/// Persisted user configuration describing one local foreground service.
/// Mirrors macOS ManagedServiceConfig.
/// </summary>
public sealed class ManagedServiceConfig
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = string.Empty;
    public int Port { get; set; }
    public string Host { get; set; } = "localhost";
    public string WorkingDirectory { get; set; } = string.Empty;
    public string StartCommand { get; set; } = string.Empty;

    /// <summary>
    /// Preset that produced this profile, if any (design: presets-exposure, section 4.1).
    /// Purely presentational/editing metadata: null on custom profiles, never read by
    /// the manager lifecycle, and absence on pre-preset profiles deserializes to null.
    /// Unknown preset IDs degrade to custom editing.
    /// </summary>
    public string? PresetId { get; set; }

    /// <summary>
    /// Host used for display and Open. Wildcard bind hosts normalize to localhost.
    /// </summary>
    [JsonIgnore]
    public string NormalizedHost
    {
        get
        {
            var trimmed = (Host ?? string.Empty).Trim();
            if (trimmed.Length == 0) return "localhost";
            return trimmed switch
            {
                "0.0.0.0" => "localhost",
                "*" => "localhost",
                "::" => "localhost",
                "[::]" => "localhost",
                _ => trimmed
            };
        }
    }

    public ManagedServiceConfig Clone() => new()
    {
        Id = Id,
        Name = Name,
        Port = Port,
        Host = Host,
        WorkingDirectory = WorkingDirectory,
        StartCommand = StartCommand,
        PresetId = PresetId,
    };
}

public enum ManagedServiceStatus
{
    Stopped,
    Starting,
    Running,
    Stopping,
    Conflict,
    Failed,
}

public enum ManagedServiceLogStream
{
    StandardOutput,
    StandardError,
}

public sealed class ManagedServiceLogEntry
{
    public Guid Id { get; } = Guid.NewGuid();
    public DateTime Timestamp { get; } = DateTime.Now;
    public ManagedServiceLogStream Stream { get; init; }
    public string Text { get; init; } = string.Empty;

    public bool IsError => Stream == ManagedServiceLogStream.StandardError;
}

public sealed class ManagedServiceOccupant
{
    public int Pid { get; init; }
    public string ProcessName { get; init; } = string.Empty;
    public string Command { get; init; } = string.Empty;
    public string User { get; init; } = string.Empty;
    public string Address { get; init; } = string.Empty;
}

public sealed class ManagedServiceConflict
{
    public Guid Id { get; } = Guid.NewGuid();
    public Guid ServiceId { get; init; }
    public int Port { get; init; }
    public IReadOnlyList<ManagedServiceOccupant> Occupants { get; init; } = Array.Empty<ManagedServiceOccupant>();
}

/// <summary>
/// Ephemeral, non-persisted runtime state for one profile. Never serialized.
/// </summary>
public sealed class ManagedServiceState : INotifyPropertyChanged
{
    public const int MaxOutputLines = 200;
    public static readonly TimeSpan ReadinessPollInterval = TimeSpan.FromMilliseconds(250);
    public static readonly TimeSpan ReadinessTimeout = TimeSpan.FromSeconds(20);

    private ManagedServiceStatus _status = ManagedServiceStatus.Stopped;
    private int? _rootPid;
    private DateTime? _startedAt;
    private int? _lastExitCode;
    private string? _lastError;
    private ManagedServiceConflict? _conflict;

    public ManagedServiceState(ManagedServiceConfig config)
    {
        Config = config;
        RecentOutput = new ObservableCollection<ManagedServiceLogEntry>();
        ListenerPids = new ObservableCollection<int>();
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public Guid Id => Config.Id;

    public ManagedServiceConfig Config { get; set; }

    public ManagedServiceStatus Status
    {
        get => _status;
        set
        {
            if (_status == value) return;
            _status = value;
            OnPropertyChanged(nameof(Status));
            OnPropertyChanged(nameof(IsTransitioning));
            OnPropertyChanged(nameof(IsRunning));
        }
    }

    public int? RootPid
    {
        get => _rootPid;
        set => SetField(ref _rootPid, value);
    }

    public ObservableCollection<int> ListenerPids { get; }

    public DateTime? StartedAt
    {
        get => _startedAt;
        set => SetField(ref _startedAt, value);
    }

    public int? LastExitCode
    {
        get => _lastExitCode;
        set => SetField(ref _lastExitCode, value);
    }

    public string? LastError
    {
        get => _lastError;
        set => SetField(ref _lastError, value);
    }

    public ObservableCollection<ManagedServiceLogEntry> RecentOutput { get; }

    public ManagedServiceConflict? Conflict
    {
        get => _conflict;
        set => SetField(ref _conflict, value);
    }

    public string Name => Config.Name;
    public int Port => Config.Port;
    public string Host => Config.Host;
    public string HostAndPort => $"{Config.NormalizedHost}:{Config.Port}";

    public bool IsTransitioning => Status is ManagedServiceStatus.Starting or ManagedServiceStatus.Stopping;

    public bool IsOwned => RootPid.HasValue;

    public bool IsRunning => Status == ManagedServiceStatus.Running;

    public void AppendOutput(string text, ManagedServiceLogStream stream)
    {
        var trimmed = (text ?? string.Empty).Trim('\r', '\n');
        if (trimmed.Length == 0) return;
        foreach (var line in trimmed.Split('\n'))
        {
            RecentOutput.Add(new ManagedServiceLogEntry { Stream = stream, Text = line.TrimEnd('\r') });
        }
        while (RecentOutput.Count > MaxOutputLines)
        {
            RecentOutput.RemoveAt(0);
        }
    }

    public void ClearOutput()
    {
        RecentOutput.Clear();
    }

    /// <summary>Clears ownership and transient runtime fields.</summary>
    public void ClearRuntime()
    {
        RootPid = null;
        ListenerPids.Clear();
        StartedAt = null;
        LastExitCode = null;
        Conflict = null;
    }

    private void SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return;
        field = value;
        OnPropertyChanged(propertyName);
        if (propertyName == nameof(RootPid)) OnPropertyChanged(nameof(IsOwned));
    }

    private void OnPropertyChanged(string? propertyName) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
