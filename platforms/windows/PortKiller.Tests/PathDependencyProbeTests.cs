using System.IO;

using PortKiller.Services;
using Xunit;

namespace PortKiller.Tests;

/// <summary>
/// Pure probe tests with injected filesystem state. No network, no
/// subprocess, no shell. Mirrors macOS PathDependencyProbeTests.
/// </summary>
public sealed class PathDependencyProbeTests
{
    private static PathDependencyProbe Probe(Dictionary<string, bool> files, string path = "")
    {
        return new PathDependencyProbe(
            path => files.TryGetValue(path, out var ok) && ok,
            () => path.Length == 0 ? Array.Empty<string>() : path.Split(";"));
    }

    private static DependencyRequirement Req(string binary, params string[] knownPaths) => new()
    {
        BinaryName = binary,
        KnownPaths = knownPaths,
        NotInstalledKey = "dependency.test.notInstalled",
        InstallDocumentsURL = "https://example.com",
    };

    // State mapping

    [Fact]
    public void Known_path_hit_reports_available()
    {
        var probe = Probe(new Dictionary<string, bool> { ["C:\\Windows\\System32\\ssh.exe"] = true });
        var req = Req("ssh", "C:\\Windows\\System32\\ssh.exe");
        var (state, path) = probe.Probe(req);
        Assert.Equal(DependencyProbeState.Available, state);
        Assert.Equal("C:\\Windows\\System32\\ssh.exe", path);
    }

    [Fact]
    public void Missing_everywhere_reports_not_installed()
    {
        var probe = Probe(new Dictionary<string, bool>());
        var (state, path) = probe.Probe(Req("dufs"));
        Assert.Equal(DependencyProbeState.NotInstalled, state);
        Assert.Equal(string.Empty, path);
    }

    [Fact]
    public void Path_walk_resolves_when_known_paths_miss()
    {
        var probe = Probe(
            new Dictionary<string, bool>
            {
                ["C:\\tools\\dufs.exe"] = true,
            },
            "C:\\Windows\\System32;C:\\tools");
        var (state, path) = probe.Probe(Req("dufs"));
        Assert.Equal(DependencyProbeState.Available, state);
        Assert.Equal("C:\\tools\\dufs.exe", path);
    }

    [Fact]
    public void Known_paths_beat_the_path_walk()
    {
        var probe = Probe(
            new Dictionary<string, bool>
            {
                ["C:\\Windows\\System32\\ssh.exe"] = true,
                ["C:\\Git\\ssh.exe"] = true,
            },
            "C:\\Git");
        var (state, path) = probe.Probe(DependencyRequirement.Ssh);
        Assert.Equal(DependencyProbeState.Available, state);
        // System32 first (research rule), never the Git-bundled one.
        Assert.Equal("C:\\Windows\\System32\\ssh.exe", path);
    }

    // Caching + recheck

    [Fact]
    public void Cached_state_survives_until_recheck()
    {
        var files = new Dictionary<string, bool> { ["C:\\x\\dufs.exe"] = true };
        var probe = Probe(files, "C:\\x");
        var (firstState, firstPath) = probe.Probe(Req("dufs"));
        Assert.Equal(DependencyProbeState.Available, firstState);

        // Binary disappears: cache still reports available.
        files["C:\\x\\dufs.exe"] = false;
        var (cachedState, _) = probe.Probe(Req("dufs"));
        Assert.Equal(DependencyProbeState.Available, cachedState);

        probe.Recheck();
        var (freshState, _) = probe.Probe(Req("dufs"));
        Assert.Equal(DependencyProbeState.NotInstalled, freshState);
    }

    // WindowsApps stub rule

    [Fact]
    public void Windows_apps_store_stub_is_never_available()
    {
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var stubPath = Path.Combine(localAppData, "Microsoft", "WindowsApps", "python.exe");
        var probe = Probe(
            new Dictionary<string, bool> { [stubPath] = true },
            localAppData + "\\Microsoft\\WindowsApps");
        var (state, _) = probe.Probe(DependencyRequirement.Python);
        Assert.Equal(DependencyProbeState.NotInstalled, state);
    }

    [Fact]
    public void Real_python_on_path_beats_the_stub_rule()
    {
        var probe = Probe(
            new Dictionary<string, bool>
            {
                ["C:\\Python312\\python.exe"] = true,
            },
            "C:\\Python312");
        var (state, path) = probe.Probe(DependencyRequirement.Python);
        Assert.Equal(DependencyProbeState.Available, state);
        Assert.Equal("C:\\Python312\\python.exe", path);
    }

    // Requirement table

    [Fact]
    public void Requirement_table_covers_preset_dependencies()
    {
        Assert.Equal("python", DependencyRequirement.RequirementForPresetId("static-file-share")?.BinaryName);
        Assert.Equal("ssh", DependencyRequirement.RequirementForPresetId("ssh-local-forward")?.BinaryName);
        Assert.Equal("ssh", DependencyRequirement.RequirementForPresetId("ssh-socks5-proxy")?.BinaryName);
        Assert.Equal("ssh", DependencyRequirement.RequirementForPresetId("ssh-reverse-forward")?.BinaryName);
        Assert.Equal("dufs", DependencyRequirement.RequirementForPresetId("dufs-file-share")?.BinaryName);
        Assert.Equal("jupyter", DependencyRequirement.RequirementForPresetId("jupyter-lab")?.BinaryName);
        Assert.Null(DependencyRequirement.RequirementForPresetId("custom"));
        Assert.Null(DependencyRequirement.RequirementForPresetId("unknown"));
    }

    [Fact]
    public void Ssh_known_paths_prefer_system32()
    {
        Assert.Equal(Environment.SystemDirectory + "\\ssh.exe", DependencyRequirement.Ssh.KnownPaths[0]);
    }
}
