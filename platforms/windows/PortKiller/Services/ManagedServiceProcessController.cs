using System.Diagnostics;
using PortKiller.Models;

namespace PortKiller.Services;

/// <summary>
/// Launches and terminates managed service processes.
///
/// A service runs through <c>cmd.exe /d /s /c &lt;command&gt;</c> with
/// <c>CreateNoWindow</c>, a redirected stdout/stderr and the
/// <c>PORT_MANAGER_SERVICE_ID</c> environment marker. Stop only ever targets
/// the tracked owned root and its tree; the controller never discovers kill
/// targets by port.
/// </summary>
public sealed class ManagedServiceProcessController : IManagedServiceProcessController
{
    private readonly object _gate = new();
    private readonly Dictionary<int, Process> _processes = new();

    public event EventHandler<ManagedServiceOutputEventArgs>? Output;

    public Task<int> StartAsync(ManagedServiceConfig config, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var command = ManagedServiceCommandRenderer.Render(config.StartCommand, config.Port);
        var psi = new ProcessStartInfo(ResolveShell())
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WorkingDirectory = config.WorkingDirectory,
        };
        psi.ArgumentList.Add("/d");
        psi.ArgumentList.Add("/s");
        psi.ArgumentList.Add("/c");
        psi.ArgumentList.Add(command);
        psi.Environment["PORT_MANAGER_SERVICE_ID"] = config.Id.ToString("D");

        var process = new Process { StartInfo = psi, EnableRaisingEvents = true };
        process.OutputDataReceived += (_, e) =>
        {
            if (e.Data is not null)
                Output?.Invoke(this, new ManagedServiceOutputEventArgs(config.Id, ManagedServiceLogStream.StandardOutput, e.Data));
        };
        process.ErrorDataReceived += (_, e) =>
        {
            if (e.Data is not null)
                Output?.Invoke(this, new ManagedServiceOutputEventArgs(config.Id, ManagedServiceLogStream.StandardError, e.Data));
        };

        if (!process.Start())
        {
            process.Dispose();
            throw new InvalidOperationException("Unable to start service process.");
        }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        lock (_gate) _processes[process.Id] = process;
        return Task.FromResult(process.Id);
    }

    public async Task StopAsync(int rootPid, CancellationToken cancellationToken = default)
    {
        Process? process;
        lock (_gate) _processes.TryGetValue(rootPid, out process);

        if (process is null)
        {
            try
            {
                process = Process.GetProcessById(rootPid);
            }
            catch (ArgumentException)
            {
                return;
            }
        }

        try
        {
            if (!process.HasExited)
            {
                // Console children of cmd.exe report no main window, so the
                // graceful phase is skipped and the owned tree is terminated.
                var graceful = false;
                try { graceful = process.CloseMainWindow(); }
                catch (InvalidOperationException) { }

                if (!graceful || !process.WaitForExit(500))
                {
                    process.Kill(entireProcessTree: true);
                    await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
                }
            }
        }
        catch (InvalidOperationException) { }
        catch (System.ComponentModel.Win32Exception) { }
        finally
        {
            lock (_gate) _processes.Remove(rootPid);
            process.Dispose();
        }
    }

    public bool IsRunning(int rootPid)
    {
        if (rootPid <= 0) return false;
        Process? tracked;
        lock (_gate) _processes.TryGetValue(rootPid, out tracked);
        try
        {
            if (tracked is not null) return !tracked.HasExited;
            using var process = Process.GetProcessById(rootPid);
            return !process.HasExited;
        }
        catch (ArgumentException)
        {
            return false;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }

    private static string ResolveShell()
    {
        var comSpec = Environment.GetEnvironmentVariable("ComSpec");
        return string.IsNullOrWhiteSpace(comSpec) ? "cmd.exe" : comSpec;
    }
}
