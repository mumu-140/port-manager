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
    private readonly Dictionary<Guid, SemaphoreSlim> _lifecycleGates = new();
    private readonly Dictionary<Guid, long> _lifecycleGenerations = new();

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

    /// <summary>
    /// Read-only port inspection for the editor's live availability hint.
    /// Reuses the lifecycle inspector and filters the edited service's own
    /// known listeners so a running profile never conflicts with itself.
    /// </summary>
    public async Task<IReadOnlyList<PortInfo>> InspectPortForEditorAsync(
        int port,
        Guid? editingId,
        CancellationToken cancellationToken = default)
    {
        if (port is < 1 or > 65535) return Array.Empty<PortInfo>();

        var listeners = (await _ports.InspectAsync(port, cancellationToken).ConfigureAwait(false)).ToList();
        if (editingId is not { } id) return listeners;

        var state = Find(id);
        if (state is null || state.Config.Port != port || !state.IsOwned) return listeners;

        var ownedListenerPids = state.ListenerPids.ToHashSet();
        return listeners.Where(listener => !ownedListenerPids.Contains(listener.Pid)).ToList();
    }


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
        // A config edit never races a lifecycle mutation. If Start/Stop/Restart
        // owns this service's gate (for example while Start awaits its port
        // preflight with the profile still Stopped), the edit is rejected.
        var gate = LifecycleGate(config.Id);
        if (!gate.Wait(0))
        {
            return new ManagedServiceValidationError(ManagedServiceValidationErrorKind.ServiceTransitioning);
        }

        try
        {
            BumpGeneration(config.Id);
            return UpdateCore(config);
        }
        finally
        {
            BumpGeneration(config.Id);
            gate.Release();
        }
    }

    private ManagedServiceValidationError? UpdateCore(ManagedServiceConfig config)
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

    public Task<bool> RemoveAsync(Guid id) => WithLifecycleGateAsync(id, () =>
    {
        var state = Find(id);
        if (state is null) return Task.FromResult(false);
        if (state.IsOwned || state.IsTransitioning) return Task.FromResult(false);
        lock (_gate) _services.Remove(state);
        ManagedServiceRuntimeLogStore.Cleanup(id);
        Persist();
        return Task.FromResult(true);
    }, CancellationToken.None);

    public Task<bool> StartAsync(Guid id, CancellationToken cancellationToken = default) =>
        WithLifecycleGateAsync(id, () => StartCoreAsync(id, cancellationToken), cancellationToken);

    /// <summary>Start path; the caller owns the service lifecycle gate.</summary>
    private async Task<bool> StartCoreAsync(Guid id, CancellationToken cancellationToken)
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
        try
        {
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
        }
        catch (Exception ex)
        {
            // The launch succeeded but readiness did not complete. Never leave
            // the launched tree owned by nothing, and never leave the profile
            // stuck in Starting (reconciliation skips transitional states).
            await ReleaseOwnedRuntimeAsync(state, CancellationToken.None).ConfigureAwait(false);
            Mutate(state, s =>
            {
                s.ClearRuntime();
                s.Status = ManagedServiceStatus.Failed;
                s.LastError = ex.Message;
            });
            throw;
        }

        Mutate(state, s => s.LastError = $"Service did not listen on port {s.Config.Port} in time.");
        await StopCoreAsync(id, CancellationToken.None).ConfigureAwait(false);
        Mutate(state, s =>
        {
            s.ClearRuntime();
            s.Status = ManagedServiceStatus.Failed;
        });
        return false;
    }

    public Task<bool> StopAsync(Guid id, CancellationToken cancellationToken = default) =>
        WithLifecycleGateAsync(id, () => StopCoreAsync(id, cancellationToken), cancellationToken);

    /// <summary>Stop path; the caller owns the service lifecycle gate.</summary>
    private async Task<bool> StopCoreAsync(Guid id, CancellationToken cancellationToken)
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

    /// <summary>Stop then start under one gate acquisition; never a parallel launch.</summary>
    public Task<bool> RestartAsync(Guid id, CancellationToken cancellationToken = default) =>
        WithLifecycleGateAsync(id, async () =>
        {
            var state = Find(id);
            if (state is null) return false;
            if (state.Status != ManagedServiceStatus.Running) return false;
            await StopCoreAsync(id, cancellationToken).ConfigureAwait(false);
            if (Find(id)?.Status != ManagedServiceStatus.Stopped) return false;
            return await StartCoreAsync(id, cancellationToken).ConfigureAwait(false);
        }, cancellationToken);

    public Task<bool> StopForEditingAsync(Guid id, CancellationToken cancellationToken = default) =>
        WithLifecycleGateAsync(id, async () =>
        {
            var state = Find(id);
            if (state is null) return false;
            if (!state.IsOwned) return !state.IsTransitioning;
            await StopCoreAsync(id, cancellationToken).ConfigureAwait(false);
            return Find(id)?.Status == ManagedServiceStatus.Stopped;
        }, cancellationToken);

    /// <summary>
    /// Terminates only the occupant PIDs the user confirmed, then starts.
    /// Processes that acquire the port after confirmation are never signalled.
    /// </summary>
    public Task<bool> ResolveConflictAndStartAsync(Guid id, CancellationToken cancellationToken = default) =>
        WithLifecycleGateAsync(id, () => ResolveConflictAndStartCoreAsync(id, cancellationToken), cancellationToken);

    private async Task<bool> ResolveConflictAndStartCoreAsync(Guid id, CancellationToken cancellationToken)
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
        return await StartCoreAsync(id, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>
    /// Serializes every lifecycle mutation of one service. Public entry points
    /// acquire the gate exactly once; *Core methods assume it is held and never
    /// re-enter a public entry point, so there is no nested acquisition.
    /// </summary>
    private SemaphoreSlim LifecycleGate(Guid id)
    {
        lock (_gate)
        {
            if (!_lifecycleGates.TryGetValue(id, out var gate))
            {
                gate = new SemaphoreSlim(1, 1);
                _lifecycleGates[id] = gate;
            }
            return gate;
        }
    }

    /// <summary>
    /// Advances the service's lifecycle generation. Every gated lifecycle
    /// operation bumps it on entry and on exit, so a scan whose snapshot was
    /// taken before or during that operation is recognisably stale.
    /// </summary>
    private void BumpGeneration(Guid id)
    {
        lock (_gate)
        {
            _lifecycleGenerations.TryGetValue(id, out var generation);
            _lifecycleGenerations[id] = generation + 1;
        }
    }

    private long Generation(Guid id)
    {
        lock (_gate) return _lifecycleGenerations.TryGetValue(id, out var generation) ? generation : 0;
    }

    private async Task<bool> WithLifecycleGateAsync(Guid id, Func<Task<bool>> action, CancellationToken cancellationToken)
    {
        var gate = LifecycleGate(id);
        await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        BumpGeneration(id);
        try
        {
            return await action().ConfigureAwait(false);
        }
        finally
        {
            BumpGeneration(id);
            gate.Release();
        }
    }

    /// <summary>
    /// Non-blocking variant for reconciliation. Runs <paramref name="action"/>
    /// only if the service's gate is free right now and its lifecycle has not
    /// changed since <paramref name="expectedGeneration"/> was captured. It
    /// never waits for a lifecycle operation and then applies an old scan.
    /// </summary>
    private async Task TryWithLifecycleGateAsync(Guid id, long expectedGeneration, Func<Task> action)
    {
        var gate = LifecycleGate(id);
        if (!gate.Wait(0)) return;
        try
        {
            if (Generation(id) != expectedGeneration) return;
            await action().ConfigureAwait(false);
            BumpGeneration(id);
        }
        finally
        {
            gate.Release();
        }
    }

    public void ClearOutput(Guid id)
    {
        var state = Find(id);
        if (state is null) return;
        Mutate(state, s => s.ClearOutput());
    }

    /// <summary>
    /// Captures each service's lifecycle generation. Take it before scanning
    /// and pass it to <see cref="ReconcileAsync(IReadOnlyList{PortInfo}, IReadOnlyDictionary{Guid, long}, CancellationToken)"/>
    /// so a scan can never be applied across a lifecycle change.
    /// </summary>
    public IReadOnlyDictionary<Guid, long> CaptureLifecycleSnapshot()
    {
        lock (_gate)
        {
            return _services.ToDictionary(
                s => s.Id,
                s => _lifecycleGenerations.TryGetValue(s.Id, out var generation) ? generation : 0L);
        }
    }

    public async Task ReconcileWithScanAsync(CancellationToken cancellationToken = default)
    {
        var lifecycle = CaptureLifecycleSnapshot();
        var ports = await _ports.ScanAsync(cancellationToken).ConfigureAwait(false);
        await ReconcileAsync(ports, lifecycle, cancellationToken).ConfigureAwait(false);
    }

    /// <summary>Reconciles against a scan taken just now.</summary>
    public Task ReconcileAsync(IReadOnlyList<PortInfo> ports, CancellationToken cancellationToken = default) =>
        ReconcileAsync(ports, CaptureLifecycleSnapshot(), cancellationToken);

    /// <summary>
    /// Aligns runtime state with the latest scan. A profile is only ever
    /// Running while a process this session owns still serves its port.
    /// The shared scan is passed in so a normal refresh drives reconciliation
    /// without a second polling loop.
    ///
    /// Reconciliation releases runtimes, so it joins the per-service lifecycle
    /// gate without waiting: a service whose gate is held, or whose lifecycle
    /// changed since <paramref name="lifecycle"/> was captured, is skipped and
    /// left to the next refresh. State is re-read only after the gate is held.
    /// </summary>
    public async Task ReconcileAsync(
        IReadOnlyList<PortInfo> ports,
        IReadOnlyDictionary<Guid, long> lifecycle,
        CancellationToken cancellationToken = default)
    {
        foreach (var (id, generation) in lifecycle)
        {
            await TryWithLifecycleGateAsync(id, generation, async () =>
            {
                var state = Find(id);
                if (state is null) return;
                switch (state.Status)
                {
                    case ManagedServiceStatus.Starting:
                    case ManagedServiceStatus.Stopping:
                        return;
                    case ManagedServiceStatus.Running:
                        await ReconcileRunningAsync(state, ports, cancellationToken).ConfigureAwait(false);
                        return;
                    default:
                        ReconcileUnOwned(state, ports);
                        return;
                }
            }).ConfigureAwait(false);
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
