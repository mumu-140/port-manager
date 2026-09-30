using System.IO;
using System.Text;
using PortKiller.Models;

namespace PortKiller.Services;

/// <summary>
/// Windows process controller for managed services.
///
/// A runtime is owned by this controller for the lifetime of this instance and
/// is keyed by <c>serviceId</c>. Ownership is never re-derived from a PID: if a
/// service is not in the tracked table, this controller neither reports it as
/// running nor signals it. Output is tailed from the file-backed runtime logs
/// so a child that outlives Port Manager keeps writing (design notes, section
/// 6.5).
/// </summary>
public sealed class ManagedServiceProcessController : IManagedServiceProcessController
{
    private static readonly TimeSpan TailPollInterval = TimeSpan.FromMilliseconds(100);

    private readonly object _gate = new();
    private readonly Dictionary<Guid, Runtime> _runtimes = new();

    public event EventHandler<ManagedServiceOutputEventArgs>? Output;

    public Task<int> StartAsync(ManagedServiceConfig config, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var command = ManagedServiceCommandRenderer.Render(config.StartCommand, config.Port);
        ManagedServiceRuntimeLogStore.Prepare(config.Id, out var stdoutPath, out var stderrPath);

        int pid;
        IntPtr processHandle;
        IntPtr jobHandle;
        try
        {
            pid = ManagedServiceRuntimeLauncher.Launch(
                command,
                config.WorkingDirectory,
                config.Id,
                stdoutPath,
                stderrPath,
                out processHandle,
                out jobHandle);
        }
        catch
        {
            ManagedServiceRuntimeLogStore.Cleanup(config.Id);
            throw;
        }

        var runtime = new Runtime(config.Id, pid, processHandle, jobHandle);
        lock (_gate)
        {
            _runtimes[config.Id] = runtime;
        }

        StartTailers(runtime, stdoutPath, stderrPath);
        return Task.FromResult(pid);
    }

    public async Task StopAsync(Guid serviceId, CancellationToken cancellationToken = default)
    {
        Runtime? runtime;
        lock (_gate)
        {
            _runtimes.TryGetValue(serviceId, out runtime);
        }

        if (runtime is null) return;

        try
        {
            if (ManagedServiceRuntimeLauncher.IsAlive(runtime.ProcessHandle))
            {
                ManagedServiceRuntimeLauncher.TerminateTree(runtime.JobHandle, runtime.ProcessHandle);
                await Task.Run(() => ManagedServiceRuntimeLauncher.WaitForExit(runtime.ProcessHandle, 3000))
                    .ConfigureAwait(false);
            }
        }
        catch (Exception)
        {
            // A runtime that already exited needs no further signalling.
        }

        RemoveRuntime(serviceId, runtime);
    }

    public bool IsRunning(Guid serviceId)
    {
        Runtime? runtime;
        lock (_gate)
        {
            _runtimes.TryGetValue(serviceId, out runtime);
        }

        if (runtime is null) return false;
        if (ManagedServiceRuntimeLauncher.IsAlive(runtime.ProcessHandle)) return true;

        RemoveRuntime(serviceId, runtime);
        return false;
    }

    public int? RootPid(Guid serviceId)
    {
        lock (_gate)
        {
            return _runtimes.TryGetValue(serviceId, out var runtime) ? runtime.RootPid : null;
        }
    }

    private void StartTailers(Runtime runtime, string stdoutPath, string stderrPath)
    {
        var stdout = OpenRead(stdoutPath);
        var stderr = OpenRead(stderrPath);
        runtime.StdoutStream = stdout;
        runtime.StderrStream = stderr;

        if (stdout is not null)
        {
            runtime.StdoutTask = Task.Run(() =>
                TailAsync(runtime, stdout, ManagedServiceLogStream.StandardOutput, runtime.TailToken.Token));
        }

        if (stderr is not null)
        {
            runtime.StderrTask = Task.Run(() =>
                TailAsync(runtime, stderr, ManagedServiceLogStream.StandardError, runtime.TailToken.Token));
        }
    }

