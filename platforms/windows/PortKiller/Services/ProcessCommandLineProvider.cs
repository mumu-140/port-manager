using System.Globalization;
using System.Management;

namespace PortKiller.Services;

/// <summary>
/// Resolves process command lines through WMI.
/// </summary>
/// <remarks>
/// A single <c>Win32_Process</c> query returns the command line of every process, so
/// one bulk read replaces the per-process queries a port scan would otherwise issue.
/// The snapshot is cached for a short window because a command line cannot change
/// while its process lives and callers ask for many process ids in a row.
/// </remarks>
public class ProcessCommandLineProvider
{
    /// <summary>Lifetime of a bulk snapshot when no other value is supplied.</summary>
    public static readonly TimeSpan DefaultCacheLifetime = TimeSpan.FromSeconds(2);

    private readonly TimeSpan _cacheLifetime;
    private readonly object _gate = new();
    private Dictionary<int, string?> _snapshot = new();
    private DateTime _capturedAtUtc = DateTime.MinValue;
    private bool _bulkUnavailable;

    public ProcessCommandLineProvider()
        : this(DefaultCacheLifetime)
    {
    }

    public ProcessCommandLineProvider(TimeSpan cacheLifetime)
    {
        _cacheLifetime = cacheLifetime;
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

        // The bulk read is unavailable, so answer this one request directly.
        return QuerySingle(processId);
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

            try
            {
                var fresh = QueryAll();
                _snapshot = fresh;
                LastSnapshotCount = fresh.Count;
                _bulkUnavailable = false;
                _capturedAtUtc = now;
                return fresh;
            }
            catch
            {
                // Hold the failure for one cache window so a broken WMI stack is not
                // queried again for every remaining process.
                _bulkUnavailable = true;
                _capturedAtUtc = now;
                return null;
            }
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
