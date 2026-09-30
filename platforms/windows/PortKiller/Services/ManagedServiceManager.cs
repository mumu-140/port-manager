using PortKiller.Models;

namespace PortKiller.Services;

/// <summary>
/// Owns managed-service configuration and runtime state. Mirrors the macOS
/// ManagedServiceManager: it validates profiles, starts/stops owned process
/// trees, tracks readiness, reconciles with the shared scan and only ever
/// signals user-confirmed conflict occupants.
///
/// Every mutation of a <see cref="ManagedServiceState"/> goes through
/// <see cref="IManagedServiceStateDispatcher"/> so WPF-bound observable state is
/// only ever changed on the dispatcher thread. Process ownership is delegated
/// to <see cref="IManagedServiceProcessController"/> and keyed by service id.
/// </summary>
public sealed class ManagedServiceManager
{
    public const int MaxOutputLines = 200;
    public static readonly TimeSpan ReadinessTimeout = TimeSpan.FromSeconds(20);
    public static readonly TimeSpan ReadinessPollInterval = TimeSpan.FromMilliseconds(250);
    public static readonly TimeSpan StopTimeout = TimeSpan.FromSeconds(5);
    public static readonly TimeSpan StopPollInterval = TimeSpan.FromMilliseconds(200);

    private readonly IManagedServiceStorage _storage;
    private readonly IManagedServiceProcessController _processes;
    private readonly IManagedServicePortInspector _ports;
    private readonly IManagedServiceDirectoryValidator _directoryValidator;
    private readonly IManagedServiceTunnelCoordinator? _tunnelCoordinator;
    private readonly IManagedServiceStateDispatcher _stateDispatcher;
    private readonly List<ManagedServiceState> _services = new();
    private readonly object _gate = new();

    public ManagedServiceManager(
        IManagedServiceStorage storage,
        IManagedServiceProcessController processes,
        IManagedServicePortInspector ports,
        IManagedServiceDirectoryValidator? directoryValidator = null,
        IManagedServiceTunnelCoordinator? tunnelCoordinator = null,
        IManagedServiceStateDispatcher? stateDispatcher = null)
    {
        _storage = storage;
        _processes = processes;
        _ports = ports;
        _directoryValidator = directoryValidator ?? new FileSystemManagedServiceDirectoryValidator();
        _tunnelCoordinator = tunnelCoordinator;
        _stateDispatcher = stateDispatcher ?? new ImmediateManagedServiceStateDispatcher();
        _processes.Output += OnOutput;
    }

    public IReadOnlyList<ManagedServiceState> Services
    {
        get { lock (_gate) return _services.ToList(); }
    }

    public IReadOnlyList<ManagedServiceConfig> Configs => Services.Select(s => s.Config).ToList();

    public ManagedServiceState? Find(Guid id)
    {
        lock (_gate) return _services.FirstOrDefault(s => s.Id == id);
    }

    public ManagedServiceValidationError? Validate(ManagedServiceConfig config) =>
        ManagedServiceValidator.Validate(config, Configs, _directoryValidator);

    public IReadOnlyList<ManagedServiceState> Load()
    {
        lock (_gate)
        {
            _services.Clear();
            foreach (var config in _storage.Load())
            {
                _services.Add(new ManagedServiceState(config));
            }
            return _services.ToList();
        }
    }

    public ManagedServiceValidationError? Add(ManagedServiceConfig config)
    {
        if (config.Id == Guid.Empty) config.Id = Guid.NewGuid();
        var candidate = config.Clone();
        var error = Validate(candidate);
        if (error is not null) return error;
        lock (_gate) _services.Add(new ManagedServiceState(candidate));
        Persist();
        return null;
    }

    /// <summary>
    /// Updates a profile only while it is not live. Running, starting or
    /// stopping services must be stopped first (design notes, section 12).
    /// </summary>
    public ManagedServiceValidationError? Update(ManagedServiceConfig config)
    {
        var state = Find(config.Id);
        if (state is null) return null;
        if (state.Status is ManagedServiceStatus.Starting or ManagedServiceStatus.Stopping)
        {
            return new ManagedServiceValidationError(ManagedServiceValidationErrorKind.ServiceTransitioning);
        }
        if (state.Status == ManagedServiceStatus.Running)
        {
            return new ManagedServiceValidationError(ManagedServiceValidationErrorKind.ServiceRunning);
        }

        var candidate = config.Clone();
        candidate.Id = config.Id;
        var error = Validate(candidate);
        if (error is not null) return error;
        Mutate(state, s => s.Config = candidate);
        Persist();
        return null;
    }