    private static FileStream? OpenRead(string path)
    {
        try
        {
            return new FileStream(
                path,
                FileMode.Open,
                FileAccess.Read,
                FileShare.ReadWrite | FileShare.Delete,
                4096,
                FileOptions.SequentialScan);
        }
        catch (Exception)
        {
            return null;
        }
    }

    private async Task TailAsync(Runtime runtime, FileStream stream, ManagedServiceLogStream kind, CancellationToken token)
    {
        var decoder = Encoding.UTF8.GetDecoder();
        var buffer = new byte[8192];
        var carry = string.Empty;

        try
        {
            while (!token.IsCancellationRequested)
            {
                int read;
                try
                {
                    read = stream.Read(buffer, 0, buffer.Length);
                }
                catch (Exception)
                {
                    read = 0;
                }

                if (read > 0)
                {
                    carry += Decode(decoder, buffer, read);
                    DrainLines(runtime, ref carry, kind);
                    continue;
                }

                try
                {
                    await Task.Delay(TailPollInterval, token).ConfigureAwait(false);
                }
                catch (TaskCanceledException)
                {
                    break;
                }
            }
        }
        finally
        {
            try
            {
                int read;
                while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
                {
                    carry += Decode(decoder, buffer, read);
                    DrainLines(runtime, ref carry, kind);
                }
            }
            catch (Exception)
            {
            }

            var remainder = carry.TrimEnd('\r', '\n');
            if (remainder.Length > 0) RaiseOutput(runtime.ServiceId, kind, remainder);
            try
            {
                stream.Dispose();
            }
            catch (Exception)
            {
            }
        }
    }

    private static string Decode(Decoder decoder, byte[] buffer, int count)
    {
        var chars = new char[decoder.GetCharCount(buffer, 0, count)];
        decoder.GetChars(buffer, 0, count, chars, 0);
        return new string(chars);
    }

    private void DrainLines(Runtime runtime, ref string carry, ManagedServiceLogStream kind)
    {
        int index;
        while ((index = carry.IndexOf('\n')) >= 0)
        {
            var line = carry[..index].TrimEnd('\r');
            carry = carry[(index + 1)..];
            RaiseOutput(runtime.ServiceId, kind, line);
        }
    }

    private void RaiseOutput(Guid serviceId, ManagedServiceLogStream kind, string line)
    {
        if (line.Length == 0) return;
        Output?.Invoke(this, new ManagedServiceOutputEventArgs(serviceId, kind, line));
    }

    private void RemoveRuntime(Guid serviceId, Runtime runtime)
    {
        lock (_gate)
        {
            if (!_runtimes.TryGetValue(serviceId, out var current) || !ReferenceEquals(current, runtime)) return;
            _runtimes.Remove(serviceId);
        }

        runtime.Dispose();
    }

    private sealed class Runtime : IDisposable
    {
        private int _disposed;

        public Runtime(Guid serviceId, int rootPid, IntPtr processHandle, IntPtr jobHandle)
        {
            ServiceId = serviceId;
            RootPid = rootPid;
            ProcessHandle = processHandle;
            JobHandle = jobHandle;
        }

        public Guid ServiceId { get; }

        public int RootPid { get; }

        public IntPtr ProcessHandle { get; }

        public IntPtr JobHandle { get; }

        public FileStream? StdoutStream { get; set; }

        public FileStream? StderrStream { get; set; }

        public Task? StdoutTask { get; set; }

        public Task? StderrTask { get; set; }

        public CancellationTokenSource TailToken { get; } = new();

        public void Dispose()
        {
            if (Interlocked.Exchange(ref _disposed, 1) == 1) return;

            try
            {
                TailToken.Cancel();
            }
            catch (Exception)
            {
            }

            ManagedServiceRuntimeLauncher.CloseHandleQuietly(JobHandle);
            ManagedServiceRuntimeLauncher.CloseHandleQuietly(ProcessHandle);
        }
    }
}
