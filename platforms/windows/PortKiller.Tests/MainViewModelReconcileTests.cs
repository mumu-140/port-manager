using System.IO;
using System.Windows.Threading;
using PortKiller.Models;
using PortKiller.Services;
using PortKiller.ViewModels;
using Xunit;

namespace PortKiller.Tests;

public class MainViewModelReconcileTests
{
    private static ManagedServiceConfig Config(int port) => new()
    {
        Id = Guid.NewGuid(),
        Name = "web",
        Port = port,
        Host = "localhost",
        WorkingDirectory = Path.GetTempPath(),
        StartCommand = "dotnet run --urls http://localhost:{port}",
    };

    [Fact]
    public async Task SharedScanReconcilesManagedServicesWithoutThePanelRefresh()
    {
        var storage = new FakeStorage();
        var ports = new FakePortInspector();
        var processes = new FakeProcessController();
        var manager = new ManagedServiceManager(storage, processes, ports, new AlwaysExistingDirectoryValidator());
        var config = Config(8080);
        Assert.Null(manager.Add(config));
        ports.OccupyAfter(8080, calls: 1, pid: 7777);
        Assert.True(await manager.StartAsync(config.Id));

        // The shared scan now reports a different, unowned listener for the port.
        var scanner = new StubScanner(new List<PortInfo> { TestPortInfo.Active(8080, 9999) });
        var settingsPath = Path.Combine(Path.GetTempPath(), $"portkiller-test-{Guid.NewGuid():N}.json");
        var viewModel = new MainViewModel(
            scanner,
            new ProcessKillerService(),
            new SettingsService(settingsPath),
            NotificationService.Instance,
            Dispatcher.CurrentDispatcher,
            manager);

        await viewModel.RefreshPortsAsync();

        var state = manager.Find(config.Id)!;
        Assert.Equal(ManagedServiceStatus.Conflict, state.Status);
        Assert.False(state.IsOwned);
    }

    private sealed class StubScanner : PortScannerService
    {
        private readonly List<PortInfo> _ports;

        public StubScanner(List<PortInfo> ports) => _ports = ports;

        public override Task<List<PortInfo>> ScanPortsAsync() => Task.FromResult(_ports.ToList());
    }
}
