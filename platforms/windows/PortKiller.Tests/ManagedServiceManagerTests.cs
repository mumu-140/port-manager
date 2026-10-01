using System.IO;
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
        FakePortInspector ports,
        IManagedServiceTunnelCoordinator? tunnel = null) =>
        new(storage, processes, ports, new AlwaysExistingDirectoryValidator(), tunnel);

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
    public async Task StartReleasesOwnershipWhenInspectingFailsMidReadiness()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector
        {
            InspectFailure = (AfterCalls: 1, Error: new InvalidOperationException("scan failed")),
        };
        var processes = new FakeProcessController();
        var manager = Create(storage, processes, ports);
        var config = Config();
        Assert.Null(manager.Add(config));

        await Assert.ThrowsAsync<InvalidOperationException>(() => manager.StartAsync(config.Id));

        var state = manager.Find(config.Id)!;
        Assert.Equal(ManagedServiceStatus.Failed, state.Status);
        Assert.Null(state.RootPid);
        Assert.Contains(config.Id, processes.StopRequests);
        Assert.False(processes.IsTracked(config.Id));
    }

    [Fact]
    public async Task ConcurrentStartsLaunchExactlyOneRuntime()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var manager = Create(storage, processes, ports);
        var config = Config();
        Assert.Null(manager.Add(config));

        // Barrier on the preflight: the first inspection waits (bounded) for a
        // second caller to arrive. Without a lifecycle gate both Starts pass the
        // state guard and the empty preflight together, then both launch.
        var arrivals = 0;
        var bothArrived = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        ports.BeforeInspect = async () =>
        {
            var n = Interlocked.Increment(ref arrivals);
            if (n == 2) bothArrived.TrySetResult();
            if (n == 1) await Task.WhenAny(bothArrived.Task, Task.Delay(500)).ConfigureAwait(false);
        };
        // The port listens once the readiness loop inspects after a launch.
        ports.OccupyAfter(config.Port, 2, 9100);

        var a = manager.StartAsync(config.Id);
        var b = manager.StartAsync(config.Id);
        var results = await Task.WhenAll(a, b);

        Assert.Single(processes.StartedPids);
        Assert.Equal(1, results.Count(r => r));
        var state = manager.Find(config.Id)!;
        Assert.Equal(ManagedServiceStatus.Running, state.Status);
        Assert.True(processes.IsTracked(config.Id));
        Assert.Equal((int?)processes.StartedPids[0], state.RootPid);
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

    [Fact]
    public async Task StartLeavesTunnelsAlone()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var tunnel = new FakeTunnelCoordinator();
        var manager = Create(storage, processes, ports, tunnel);
        var config = Config();
        Assert.Null(manager.Add(config));
        ports.OccupyAfter(8080, calls: 1, pid: 7777);

        Assert.True(await manager.StartAsync(config.Id));
        Assert.Empty(tunnel.StoppedPorts);
    }

    [Fact]
    public async Task StopReleasesTheAssociatedTunnel()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var tunnel = new FakeTunnelCoordinator();
        var manager = Create(storage, processes, ports, tunnel);
        var config = Config();
        Assert.Null(manager.Add(config));
        ports.OccupyAfter(8080, calls: 1, pid: 7777);
        Assert.True(await manager.StartAsync(config.Id));

        processes.OnStop = _ => ports.Release(8080);
        Assert.True(await manager.StopAsync(config.Id));
        Assert.Equal(new[] { 8080 }, tunnel.StoppedPorts);
    }

    [Fact]
    public async Task RestartReleasesTheTunnelWithoutSharingAgain()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var tunnel = new FakeTunnelCoordinator();
        var manager = Create(storage, processes, ports, tunnel);
        var config = Config();
        Assert.Null(manager.Add(config));
        ports.OccupyAfter(8080, calls: 1, pid: 7777);
        Assert.True(await manager.StartAsync(config.Id));

        ports.OccupyAfter(8080, calls: 4, pid: 8888);
        processes.OnStop = _ => ports.Release(8080);

        Assert.True(await manager.RestartAsync(config.Id));
        Assert.Equal(new[] { 8080 }, tunnel.StoppedPorts);
        Assert.Equal(ManagedServiceStatus.Running, manager.Find(config.Id)!.Status);
    }

    // MARK: - Edit guard (design notes, section 12)

    [Fact]
    public async Task UpdateIsRejectedWhileRunning()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var manager = Create(storage, processes, ports);
        var config = Config("web", 8080);
        Assert.Null(manager.Add(config));
        ports.OccupyAfter(8080, calls: 1, pid: 7777);
        Assert.True(await manager.StartAsync(config.Id));

        var edited = config.Clone();
        edited.Name = "renamed";
        var error = manager.Update(edited);

        Assert.NotNull(error);
        Assert.Equal(ManagedServiceValidationErrorKind.ServiceRunning, error!.Kind);
        Assert.Equal("web", manager.Find(config.Id)!.Name);
    }

    [Fact]
    public void UpdateIsRejectedWhileTransitioning()
    {
        var manager = Create(new FakeStorage(), new FakeProcessController(), new FakePortInspector());
        var config = Config();
        Assert.Null(manager.Add(config));
        manager.Find(config.Id)!.Status = ManagedServiceStatus.Starting;

        var error = manager.Update(config.Clone());

        Assert.NotNull(error);
        Assert.Equal(ManagedServiceValidationErrorKind.ServiceTransitioning, error!.Kind);
    }

    [Fact]
    public void UpdateIsAllowedWhenStopped()
    {
        var manager = Create(new FakeStorage(), new FakeProcessController(), new FakePortInspector());
        var config = Config("web", 8080);
        Assert.Null(manager.Add(config));
        var edited = config.Clone();
        edited.Name = "renamed";

        Assert.Null(manager.Update(edited));
        Assert.Equal("renamed", manager.Find(config.Id)!.Name);
        Assert.Equal("renamed", manager.Configs.Single().Name);
    }

    // MARK: - Ownership by service id (design notes, section 6.5)

    [Fact]
    public async Task ReconcileNeverStopsAnUntrackedReusedPid()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var manager = Create(storage, processes, ports);
        var config = Config();
        Assert.Null(manager.Add(config));
        ports.OccupyAfter(8080, calls: 1, pid: 7000);
        Assert.True(await manager.StartAsync(config.Id));
        Assert.Equal(7000, manager.Find(config.Id)!.RootPid);

        // The runtime is no longer tracked (it exited and was pruned), yet the
        // old PID still appears in the scan. A reused PID must never be killed.
        processes.Forget(config.Id);
        Assert.False(processes.IsRunning(config.Id));

        await manager.ReconcileAsync(new List<PortInfo> { Active(8080, 7000) });

        Assert.Empty(processes.StoppedPids);
        Assert.Equal(new[] { config.Id }, processes.StopRequests);
        Assert.Equal(ManagedServiceStatus.Failed, manager.Find(config.Id)!.Status);
    }

    [Fact]
    public async Task StopOnlySignalsATrackedRuntime()
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
        processes.Forget(config.Id);

        var stopped = await manager.StopAsync(config.Id);

        Assert.True(stopped);
        Assert.Empty(processes.StoppedPids);
        Assert.Equal(new[] { config.Id }, processes.StopRequests);
    }

    // MARK: - Dispatcher marshalling (design notes, section 20)

    [Fact]
    public async Task EveryObservableMutationGoesThroughTheStateDispatcher()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var dispatcher = new RecordingStateDispatcher();
        var manager = new ManagedServiceManager(
            storage,
            processes,
            ports,
            new AlwaysExistingDirectoryValidator(),
            null,
            dispatcher);
        var config = Config();
        Assert.Null(manager.Add(config));
        ports.OccupyAfter(8080, calls: 1, pid: 7777);

        Assert.True(await manager.StartAsync(config.Id));
        Assert.True(dispatcher.InvokeCount > 0);

        processes.RaiseOutput(config.Id, "hello from stdout");

        Assert.True(dispatcher.PostCount > 0);
        Assert.Contains("hello from stdout", manager.Find(config.Id)!.RecentOutput.Select(e => e.Text));
    }

    [Fact]
    public void RuntimeLogStorePreparesTruncatesAndCleansPerService()
    {
        var id = Guid.NewGuid();
        ManagedServiceRuntimeLogStore.Prepare(id, out var stdout, out var stderr);

        Assert.True(File.Exists(stdout));
        Assert.True(File.Exists(stderr));
        Assert.StartsWith(ManagedServiceRuntimeLogStore.RootDirectory, stdout, StringComparison.OrdinalIgnoreCase);

        File.AppendAllText(stdout, "previous run output");
        ManagedServiceRuntimeLogStore.Prepare(id, out var stdoutAgain, out _);
        Assert.Equal(string.Empty, File.ReadAllText(stdoutAgain));

        ManagedServiceRuntimeLogStore.Cleanup(id);
        Assert.False(Directory.Exists(ManagedServiceRuntimeLogStore.DirectoryFor(id)));
    }

    private static PortInfo Active(int port, int pid) => TestPortInfo.Active(port, pid);
}
