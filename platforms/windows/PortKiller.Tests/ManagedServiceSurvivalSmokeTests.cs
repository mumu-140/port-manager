using System.Diagnostics;
using System.IO;
using PortKiller.Models;
using PortKiller.Services;
using Xunit;

namespace PortKiller.Tests;

/// <summary>
/// End-to-end app-quit survival smoke test. Both facts return immediately
/// unless <c>PORTKILLER_SURVIVAL_SMOKE</c> selects a phase, because the launch
/// phase deliberately leaves a real child running so
/// <c>scripts/smoke-service-survival.ps1</c> can prove it outlives this
/// process.
///
/// launch phase: start a real managed service through the production manager,
///               then return; the test process exits, simulating quitting Port
///               Manager without stopping the child.
/// relaunch phase: reload the profile in a fresh process, reconcile against a
///               real Windows port scan and require the survivor to appear as
///               a Conflict this app does not own.
/// </summary>
public class ManagedServiceSurvivalSmokeTests
{
    private const string SmokeVariable = "PORTKILLER_SURVIVAL_SMOKE";
    private static readonly Guid ServiceId = Guid.Parse("A1B2C3D4-0000-4000-8000-000000000002");

    [Fact]
    public async Task LaunchServiceThenLetThisProcessExit()
    {
        if (Environment.GetEnvironmentVariable(SmokeVariable) != "launch") return;

        var port = int.Parse(Environment.GetEnvironmentVariable("PORTKILLER_SURVIVAL_PORT")!);
        var script = Environment.GetEnvironmentVariable("PORTKILLER_SURVIVAL_SCRIPT")!;
        var info = Environment.GetEnvironmentVariable("PORTKILLER_SURVIVAL_INFO")!;
        var settings = Environment.GetEnvironmentVariable("PORTKILLER_SURVIVAL_SETTINGS")!;

        var config = new ManagedServiceConfig
        {
            Id = ServiceId,
            Name = "Survival Smoke",
            Port = port,
            Host = "localhost",
            WorkingDirectory = Path.GetDirectoryName(script)!,
            StartCommand = $"powershell -NoProfile -ExecutionPolicy Bypass -File \"{script}\" {{port}}",
        };

        var scanner = new PortScannerService();
        var manager = new ManagedServiceManager(
            new SettingsManagedServiceStorage(new SettingsService(settings)),
            new ManagedServiceProcessController(),
            new ManagedServicePortInspector(scanner, new ProcessKillerService()),
            new FileSystemManagedServiceDirectoryValidator());

        Assert.Null(manager.Add(config));
        var started = await manager.StartAsync(config.Id);

        var state = manager.Find(config.Id)!;
        Assert.True(started, $"service did not reach running (status={state.Status}, error={state.LastError})");
        var pid = state.RootPid!.Value;

        File.WriteAllText(
            info,
            $"pid={pid}\nstdout={ManagedServiceRuntimeLogStore.StdoutPath(ServiceId)}\nstderr={ManagedServiceRuntimeLogStore.StderrPath(ServiceId)}\n");

        // Intentionally no stop: this process exiting is the simulated quit.
    }

    [Fact]
    public async Task RelaunchDetectsSurvivingServiceAsConflict()
    {
        if (Environment.GetEnvironmentVariable(SmokeVariable) != "relaunch") return;

        var infoPath = Environment.GetEnvironmentVariable("PORTKILLER_SURVIVAL_INFO")!;
        var settings = Environment.GetEnvironmentVariable("PORTKILLER_SURVIVAL_SETTINGS")!;
        var info = File.ReadAllText(infoPath);
        var expectedPid = int.Parse(info.Split('\n').First(l => l.StartsWith("pid=")).Substring(4));

        var scanner = new PortScannerService();
        var manager = new ManagedServiceManager(
            new SettingsManagedServiceStorage(new SettingsService(settings)),
            new ManagedServiceProcessController(),
            new ManagedServicePortInspector(scanner, new ProcessKillerService()),
            new FileSystemManagedServiceDirectoryValidator());

        manager.Load();
        await manager.ReconcileAsync(await scanner.ScanPortsAsync());

        var state = manager.Find(ServiceId)!;
        Assert.Equal(ManagedServiceStatus.Conflict, state.Status);
        Assert.False(state.IsOwned);
        Assert.Null(state.RootPid);
        Assert.Contains(expectedPid, state.Conflict!.Occupants.Select(o => o.Pid));

        // A fresh manager does not own the survivor and must not stop it.
        Assert.False(await manager.StopAsync(ServiceId));
        Assert.True(IsAlive(expectedPid), "fresh manager stopped a service it does not own");

        KillTree(expectedPid);
    }

    private static bool IsAlive(int pid)
    {
        try
        {
            using var process = Process.GetProcessById(pid);
            return !process.HasExited;
        }
        catch (ArgumentException)
        {
            return false;
        }
    }

    private static void KillTree(int pid)
    {
        try
        {
            using var process = Process.GetProcessById(pid);
            process.Kill(entireProcessTree: true);
            process.WaitForExit(5000);
        }
        catch (Exception)
        {
        }
    }
}