    public Task<bool> RemoveAsync(Guid id)
    {
        var state = Find(id);
        if (state is null) return Task.FromResult(false);
        if (state.IsOwned || state.IsTransitioning) return Task.FromResult(false);
        lock (_gate) _services.Remove(state);
        ManagedServiceRuntimeLogStore.Cleanup(id);
        Persist();
        return Task.FromResult(true);
    }

    public async Task<bool> StartAsync(Guid id, CancellationToken cancellationToken = default)
    {
        var state = Find(id);
        if (state is null) return false;
        if (state.IsTransitioning || state.Status == ManagedServiceStatus.Running) return false;

        var error = Validate(state.Config);
        if (error is not null)
        {
            var message = error.Message;
            Mutate(state, s =>
            {
                s.Status = ManagedServiceStatus.Failed;
                s.LastError = message;
            });
            return false;
        }

        var listeners = await _ports.InspectAsync(state.Config.Port, cancellationToken).ConfigureAwait(false);
        if (listeners.Count > 0)
        {
            Mutate(state, s =>
            {
                s.Conflict = MakeConflict(s, listeners);
                s.ListenerPids.Clear();
                foreach (var pid in DistinctPids(listeners)) s.ListenerPids.Add(pid);
                s.Status = ManagedServiceStatus.Conflict;
                s.LastError = null;
            });
            return false;
        }

        Mutate(state, s =>
        {
            s.Status = ManagedServiceStatus.Starting;
            s.LastError = null;
            s.Conflict = null;
            s.ClearOutput();
        });

        int rootPid;
        try
        {
            rootPid = await _processes.StartAsync(state.Config, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex)
        {
            Mutate(state, s =>
            {
                s.Status = ManagedServiceStatus.Failed;
                s.LastError = ex.Message;
            });
            return false;
        }

        Mutate(state, s => s.RootPid = rootPid);

        var deadline = DateTime.UtcNow + ReadinessTimeout;
        while (DateTime.UtcNow < deadline)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (state.Status != ManagedServiceStatus.Starting) return false;

            if (!_processes.IsRunning(state.Id))
            {
                Mutate(state, s =>
                {
                    s.ClearRuntime();
                    s.Status = ManagedServiceStatus.Failed;
                    s.LastError = $"Service exited before it listened on port {s.Config.Port}.";
                });
                return false;
            }

            var current = await _ports.InspectAsync(state.Config.Port, cancellationToken).ConfigureAwait(false);
            if (state.Status != ManagedServiceStatus.Starting) return false;
            if (current.Count > 0)
            {
                Mutate(state, s =>
                {
                    s.ListenerPids.Clear();
                    foreach (var pid in DistinctPids(current)) s.ListenerPids.Add(pid);
                    s.Status = ManagedServiceStatus.Running;
                    s.StartedAt = DateTime.Now;
                });
                return true;
            }

            await Task.Delay(ReadinessPollInterval, cancellationToken).ConfigureAwait(false);
        }

        Mutate(state, s => s.LastError = $"Service did not listen on port {s.Config.Port} in time.");
        await StopAsync(id, CancellationToken.None).ConfigureAwait(false);
        Mutate(state, s =>
        {
            s.ClearRuntime();
            s.Status = ManagedServiceStatus.Failed;
        });
        return false;
    }

    public async Task<bool> StopAsync(Guid id, CancellationToken cancellationToken = default)
    {
        var state = Find(id);
        if (state is null) return false;
        if (state.Status != ManagedServiceStatus.Running && state.Status != ManagedServiceStatus.Starting)
        {
            return state.Status == ManagedServiceStatus.Stopped || state.Status == ManagedServiceStatus.Failed;
        }

        Mutate(state, s => s.Status = ManagedServiceStatus.Stopping);

        // A stopped service must not leave a stale public endpoint behind.
        if (_tunnelCoordinator is not null)
        {
            await _tunnelCoordinator.StopTunnelForPortAsync(state.Config.Port, cancellationToken).ConfigureAwait(false);
        }

        if (state.IsOwned)
        {
            try
            {
                await _processes.StopAsync(state.Id, cancellationToken).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                Mutate(state, s => s.LastError = ex.Message);
            }
        }

        var freed = await WaitForPortToFreeAsync(state.Config.Port, cancellationToken).ConfigureAwait(false);
        if (freed)
        {
            Mutate(state, s =>
            {
                s.Status = ManagedServiceStatus.Stopped;
                s.LastError = null;
                s.ClearRuntime();
            });
            return true;
        }

        var remaining = await _ports.InspectAsync(state.Config.Port, cancellationToken).ConfigureAwait(false);
        if (remaining.Count == 0)
        {
            Mutate(state, s =>
            {
                s.Status = ManagedServiceStatus.Stopped;
                s.LastError = null;
                s.ClearRuntime();
            });
            return true;
        }

        Mutate(state, s =>
        {
            s.Status = ManagedServiceStatus.Conflict;
            s.Conflict = MakeConflict(s, remaining);
            s.LastError = $"Port {s.Config.Port} is still in use.";
            s.RootPid = null;
            s.ListenerPids.Clear();
            foreach (var pid in DistinctPids(remaining)) s.ListenerPids.Add(pid);
        });
        return false;
    }

