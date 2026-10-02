using System.IO;
using PortKiller.Models;
using PortKiller.Services;
using PortKiller.ViewModels;
using Xunit;

namespace PortKiller.Tests;

public class ManagedServicesViewModelTests
{
    private static ManagedServiceConfig Config(string name = "web", int port = 8080) => new()
    {
        Id = Guid.NewGuid(),
        Name = name,
        Port = port,
        Host = "localhost",
        WorkingDirectory = Path.GetTempPath(),
        StartCommand = "dotnet run --urls http://localhost:{port}",
    };

    private static ManagedServiceManager Manager(
        FakeStorage storage,
        FakeProcessController processes,
        FakePortInspector ports) =>
        new(storage, processes, ports, new AlwaysExistingDirectoryValidator());

    [Fact]
    public void SearchFiltersServicesIndependently()
    {
        var storage = new FakeStorage();
        var manager = Manager(storage, new FakeProcessController(), new FakePortInspector());
        Assert.Null(manager.Add(Config("web", 8080)));
        Assert.Null(manager.Add(Config("api", 8081)));
        var vm = new ManagedServicesViewModel(manager, new FakeTunnelHost());
        vm.Load();

        vm.SearchText = "api";

        Assert.Equal("api", Assert.Single(vm.FilteredServices).Name);
        Assert.Equal(2, vm.Services.Count);

        vm.SearchText = string.Empty;
        Assert.Equal(2, vm.FilteredServices.Count);
    }

    [Fact]
    public async Task DeleteTransitioningServiceKeepsItInTheUi()
    {
        var storage = new FakeStorage();
        var processes = new FakeProcessController();
        var manager = Manager(storage, processes, new FakePortInspector());
        var config = Config();
        Assert.Null(manager.Add(config));
        var vm = new ManagedServicesViewModel(manager, new FakeTunnelHost());
        vm.Load();
        manager.Find(config.Id)!.Status = ManagedServiceStatus.Starting;

        await vm.DeleteCommand.ExecuteAsync(null);

        Assert.Single(vm.Services);
        Assert.Single(manager.Services);
        Assert.Empty(processes.StopRequests);
    }

    [Fact]
    public async Task DeleteRunningServiceStopsOwnedRuntimeThenRemovesProfile()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var manager = Manager(storage, processes, ports);
        var config = Config();
        Assert.Null(manager.Add(config));
        var vm = new ManagedServicesViewModel(manager, new FakeTunnelHost());
        vm.Load();
        ports.OccupyAfter(8080, calls: 1, pid: 7777);
        Assert.True(await manager.StartAsync(config.Id));
        ports.Release(8080);
        processes.OnStop = _ => ports.Release(8080);

        await vm.DeleteCommand.ExecuteAsync(null);

        Assert.Contains(7000, processes.StoppedPids);
        Assert.Empty(vm.Services);
        Assert.Empty(manager.Services);
    }

    [Fact]
    public async Task DeleteConflictProfileNeverKillsTheOccupant()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var manager = Manager(storage, processes, ports);
        var config = Config();
        Assert.Null(manager.Add(config));
        var vm = new ManagedServicesViewModel(manager, new FakeTunnelHost());
        vm.Load();
        ports.Occupy(8080, 4242);
        Assert.False(await manager.StartAsync(config.Id));
        Assert.Equal(ManagedServiceStatus.Conflict, vm.SelectedService!.Status);

        await vm.DeleteCommand.ExecuteAsync(null);

        Assert.Empty(vm.Services);
        Assert.Empty(manager.Services);
        Assert.Empty(ports.KilledPids);
        Assert.Empty(processes.StopRequests);
    }

    [Fact]
    public async Task EditPreparationStopsOnlyTheOwnedRuntimeAndDoesNotRestart()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var manager = Manager(storage, processes, ports);
        var config = Config();
        Assert.Null(manager.Add(config));
        var vm = new ManagedServicesViewModel(manager, new FakeTunnelHost());
        vm.Load();
        ports.OccupyAfter(8080, calls: 1, pid: 7777);
        Assert.True(await manager.StartAsync(config.Id));
        ports.Release(8080);
        processes.OnStop = _ => ports.Release(8080);

        var prepared = await vm.PrepareForEditAsync();

        Assert.True(prepared);
        Assert.Equal(ManagedServiceStatus.Stopped, manager.Find(config.Id)!.Status);
        Assert.Contains(7000, processes.StoppedPids);

        var edited = config.Clone();
        edited.Name = "renamed";
        Assert.Null(vm.SaveProfile(edited, isNew: false));

        Assert.Equal(ManagedServiceStatus.Stopped, manager.Find(config.Id)!.Status);
        Assert.Single(processes.StartedPids);
    }

    [Fact]
    public void CanDeleteIsDisabledWhileTransitioning()
    {
        var manager = Manager(new FakeStorage(), new FakeProcessController(), new FakePortInspector());
        var config = Config();
        Assert.Null(manager.Add(config));
        var vm = new ManagedServicesViewModel(manager, new FakeTunnelHost());
        vm.Load();

        Assert.True(vm.CanDelete);

        manager.Find(config.Id)!.Status = ManagedServiceStatus.Stopping;
        vm.NotifySelectedChanged();

        Assert.False(vm.CanDelete);
        Assert.False(vm.CanEdit);
    }
    [Fact]
    public async Task LivePortCheckFindsExternalOccupant()
    {
        var ports = new FakePortInspector();
        var manager = Manager(new FakeStorage(), new FakeProcessController(), ports);
        var vm = new ManagedServicesViewModel(manager, new FakeTunnelHost());
        ports.Occupy(38902, 4242);

        var listeners = await vm.InspectPortForEditorAsync(38902, editingId: null);

        var listener = Assert.Single(listeners);
        Assert.Equal(4242, listener.Pid);
    }

    [Fact]
    public async Task LivePortCheckFiltersEditedServicesOwnListener()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var manager = Manager(storage, processes, ports);
        var config = Config(port: 38902);
        Assert.Null(manager.Add(config));
        var vm = new ManagedServicesViewModel(manager, new FakeTunnelHost());
        vm.Load();

        ports.OccupyAfter(38902, calls: 1, pid: 7777);
        Assert.True(await manager.StartAsync(config.Id));

        var listeners = await vm.InspectPortForEditorAsync(38902, config.Id);

        Assert.Empty(listeners);
    }

    [Fact]
    public void LivePortCheckFindsAnotherSavedProfileReservation()
    {
        var manager = Manager(new FakeStorage(), new FakeProcessController(), new FakePortInspector());
        var first = Config("proxy-a", 38902);
        var second = Config("proxy-b", 38903);
        Assert.Null(manager.Add(first));
        Assert.Null(manager.Add(second));
        var vm = new ManagedServicesViewModel(manager, new FakeTunnelHost());
        vm.Load();

        var reserved = vm.FindOtherProfileUsingPort(38902, second.Id);

        Assert.NotNull(reserved);
        Assert.Equal(first.Id, reserved!.Id);
        Assert.Null(vm.FindOtherProfileUsingPort(38902, first.Id));
    }

}
