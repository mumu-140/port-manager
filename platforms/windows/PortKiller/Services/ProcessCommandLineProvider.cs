using System.Globalization;
using System.Management;
using System.Runtime.ExceptionServices;

namespace PortKiller.Services;

/// <summary>
/// Resolves process command lines through WMI.
/// </summary>
/// <remarks>
/// A single <c>Win32_Process</c> query returns the command line of every process, so
/// one bulk read replaces the per-process queries a port scan would otherwise issue.
/// The snapshot is cached for a short window because a command line cannot change
/// while its process lives and callers ask for many process ids in a row.
/// Every read is bounded by <see cref="DefaultQueryTimeout"/>: a wedged WMI provider
/// host never answers, and an unbounded query would stall the whole port scan behind
/// it and leave the port list empty. A read that outlives its deadline keeps the one
/// stalled slot, so later scans skip WMI instead of stacking more blocked threads.
/// </remarks>
public class ProcessCommandLineProvider
{
    /// <summary>Lifetime of a bulk snapshot when no other value is supplied.</summary>
    public static readonly TimeSpan DefaultCacheLifetime = TimeSpan.FromSeconds(2);

    /// <summary>How long a WMI read may run before the caller stops waiting for it.</summary>
    public static readonly TimeSpan DefaultQueryTimeout = TimeSpan.FromSeconds(2);

    private readonly TimeSpan _cacheLifetime;
    private readonly TimeSpan _queryTimeout;
    private readonly Func<Dictionary<int, string?>> _readAll;
    private readonly Func<int, string?> _readOne;
    private readonly object _gate = new();
    private readonly object _stallGate = new();
    private Dictionary<int, string?> _snapshot = new();
    private DateTime _capturedAtUtc = DateTime.MinValue;
    private bool _bulkUnavailable;
    private Thread? _stalledRead;

    public ProcessCommandLineProvider()
        : this(DefaultCacheLifetime, DefaultQueryTimeout)
    {
    }

    public ProcessCommandLineProvider(TimeSpan cacheLifetime)
        : this(cacheLifetime, DefaultQueryTimeout)
    {
    }

    public ProcessCommandLineProvider(TimeSpan cacheLifetime, TimeSpan queryTimeout)
        : this(cacheLifetime, queryTimeout, QueryAll, QuerySingle)
    {
    }

    internal ProcessCommandLineProvider(
        TimeSpan cacheLifetime,
        TimeSpan queryTimeout,
        Func<Dictionary<int, string?>> readAll,
        Func<int, string?> readOne)
    {
        _cacheLifetime = cacheLifetime;
        _queryTimeout = queryTimeout;
        _readAll = readAll;
        _readOne = readOne;
    }

    /// <summary>Number of processes seen by the most recent successful bulk read.</summary>
    public int LastSnapshotCount { get; private set; }

    /// <summary>
    /// Returns the command line of one process, or <see langword="null"/> when it is
    /// unknown.
    /// </summary>
    public string? GetCommandLine(int processId)
    {
        if (processId <= 0)
        {
            return null;
        }

        var snapshot = TryGetSnapshot();
        if (snapshot is not null)
        {
            return snapshot.TryGetValue(processId, out var commandLine) ? commandLine : null;
        }

        // A read is already wedged, so a per-process query would queue behind it.
        if (HasStalledRead())
        {
            return null;
        }

        // The bulk read is unavailable, so answer this one request directly.
        return RunBounded(() => _readOne(processId), out var single) ? single : null;
    }

    /// <summary>
    /// Returns the process-id to command-line map, refreshing it once the cached copy
    /// has expired. The map is empty when WMI cannot be reached.
    /// </summary>
    public IReadOnlyDictionary<int, string?> Snapshot() =>
        TryGetSnapshot() ?? new Dictionary<int, string?>();