    public async Task<bool> RestartAsync(Guid id, CancellationToken cancellationToken = default)
    {
        var state = Find(id);
        if (state is null) return false;
        if (state.Status != ManagedServiceStatus.Running) return false;
        await StopAsync(id, cancellationToken).ConfigureAwait(false);
        if (Find(id)?.Status != ManagedServiceStatus.Stopped) return false;
        return await StartAsync(id, cancellationToken).ConfigureAwait(false);
    }

    public async Task<bool> StopForEditingAsync(Guid id, CancellationToken cancellationToken = default)
    {
        var state = Find(id);
        if (state is null) return false;
        if (!state.IsOwned) return !state.IsTransitioning;
        await StopAsync(id, cancellationToken).ConfigureAwait(false);
        return Find(id)?.Status == ManagedServiceStatus.Stopped;
    }

    /// <summary>
    /// Terminates only the occupant PIDs the user confirmed, then starts.
    /// Processes that acquire the port after confirmation are never signalled.
    /// </summary>
    public async Task<bool> ResolveConflictAndStartAsync(Guid id, CancellationToken cancellationToken = default)
    {
        var state = Find(id);
        if (state is null || state.Status != ManagedServiceStatus.Conflict || state.Conflict is null) return false;

        var confirmed = state.Conflict.Occupants.Select(o => o.Pid).ToHashSet();
        Mutate(state, s =>
        {
            s.Status = ManagedServiceStatus.Starting;
            s.LastError = null;
        });

        foreach (var pid in confirmed)
        {
            try { await _ports.KillAsync(pid, force: false, cancellationToken).ConfigureAwait(false); }
            catch (Exception) { }
        }

        var afterGraceful = await _ports.InspectAsync(state.Config.Port, cancellationToken).ConfigureAwait(false);
        foreach (var pid in DistinctPids(afterGraceful).Where(confirmed.Contains))
        {
            try { await _ports.KillAsync(pid, force: true, cancellationToken).ConfigureAwait(false); }
            catch (Exception) { }
        }

        var remaining = await _ports.InspectAsync(state.Config.Port, cancellationToken).ConfigureAwait(false);
        if (remaining.Count > 0)
        {
            Mutate(state, s =>
            {
                s.Status = ManagedServiceStatus.Conflict;
                s.Conflict = MakeConflict(s, remaining);
                s.LastError = $"Port {s.Config.Port} is still in use.";
                s.ListenerPids.Clear();
                foreach (var pid in DistinctPids(remaining)) s.ListenerPids.Add(pid);
            });
            return false;
        }

        Mutate(state, s =>
        {
            s.Conflict = null;
            s.ListenerPids.Clear();
            s.Status = ManagedServiceStatus.Stopped;
        });
        return await StartAsync(id, cancellationToken).ConfigureAwait(false);
    }

    public void ClearOutput(Guid id)
    {
        var state = Find(id);
        if (state is null) return;
        Mutate(state, s => s.ClearOutput());
    }

