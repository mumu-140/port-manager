namespace PortKiller.Services;

/// <summary>Result of a read-only dependency probe.</summary>
public enum DependencyProbeState
{
    Available,
    NotInstalled,
}

/// <summary>
/// Read-only binary discovery, generalized from the cloudflared probe:
/// known paths first, then a PATH walk. Results are cached; <see cref="Recheck"/>
/// invalidates. Strictly File.Exists + PATH walking — never executes the
/// binary for detection, never writes anything, never hits the network.
/// Runs on demand (preset picker / preset form), never at app launch.
/// Mirrors macOS PathDependencyProbe.
/// </summary>
public sealed class PathDependencyProbe
{
    private readonly Func<string, bool> _fileExists;
    private readonly Func<string, IReadOnlyList<string>> _pathEntries;

    private readonly Dictionary<string, (DependencyProbeState State, string Path)> _cache = new();

    /// <summary>Production probe: File.Exists + PATH from the environment.</summary>
    public PathDependencyProbe()
        : this(
            path => File.Exists(path),
            () => (Environment.GetEnvironmentVariable("PATH") ?? string.Empty)
                .Split(";", StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
    {
    }

    /// <summary>Test probe: inject existence and PATH layout.</summary>
    public PathDependencyProbe(Func<string, bool> fileExists, Func<string, IReadOnlyList<string>> pathEntries)
    {
        _fileExists = fileExists;
        _pathEntries = pathEntries;
    }

    /// <summary>Cached probe; returns the resolved path when available.</summary>
    public (DependencyProbeState State, string Path) Probe(DependencyRequirement requirement)
    {
        if (_cache.TryGetValue(requirement.BinaryName, out var cached))
        {
            return cached;
        }
        var fresh = ProbeFresh(requirement);
        _cache[requirement.BinaryName] = fresh;
        return fresh;
    }

    /// <summary>Drops the cache; next probe runs again.</summary>
    public void Recheck() => _cache.Clear();

    private (DependencyProbeState, string) ProbeFresh(DependencyRequirement requirement)
    {
        var exeName = requirement.BinaryName + ".exe";

        // 1. Known absolute paths (System32 ssh first, scoop shims for dufs).
        foreach (var path in requirement.KnownPaths)
        {
            if (_fileExists(path) && !IsWindowsAppsStub(path))
            {
                return (DependencyProbeState.Available, path);
            }
        }

        // 2. PATH walk (where.exe equivalent, no subprocess).
        foreach (var dir in _pathEntries())
        {
            var candidate = Path.Combine(dir, exeName);
            if (_fileExists(candidate) && !IsWindowsAppsStub(candidate))
            {
                return (DependencyProbeState.Available, candidate);
            }
        }

        return (DependencyProbeState.NotInstalled, string.Empty);
    }

    /// <summary>
    /// The Microsoft Store app-execution aliases live under
    /// AppData\Local\Microsoft\WindowsApps and open the Store
    /// instead of running when the app is not installed. They are never
    /// reported as available. Detection is path-based and read-only.
    /// </summary>
    private static bool IsWindowsAppsStub(string path)
    {
        return path.Contains("Microsoft\\WindowsApps", StringComparison.OrdinalIgnoreCase);
    }
}
