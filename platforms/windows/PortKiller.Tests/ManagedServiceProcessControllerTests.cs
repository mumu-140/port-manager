using System.IO;
using System.Runtime.InteropServices;
using PortKiller.Models;
using PortKiller.Services;
using Xunit;

namespace PortKiller.Tests;

/// <summary>
/// Controller ownership tests. The launch seam replaces native process
/// creation so a test can count launches directly instead of inferring them.
/// </summary>
public class ManagedServiceProcessControllerTests
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateJobObjectW(IntPtr lpJobAttributes, string? lpName);

    private static ManagedServiceConfig Config() => new()
    {
        Id = Guid.NewGuid(),
        Name = "controller",
        Port = 8080,
        Host = "localhost",
        WorkingDirectory = Path.GetTempPath(),
        StartCommand = "echo {port}",
    };

    [Fact]
    public async Task ProcessControllerRejectsSecondTrackedStartBeforeLaunch()
    {
        var launches = 0;
        var controller = new ManagedServiceProcessController(
            (string command, string? dir, Guid id, string so, string se, out IntPtr process, out IntPtr job) =>
            {
                Interlocked.Increment(ref launches);
                process = IntPtr.Zero;
                job = CreateJobObjectW(IntPtr.Zero, null);
                return 4242;
            });
        var config = Config();
        try
        {
            Assert.Equal(4242, await controller.StartAsync(config));

            await Assert.ThrowsAsync<InvalidOperationException>(() => controller.StartAsync(config));

            Assert.Equal(1, launches);
            Assert.Equal((int?)4242, controller.RootPid(config.Id));
        }
        finally
        {
            await controller.StopAsync(config.Id);
            ManagedServiceRuntimeLogStore.Cleanup(config.Id);
        }
    }

    [Fact]
    public async Task ProcessControllerRejectsStartWhileLaunchIsInFlight()
    {
        var launches = 0;
        using var entered = new ManualResetEventSlim();
        using var release = new ManualResetEventSlim();
        var controller = new ManagedServiceProcessController(
            (string command, string? dir, Guid id, string so, string se, out IntPtr process, out IntPtr job) =>
            {
                Interlocked.Increment(ref launches);
                entered.Set();
                release.Wait(TimeSpan.FromSeconds(10));
                process = IntPtr.Zero;
                job = CreateJobObjectW(IntPtr.Zero, null);
                return 4343;
            });
        var config = Config();
        try
        {
            var first = Task.Run(() => controller.StartAsync(config));
            Assert.True(entered.Wait(TimeSpan.FromSeconds(10)));

            await Assert.ThrowsAsync<InvalidOperationException>(() => controller.StartAsync(config));

            release.Set();
            Assert.Equal(4343, await first);
            Assert.Equal(1, launches);
        }
        finally
        {
            release.Set();
            await controller.StopAsync(config.Id);
            ManagedServiceRuntimeLogStore.Cleanup(config.Id);
        }
    }

    [Fact]
    public async Task ProcessControllerRejectsALaunchWithoutAJobObject()
    {
        var controller = new ManagedServiceProcessController(
            (string command, string? dir, Guid id, string so, string se, out IntPtr process, out IntPtr job) =>
            {
                process = IntPtr.Zero;
                job = IntPtr.Zero;
                return 4444;
            });
        var config = Config();
        try
        {
            await Assert.ThrowsAsync<InvalidOperationException>(() => controller.StartAsync(config));

            Assert.Null(controller.RootPid(config.Id));
            Assert.False(controller.IsRunning(config.Id));
        }
        finally
        {
            ManagedServiceRuntimeLogStore.Cleanup(config.Id);
        }
    }
}