    /// <summary>Drops the cached snapshot so the next read queries WMI again.</summary>
    public void Invalidate()
    {
        lock (_gate)
        {
            _capturedAtUtc = DateTime.MinValue;
            _bulkUnavailable = false;
        }
    }

    private Dictionary<int, string?>? TryGetSnapshot()
    {
        lock (_gate)
        {
            var now = DateTime.UtcNow;
            if (now - _capturedAtUtc < _cacheLifetime)
            {
                return _bulkUnavailable ? null : _snapshot;
            }

            // An earlier read never came back; queue nothing behind it.
            if (HasStalledRead())
            {
                _bulkUnavailable = true;
                _capturedAtUtc = now;
                return null;
            }

            try
            {
                if (!RunBounded(_readAll, out var fresh) || fresh is null)
                {
                    // Timed out or returned nothing: hold the failure for one cache
                    // window so a broken WMI stack is not queried again for every
                    // remaining process.
                    _bulkUnavailable = true;
                    _capturedAtUtc = now;
                    return null;
                }

                _snapshot = fresh;
                LastSnapshotCount = fresh.Count;
                _bulkUnavailable = false;
                _capturedAtUtc = now;
                return fresh;
            }
            catch
            {
                _bulkUnavailable = true;
                _capturedAtUtc = now;
                return null;
            }
        }
    }

    /// <summary>
    /// Runs one WMI read on a thread of its own and stops waiting once the query
    /// timeout elapses, so a provider host that never answers cannot block the caller.
    /// </summary>
    private bool RunBounded<T>(Func<T> read, out T? value)
    {
        value = default;

        T? result = default;
        ExceptionDispatchInfo? failure = null;
        using var completed = new ManualResetEventSlim(false);
        var worker = new Thread(() =>
        {
            try
            {
                result = read();
            }
            catch (Exception ex)
            {
                failure = ExceptionDispatchInfo.Capture(ex);
            }
            finally
            {
                completed.Set();
            }
        })
        {
            IsBackground = true,
            Name = "PortKiller.WmiRead"
        };

        worker.Start();
        if (!completed.Wait(_queryTimeout))
        {
            // The read outlived its deadline. Remember it while it is still running so
            // later callers skip WMI instead of stacking one blocked thread per scan;
            // the slot frees itself once the read finally returns.
            lock (_stallGate)
            {
                if (worker.IsAlive)
                {
                    _stalledRead = worker;
                }
            }

            return false;
        }

        failure?.Throw();
        value = result;
        return true;
    }

    /// <summary>
    /// True while a read that already outlived its deadline is still running. The slot
    /// clears itself as soon as that read finishes.
    /// </summary>
    private bool HasStalledRead()
    {
        lock (_stallGate)
        {
            var stalled = _stalledRead;
            if (stalled is null)
            {
                return false;
            }

            if (stalled.IsAlive)
            {
                return true;
            }

            _stalledRead = null;
            return false;
        }
    }

    private static Dictionary<int, string?> QueryAll()
    {
        var snapshot = new Dictionary<int, string?>();
        using var searcher = new ManagementObjectSearcher(
            "SELECT ProcessId, CommandLine FROM Win32_Process");
        using var results = searcher.Get();
        foreach (ManagementObject entry in results)
        {
            using (entry)
            {
                if (entry["ProcessId"] is not { } rawId)
                {
                    continue;
                }

                snapshot[Convert.ToInt32(rawId, CultureInfo.InvariantCulture)] =
                    entry["CommandLine"]?.ToString();
            }
        }

        return snapshot;
    }

    private static string? QuerySingle(int processId)
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(
                $"SELECT CommandLine FROM Win32_Process WHERE ProcessId = {processId}");
            using var results = searcher.Get();
            foreach (ManagementObject entry in results)
            {
                using (entry)
                {
                    return entry["CommandLine"]?.ToString();
                }
            }
        }
        catch
        {
            // Command lines are best effort; callers fall back to the process name.
        }

        return null;
    }
}
