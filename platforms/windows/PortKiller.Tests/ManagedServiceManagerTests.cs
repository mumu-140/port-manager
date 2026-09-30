using PortKiller.Models;
using PortKiller.Services;
using Xunit;

namespace PortKiller.Tests;

public class ManagedServiceManagerTests
{
    private static ManagedServiceConfig Config(
        string name = "web",
        int port = 8080,
        string command = "dotnet run --urls http://localhost:{port}") => new()
    {
        Id = Guid.NewGuid(),
        Name = name,
        Port = port,
        Host = "localhost",
        WorkingDirectory = Path.GetTempPath(),
        StartCommand = command,
    };

    private static ManagedServiceManager Create(
        FakeStorage storage,
        FakeProcessController processes,
        FakePortInspector ports) =>
        new(storage, processes, ports, new AlwaysExistingDirectoryValidator());

    [Fact]
    public void AddRejectsDuplicatePort()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var manager = Create(storage, new FakeProcessController(), ports);

        Assert.Null(manager.Add(Config("one", 8080)));
        var error = manager.Add(Config("two", 8080));

        Assert.NotNull(error);
        Assert.Equal(ManagedServiceValidationErrorKind.DuplicatePort, error!.Kind);
        Assert.Single(manager.Services);
    }

    [Fact]
    public void AddRejectsDuplicateNameIgnoringCase()
    {
        var manager = Create(new FakeStorage(), new FakeProcessController(), new FakePortInspector());
        Assert.Null(manager.Add(Config("Web", 8080)));

        var error = manager.Add(Config("web", 8081));
        Assert.NotNull(error);
        Assert.Equal(ManagedServiceValidationErrorKind.DuplicateName, error!.Kind);
    }

    [Fact]
    public async Task StartReportsConflictWithoutKillingAnyone()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var manager = Create(storage, processes, ports);
        var config = Config();
        Assert.Null(manager.Add(config));
        ports.Occupy(8080, 4242);

        var started = await manager.StartAsync(config.Id);

        Assert.False(started);
        var state = manager.Find(config.Id)!;
        Assert.Equal(ManagedServiceStatus.Conflict, state.Status);
        Assert.Equal(4242, Assert.Single(state.Conflict!.Occupants).Pid);
        Assert.Empty(ports.KilledPids);
        Assert.Empty(processes.StartedPids);
    }

    [Fact]
    public async Task StartSucceedsOnceThePortListens()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var manager = Create(storage, processes, ports);
        var config = Config();
        Assert.Null(manager.Add(config));
        ports.OccupyAfter(8080, calls: 1, pid: 7777);

        var started = await manager.StartAsync(config.Id);

        Assert.True(started);
        var state = manager.Find(config.Id)!;
        Assert.Equal(ManagedServiceStatus.Running, state.Status);
        Assert.Equal(7000, state.RootPid);
        Assert.Contains(7777, state.ListenerPids);
    }

    [Fact]
    public async Task StartFailsWhenTheProcessExitsBeforeListening()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController { ExitImmediately = true };
        var manager = Create(storage, processes, ports);
        var config = Config();
        Assert.Null(manager.Add(config));

        var started = await manager.StartAsync(config.Id);

        Assert.False(started);
        var state = manager.Find(config.Id)!;
        Assert.Equal(ManagedServiceStatus.Failed, state.Status);
        Assert.NotNull(state.LastError);
    }

    [Fact]
    public async Task StopOnlySignalsTheOwnedRootAndWaitsForThePort()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var manager = Create(storage, processes, ports);
        var config = Config();
        Assert.Null(manager.Add(config));
        ports.OccupyAfter(8080, calls: 1, pid: 7777);

        Assert.True(await manager.StartAsync(config.Id));
        ports.Release(8080);
        processes.OnStop = _ => ports.Release(8080);

        var stopped = await manager.StopAsync(config.Id);

        Assert.True(stopped);
        Assert.Equal(ManagedServiceStatus.Stopped, manager.Find(config.Id)!.Status);
        Assert.Contains(7000, processes.StoppedPids);
        Assert.Empty(ports.KilledPids);
    }

    [Fact]
    public async Task StopReportsConflictWhenThePortStaysOccupied()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var manager = Create(storage, processes, ports);
        var config = Config();
        Assert.Null(manager.Add(config));
        ports.OccupyAfter(8080, calls: 1, pid: 7777);
        Assert.True(await manager.StartAsync(config.Id));

        // The owned process stops, but a foreign listener grabs the port.
        ports.Occupy(8080, 9999);
        processes.OnStop = _ => ports.ReleasePid(8080, 7777);

        var stopped = await manager.StopAsync(config.Id);

        Assert.False(stopped);
        var state = manager.Find(config.Id)!;
        Assert.Equal(ManagedServiceStatus.Conflict, state.Status);
        Assert.Equal(9999, Assert.Single(state.Conflict!.Occupants).Pid);
    }

    [Fact]
    public async Task RestartStopsThenStartsAgain()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var manager = Create(storage, processes, ports);
        var config = Config();
        Assert.Null(manager.Add(config));
        ports.OccupyAfter(8080, calls: 1, pid: 7777);
        Assert.True(await manager.StartAsync(config.Id));

        ports.OccupyAfter(8080, calls: 4, pid: 8888);
        processes.OnStop = _ => ports.Release(8080);

        var restarted = await manager.RestartAsync(config.Id);

        Assert.True(restarted);
        Assert.Equal(2, processes.StartedPids.Count);
        Assert.Equal(ManagedServiceStatus.Running, manager.Find(config.Id)!.Status);
    }

    [Fact]
    public async Task ResolveConflictKillsOnlyConfirmedPidsThenStarts()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var manager = Create(storage, processes, ports);
        var config = Config();
        Assert.Null(manager.Add(config));
        ports.Occupy(8080, 4242);
        Assert.False(await manager.StartAsync(config.Id));
        Assert.Equal(ManagedServiceStatus.Conflict, manager.Find(config.Id)!.Status);

        // The confirmed occupant dies on the graceful signal and only the
        // newly launched process listens afterwards.
        ports.OccupyAfter(8080, calls: 4, pid: 5150);

        var resolved = await manager.ResolveConflictAndStartAsync(config.Id);

        Assert.True(resolved);
        Assert.Equal(new[] { 4242 }, ports.KilledPids);
        Assert.Equal(ManagedServiceStatus.Running, manager.Find(config.Id)!.Status);
    }

    [Fact]
    public async Task ResolveConflictReconflictsWhenPortStaysOccupied()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var manager = Create(storage, processes, ports);
        var config = Config();
        Assert.Null(manager.Add(config));
        ports.Occupy(8080, 4242);
        Assert.False(await manager.StartAsync(config.Id));

        // The confirmed occupant refuses to die; a new PID also appears.
        ports.KillShouldFail = true;
        ports.Occupy(8080, 5252);

        var resolved = await manager.ResolveConflictAndStartAsync(config.Id);

        Assert.False(resolved);
        var state = manager.Find(config.Id)!;
        Assert.Equal(ManagedServiceStatus.Conflict, state.Status);
        Assert.Equal(2, state.Conflict!.Occupants.Count);
        Assert.Empty(processes.StartedPids);
        Assert.Contains(true, ports.KillForce);
    }

    [Fact]
    public async Task ReconcileMarksUnownedOccupancyAsConflict()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var manager = Create(storage, new FakeProcessController(), ports);
        var config = Config();
        Assert.Null(manager.Add(config));

        await manager.ReconcileAsync(new List<PortInfo> { Active(8080, 6001) });

        var state = manager.Find(config.Id)!;
        Assert.Equal(ManagedServiceStatus.Conflict, state.Status);
        Assert.Equal(6001, Assert.Single(state.Conflict!.Occupants).Pid);
    }

    [Fact]
    public void PersistenceRoundTripsThroughStorage()
    {
        var storage = new FakeStorage();
        var manager = Create(storage, new FakeProcessController(), new FakePortInspector());
        Assert.Null(manager.Add(Config("web", 8080)));
        Assert.Null(manager.Add(Config("api", 8081)));

        var reloaded = Create(storage, new FakeProcessController(), new FakePortInspector());
        var services = reloaded.Load();

        Assert.Equal(2, services.Count);
        Assert.Equal(new[] { "web", "api" }, services.Select(s => s.Name).ToArray());
        Assert.All(services, s => Assert.Equal(ManagedServiceStatus.Stopped, s.Status));
    }

    [Fact]
    public async Task RemoveIsRejectedWhileTheServiceIsOwned()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var manager = Create(storage, processes, ports);
        var config = Config();
        Assert.Null(manager.Add(config));
        ports.OccupyAfter(8080, calls: 1, pid: 7777);
        Assert.True(await manager.StartAsync(config.Id));

        Assert.False(await manager.RemoveAsync(config.Id));
        Assert.Single(manager.Services);
    }

    [Fact]
    public void OutputIsBoundedPerService()
    {
        var state = new ManagedServiceState(Config());
        for (var i = 0; i < ManagedServiceState.MaxOutputLines + 50; i++)
        {
            state.AppendOutput($"line {i}", ManagedServiceLogStream.StandardOutput);
        }

        Assert.Equal(ManagedServiceState.MaxOutputLines, state.RecentOutput.Count);
        Assert.Equal($"line {ManagedServiceState.MaxOutputLines + 49}", state.RecentOutput.Last().Text);
    }

    private static PortInfo Active(int port, int pid) => new()
    {
        Port = port,
        Pid = pid,
        ProcessName = "foreign",
        Address = "127.0.0.1",
        User = "tester",
        Command = "foreign --port",
    };

    private sealed class AlwaysExistingDirectoryValidator : IManagedServiceDirectoryValidator
    {
        public bool IsExistingDirectory(string path) => true;
    }

    private sealed class FakeStorage : IManagedServiceStorage
    {
        private List<ManagedServiceConfig> _configs = new();

        public IReadOnlyList<ManagedServiceConfig> Load() => _configs.Select(c => c.Clone()).ToList();

        public void Save(IEnumerable<ManagedServiceConfig> services)
            => _configs = services.Select(c => c.Clone()).ToList();
    }

    private sealed class FakeProcessController : IManagedServiceProcessController
    {
        public event EventHandler<ManagedServiceOutputEventArgs>? Output;
        public List<int> StartedPids { get; } = new();
        public List<int> StoppedPids { get; } = new();
        public Action<int>? OnStop { get; set; }
        public bool ExitImmediately { get; set; }

        public void RaiseOutput(Guid id, string text) =>
            Output?.Invoke(this, new ManagedServiceOutputEventArgs(id, ManagedServiceLogStream.StandardOutput, text));

        public Task<int> StartAsync(ManagedServiceConfig config, CancellationToken cancellationToken = default)
        {
            var pid = 7000 + StartedPids.Count;
            StartedPids.Add(pid);
            return Task.FromResult(pid);
        }

        public Task StopAsync(int rootPid, CancellationToken cancellationToken = default)
        {
            StoppedPids.Add(rootPid);
            OnStop?.Invoke(rootPid);
            return Task.CompletedTask;
        }

        public bool IsRunning(int rootPid) => !ExitImmediately && !StoppedPids.Contains(rootPid);
    }

    private sealed class FakePortInspector : IManagedServicePortInspector
    {
        private readonly Dictionary<int, List<PortInfo>> _occupants = new();
        private readonly Dictionary<int, int> _calls = new();
        private readonly Dictionary<int, (int Threshold, int Pid)> _later = new();

        public List<int> KilledPids { get; } = new();
        public List<bool> KillForce { get; } = new();
        public bool KillShouldFail { get; set; }

        public void Occupy(int port, int pid)
        {
            if (!_occupants.TryGetValue(port, out var list))
            {
                list = new List<PortInfo>();
                _occupants[port] = list;
            }
            if (list.All(p => p.Pid != pid)) list.Add(Active(port, pid));
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
}