    public async Task ReconcileWithScanAsync(CancellationToken cancellationToken = default)
    {
        var ports = await _ports.ScanAsync(cancellationToken).ConfigureAwait(false);
        await ReconcileAsync(ports, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>
    /// Aligns runtime state with the latest scan. A profile is only ever
    /// Running while a process this session owns still serves its port.
    /// The shared scan is passed in so a normal refresh drives reconciliation
    /// without a second polling loop.
    /// </summary>
    public async Task ReconcileAsync(IReadOnlyList<PortInfo> ports, CancellationToken cancellationToken = default)
    {
        foreach (var state in Services)
        {
            switch (state.Status)
            {
                case ManagedServiceStatus.Starting:
                case ManagedServiceStatus.Stopping:
                    continue;
                case ManagedServiceStatus.Running:
                    await ReconcileRunningAsync(state, ports, cancellationToken).ConfigureAwait(false);
                    break;
                default:
                    ReconcileUnOwned(state, ports);
                    break;
            }
        }
    }

    private async Task ReconcileRunningAsync(ManagedServiceState state, IReadOnlyList<PortInfo> ports, CancellationToken cancellationToken)
    {
        var raw = ports.Where(p => p.Port == state.Config.Port).ToList();
        var current = DistinctPids(raw);

        var rootAlive = state.RootPid is not null && _processes.IsRunning(state.Id);
        if (!rootAlive)
        {
            await ReleaseOwnedRuntimeAsync(state, cancellationToken).ConfigureAwait(false);
            Mutate(state, s =>
            {
                s.ClearRuntime();
                s.Status = ManagedServiceStatus.Failed;
                s.LastError = "Owned service process is no longer running.";
            });
            return;
        }

        if (current.Count == 0)
        {
            await ReleaseOwnedRuntimeAsync(state, cancellationToken).ConfigureAwait(false);
            Mutate(state, s =>
            {
                s.ClearRuntime();
                s.Status = ManagedServiceStatus.Failed;
                s.LastError = $"Service stopped listening on port {s.Config.Port}.";
            });
            return;
        }

        var tracked = state.ListenerPids.ToHashSet();
        var ownedListeners = current.Where(pid => pid == state.RootPid || tracked.Contains(pid)).ToList();
        if (ownedListeners.Count == 0)
        {
            await ReleaseOwnedRuntimeAsync(state, cancellationToken).ConfigureAwait(false);
            Mutate(state, s =>
            {
                s.ClearRuntime();
                s.Status = ManagedServiceStatus.Conflict;
                s.Conflict = MakeConflict(s, raw);
                s.ListenerPids.Clear();
                foreach (var pid in current) s.ListenerPids.Add(pid);
                s.LastError = null;
            });
            return;
        }

        Mutate(state, s =>
        {
            s.ListenerPids.Clear();
            foreach (var pid in current) s.ListenerPids.Add(pid);
        });
    }

    private void ReconcileUnOwned(ManagedServiceState state, IReadOnlyList<PortInfo> ports)
    {
        var raw = ports.Where(p => p.Port == state.Config.Port).ToList();
        var occupants = DistinctPids(raw);

        if (occupants.Count == 0)
        {
            if (state.Status == ManagedServiceStatus.Conflict)
            {
                Mutate(state, s =>
                {
                    s.Conflict = null;
                    s.ListenerPids.Clear();
                    s.ClearRuntime();
                    s.Status = ManagedServiceStatus.Stopped;
                    s.LastError = null;
                });
            }
            else if (state.Status == ManagedServiceStatus.Stopped)
            {
                Mutate(state, s => s.ClearRuntime());
            }
            return;
        }

        Mutate(state, s =>
        {
            s.Status = ManagedServiceStatus.Conflict;
            s.Conflict = MakeConflict(s, raw);
            s.ListenerPids.Clear();
            foreach (var pid in occupants) s.ListenerPids.Add(pid);
            s.LastError = null;
        });
    }

    private async Task ReleaseOwnedRuntimeAsync(ManagedServiceState state, CancellationToken cancellationToken)
    {
        if (!state.IsOwned) return;
        try { await _processes.StopAsync(state.Id, cancellationToken).ConfigureAwait(false); }
        catch (Exception) { }
    }

    private async Task<bool> WaitForPortToFreeAsync(int port, CancellationToken cancellationToken)
    {
        var deadline = DateTime.UtcNow + StopTimeout;
        while (DateTime.UtcNow < deadline)
        {
            if (cancellationToken.IsCancellationRequested) return false;
            var listeners = await _ports.InspectAsync(port, cancellationToken).ConfigureAwait(false);
            if (listeners.Count == 0) return true;
            await Task.Delay(StopPollInterval, cancellationToken).ConfigureAwait(false);
        }
        return false;
    }

    private static ManagedServiceConflict MakeConflict(ManagedServiceState state, IReadOnlyList<PortInfo> listeners) => new()
    {
        ServiceId = state.Id,
        Port = state.Config.Port,
        Occupants = listeners
            .GroupBy(p => p.Pid)
            .Select(g => g.First())
            .Select(p => new ManagedServiceOccupant
            {
                Pid = p.Pid,
                ProcessName = p.ProcessName,
                Command = p.Command,
                User = p.User,
                Address = p.Address,
            })
            .ToList(),
    };

    private static List<int> DistinctPids(IReadOnlyList<PortInfo> ports) =>
        ports.Select(p => p.Pid).Distinct().ToList();

    private void Persist() => _storage.Save(Configs);

    /// <summary>Applies a state mutation on the dispatcher thread.</summary>
    private void Mutate(ManagedServiceState state, Action<ManagedServiceState> mutation) =>
        _stateDispatcher.Invoke(() => mutation(state));

    private void OnOutput(object? sender, ManagedServiceOutputEventArgs e)
    {
        var state = Find(e.ServiceId);
        if (state is not null) _stateDispatcher.Post(() => state.AppendOutput(e.Text, e.Stream));
    }
}
