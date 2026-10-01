using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using PortKiller.Models;
using PortKiller.Services;
using Xunit;

namespace PortKiller.Tests;

/// <summary>
/// Real process-tree containment through the production native launcher and
/// job object. The root (cmd.exe) starts a child (powershell) that owns the
/// listener. Stop terminates the job, not a PID, so the listener can only
/// disappear if the child was created inside the job.
/// </summary>
public class ManagedServiceProcessTreeTests
{
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsProcessInJob(IntPtr processHandle, IntPtr jobHandle, out bool result);

    [Fact]
    public void ProductionLauncherReturnsARootAlreadyInsideItsJob()
    {
        var id = Guid.NewGuid();
        ManagedServiceRuntimeLogStore.Prepare(id, out var stdout, out var stderr);
        var pid = ManagedServiceRuntimeLauncher.Launch(
            "ping -n 6 127.0.0.1 >NUL", Path.GetTempPath(), id, stdout, stderr,
            out var process, out var job);
        try
        {
            Assert.True(pid > 0);
            Assert.NotEqual(IntPtr.Zero, process);
            Assert.NotEqual(IntPtr.Zero, job);
            Assert.True(IsProcessInJob(process, job, out var inJob));
            Assert.True(inJob);
        }
        finally
        {
            ManagedServiceRuntimeLauncher.TerminateTree(job, process);
            ManagedServiceRuntimeLauncher.WaitForExit(process, 5000);
            ManagedServiceRuntimeLauncher.CloseHandleQuietly(job);
            ManagedServiceRuntimeLauncher.CloseHandleQuietly(process);
            ManagedServiceRuntimeLogStore.Cleanup(id);
        }
    }

    [Fact]
    public async Task StopTerminatesTheWholeContainedTreeAndFreesThePort()
    {
        var work = Directory.CreateTempSubdirectory("portkiller-tree-");
        var script = Path.Combine(work.FullName, "listen.ps1");
        File.WriteAllText(script, """
            param([int]$Port)
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
            $listener.Start()
            while ($true) { Start-Sleep -Milliseconds 200 }
            """);

        var port = FreePort();
        var config = new ManagedServiceConfig
        {
            Id = Guid.NewGuid(),
            Name = "Process Tree",
            Port = port,
            Host = "localhost",
            WorkingDirectory = work.FullName,
            StartCommand = $"powershell -NoProfile -ExecutionPolicy Bypass -File \"{script}\" {{port}}",
        };

        var scanner = new PortScannerService();
        var manager = new ManagedServiceManager(
            new FakeStorage(),
            new ManagedServiceProcessController(),
            new ManagedServicePortInspector(scanner, new ProcessKillerService()),
            new FileSystemManagedServiceDirectoryValidator());

        int rootPid = 0, listenerPid = 0;
        try
        {
            Assert.Null(manager.Add(config));
            var started = await manager.StartAsync(config.Id);
            var state = manager.Find(config.Id)!;
            Assert.True(started, $"service did not reach running (status={state.Status}, error={state.LastError})");
            Assert.Equal(ManagedServiceStatus.Running, state.Status);

            rootPid = state.RootPid!.Value;
            listenerPid = (await scanner.ScanPortsAsync()).Where(p => p.Port == port).Select(p => p.Pid).FirstOrDefault();
            Assert.NotEqual(0, listenerPid);
            Assert.NotEqual(rootPid, listenerPid);
            Assert.True(Exists(rootPid), "root is not running");
            Assert.True(Exists(listenerPid), "child listener is not running");

            Assert.True(await manager.StopAsync(config.Id));
            Assert.Equal(ManagedServiceStatus.Stopped, manager.Find(config.Id)!.Status);

            Assert.True(await WaitGoneAsync(rootPid), "root survived stop");
            Assert.True(await WaitGoneAsync(listenerPid), "child listener survived stop: tree was not contained");
            Assert.DoesNotContain(await scanner.ScanPortsAsync(), p => p.Port == port);

            var probe = new TcpListener(IPAddress.Loopback, port);
            probe.Start();
            probe.Stop();
        }
        finally
        {
            KillQuietly(listenerPid);
            KillQuietly(rootPid);
            ManagedServiceRuntimeLogStore.Cleanup(config.Id);
            try { work.Delete(recursive: true); } catch (Exception) { }
        }
    }

    private static int FreePort()
    {
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        listener.Stop();
        return port;
    }

    private static bool Exists(int pid)
    {
        if (pid == 0) return false;
        try
        {
            using var process = Process.GetProcessById(pid);
            return !process.HasExited;
        }
        catch (Exception)
        {
            return false;
        }
    }

    private static async Task<bool> WaitGoneAsync(int pid)
    {
        var deadline = DateTime.UtcNow + TimeSpan.FromSeconds(10);
        while (DateTime.UtcNow < deadline)
        {
            if (!Exists(pid)) return true;
            await Task.Delay(100);
        }
        return !Exists(pid);
    }

    private static void KillQuietly(int pid)
    {
        if (pid == 0) return;
        try
        {
            using var process = Process.GetProcessById(pid);
            process.Kill(entireProcessTree: true);
        }
        catch (Exception)
        {
        }
    }
}
