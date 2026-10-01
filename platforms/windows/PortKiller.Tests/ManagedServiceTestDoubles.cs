using System.Collections.ObjectModel;
using PortKiller.Models;
using PortKiller.Services;

namespace PortKiller.Tests;

/// <summary>Shared test doubles for managed-service tests.</summary>
internal static class TestPortInfo
{
    public static PortInfo Active(int port, int pid) => new()
    {
        Port = port,
        Pid = pid,
        ProcessName = "foreign",
        Address = "127.0.0.1",
        User = "tester",
        Command = "foreign --port",
    };
}

internal sealed class AlwaysExistingDirectoryValidator : IManagedServiceDirectoryValidator
{
    public bool IsExistingDirectory(string path) => true;
}

internal sealed class FakeTunnelCoordinator : IManagedServiceTunnelCoordinator
{
    public List<int> StoppedPorts { get; } = new();

    public Task StopTunnelForPortAsync(int port, CancellationToken cancellationToken = default)
    {
        StoppedPorts.Add(port);
        return Task.CompletedTask;
    }
}

internal sealed class FakeStorage : IManagedServiceStorage
{
    private List<ManagedServiceConfig> _configs = new();

    public IReadOnlyList<ManagedServiceConfig> Load() => _configs.Select(c => c.Clone()).ToList();

    public void Save(IEnumerable<ManagedServiceConfig> services)
        => _configs = services.Select(c => c.Clone()).ToList();
}

/// <summary>
/// Service-id-keyed process controller. A runtime is only ever reported as
/// running, and only ever stopped, while this instance tracks it.
/// </summary>
internal sealed class FakeProcessController : IManagedServiceProcessController
{
    private readonly Dictionary<Guid, int> _tracked = new();

    public event EventHandler<ManagedServiceOutputEventArgs>? Output;

    public List<int> StartedPids { get; } = new();
    public List<int> StoppedPids { get; } = new();
    public List<Guid> StopRequests { get; } = new();
    public Action<int>? OnStop { get; set; }
    public bool ExitImmediately { get; set; }

    public void RaiseOutput(Guid id, string text) =>
        Output?.Invoke(this, new ManagedServiceOutputEventArgs(id, ManagedServiceLogStream.StandardOutput, text));

    /// <summary>Simulates the controller dropping a runtime it used to track.</summary>
    public void Forget(Guid serviceId) => _tracked.Remove(serviceId);

    public bool IsTracked(Guid serviceId) => _tracked.ContainsKey(serviceId);

    public Task<int> StartAsync(ManagedServiceConfig config, CancellationToken cancellationToken = default)
    {
        var pid = 7000 + StartedPids.Count;
        StartedPids.Add(pid);
        _tracked[config.Id] = pid;
        return Task.FromResult(pid);
    }

    public Task StopAsync(Guid serviceId, CancellationToken cancellationToken = default)
    {
        StopRequests.Add(serviceId);
        if (_tracked.TryGetValue(serviceId, out var pid))
        {
            _tracked.Remove(serviceId);
            StoppedPids.Add(pid);
            OnStop?.Invoke(pid);
        }
        return Task.CompletedTask;
    }

    public bool IsRunning(Guid serviceId) => !ExitImmediately && _tracked.ContainsKey(serviceId);

    public int? RootPid(Guid serviceId) => _tracked.TryGetValue(serviceId, out var pid) ? pid : null;
}

internal sealed class FakePortInspector : IManagedServicePortInspector
{
    private readonly Dictionary<int, List<PortInfo>> _occupants = new();
    private readonly Dictionary<int, int> _calls = new();
    private readonly Dictionary<int, (int Threshold, int Pid)> _later = new();

    public List<int> KilledPids { get; } = new();
    public List<bool> KillForce { get; } = new();
    public bool KillShouldFail { get; set; }

    /// <summary>When set, <see cref="InspectAsync"/> throws once the call count exceeds the threshold.</summary>
    public (int AfterCalls, Exception Error)? InspectFailure { get; set; }

    public void Occupy(int port, int pid)
    {
        if (!_occupants.TryGetValue(port, out var list))
        {
            list = new List<PortInfo>();
            _occupants[port] = list;
        }
        if (list.All(p => p.Pid != pid)) list.Add(TestPortInfo.Active(port, pid));
    }

    public void OccupyAfter(int port, int calls, int pid) => _later[port] = (calls, pid);

    public void Release(int port) => _occupants.Remove(port);

    public void ReleasePid(int port, int pid)
    {
        if (_occupants.TryGetValue(port, out var list)) list.RemoveAll(p => p.Pid == pid);
    }

    public Task<IReadOnlyList<PortInfo>> ScanAsync(CancellationToken cancellationToken = default) =>
        Task.FromResult<IReadOnlyList<PortInfo>>(_occupants.Values.SelectMany(v => v).ToList());

    public Task<IReadOnlyList<PortInfo>> InspectAsync(int port, CancellationToken cancellationToken = default)
    {
        _calls.TryGetValue(port, out var calls);
        calls++;
        _calls[port] = calls;

        if (InspectFailure is { } failure && calls > failure.AfterCalls)
        {
            throw failure.Error;
        }

        if (_later.TryGetValue(port, out var later) && calls > later.Threshold)
        {
            Occupy(port, later.Pid);
            _later.Remove(port);
        }

        var result = _occupants.TryGetValue(port, out var list)
            ? list.ToList()
            : new List<PortInfo>();
        return Task.FromResult<IReadOnlyList<PortInfo>>(result);
    }

    public async Task<bool> IsReadyAsync(int port, CancellationToken cancellationToken = default) =>
        (await InspectAsync(port, cancellationToken)).Count > 0;

    public Task<bool> KillAsync(int pid, bool force, CancellationToken cancellationToken = default)
    {
        KilledPids.Add(pid);
        KillForce.Add(force);
        if (!KillShouldFail)
        {
            foreach (var list in _occupants.Values) list.RemoveAll(p => p.Pid == pid);
        }
        return Task.FromResult(true);
    }
}

/// <summary>Records how state changes are marshalled and runs them inline.</summary>
internal sealed class RecordingStateDispatcher : IManagedServiceStateDispatcher
{
    public int InvokeCount { get; private set; }
    public int PostCount { get; private set; }

    public void Invoke(Action action)
    {
        InvokeCount++;
        action();
    }

    public void Post(Action action)
    {
        PostCount++;
        action();
    }
}

/// <summary>Lightweight tunnel host for ViewModel tests.</summary>
internal sealed class FakeTunnelHost : IManagedServiceTunnelHost
{
    public ObservableCollection<CloudflareTunnel> Tunnels { get; } = new();
    public List<int> StartedPorts { get; } = new();
    public List<CloudflareTunnel> StoppedTunnels { get; } = new();

    public Task StartTunnelAsync(int port)
    {
        StartedPorts.Add(port);
        return Task.CompletedTask;
    }

    public Task StopTunnelAsync(CloudflareTunnel tunnel)
    {
        StoppedTunnels.Add(tunnel);
        return Task.CompletedTask;
    }

    public void CopyUrlToClipboard(string url)
    {
    }

    public void OpenUrlInBrowser(string url)
    {
    }
}
