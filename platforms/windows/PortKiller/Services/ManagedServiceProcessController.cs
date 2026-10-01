using System.IO;
using System.Text;
using PortKiller.Models;

namespace PortKiller.Services;

/// <summary>Launch seam matching <see cref="ManagedServiceRuntimeLauncher.Launch"/>.</summary>
internal delegate int ManagedServiceLaunch(
    string command,
    string? workingDirectory,
    Guid serviceId,
    string stdoutPath,
    string stderrPath,
    out IntPtr processHandle,
    out IntPtr jobHandle);

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
    private readonly HashSet<Guid> _launching = new();
    private readonly ManagedServiceLaunch _launch;

    public ManagedServiceProcessController()
        : this(ManagedServiceRuntimeLauncher.Launch)
    {
    }

    /// <summary>Test seam: observe or replace native process creation.</summary>
    internal ManagedServiceProcessController(ManagedServiceLaunch launch)
    {
        _launch = launch;
    }

    public event EventHandler<ManagedServiceOutputEventArgs>? Output;

    public Task<int> StartAsync(ManagedServiceConfig config, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        // Reserve the id before any side effect. A service that is tracked or
        // mid-launch is rejected: no log truncation, no second child, and a
        // tracked runtime is never replaced.
        lock (_gate)
        {
            if (_runtimes.ContainsKey(config.Id) || !_launching.Add(config.Id))
            {
                throw new InvalidOperationException($"Service {config.Id} already has an owned runtime.");
            }
        }

        try
        {
            var command = ManagedServiceCommandRenderer.Render(config.StartCommand, config.Port);
            ManagedServiceRuntimeLogStore.Prepare(config.Id, out var stdoutPath, out var stderrPath);

            int pid;
            IntPtr processHandle;
            IntPtr jobHandle;
            try
            {
                pid = _launch(
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

            // Every owned runtime is contained by a job object. A launch that
            // returns without one is torn down and never tracked.
            if (jobHandle == IntPtr.Zero)
            {
                ManagedServiceRuntimeLauncher.TerminateTree(IntPtr.Zero, processHandle);
                ManagedServiceRuntimeLauncher.CloseHandleQuietly(processHandle);
                throw new InvalidOperationException("Managed service launched without a job object.");
            }

            var runtime = new Runtime(config.Id, pid, processHandle, jobHandle);
            lock (_gate)
            {
                _runtimes[config.Id] = runtime;
            }

            StartTailers(runtime, stdoutPath, stderrPath);
            return Task.FromResult(pid);
        }
        finally
        {
            lock (_gate)
            {
                _launching.Remove(config.Id);
            }
        }
    }

    public async Task StopAsync(Guid serviceId, CancellationToken cancellationToken = default)
    {
        // Detaching is atomic: exactly one caller can ever take a given runtime,
        // so a concurrent stop or the dead-runtime reaper can never signal the
        // same tree twice nor touch a handle after it has been disposed.
        var runtime = DetachRuntime(serviceId);
        if (runtime is null) return;

        await TerminateAsync(runtime).ConfigureAwait(false);
    }

    public bool IsRunning(Guid serviceId)
    {
        Runtime? runtime;
        lock (_gate)
        {
            if (!_runtimes.TryGetValue(serviceId, out runtime)) return false;

            // Probe while the runtime is still tracked: a detached runtime is
            // owned by its detacher and disposed there, so this must never
            // touch a handle that another thread has already closed.
            if (ManagedServiceRuntimeLauncher.IsAlive(runtime.ProcessHandle)) return true;
        }

        // The root process exited. Reap the tracking entry; the identity check
        // stops a runtime installed by a concurrent start from being removed.
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

    /// <summary>
    /// Atomically removes and returns the runtime tracked for
    /// <paramref name="serviceId"/>, or null when this instance tracks none.
    /// Exactly one caller can detach a given runtime; that is what keeps
    /// "only ever signal a runtime this instance launched" true when stop,
    /// reaping and start overlap.
    /// </summary>
    private Runtime? DetachRuntime(Guid serviceId)
    {
        lock (_gate)
        {
            if (!_runtimes.TryGetValue(serviceId, out var runtime)) return null;
            _runtimes.Remove(serviceId);
            return runtime;
        }
    }

    /// <summary>Terminates an owned tree and releases the runtime's handles.</summary>
    private static async Task TerminateAsync(Runtime runtime)
    {
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
        finally
        {
            runtime.Dispose();
        }
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
