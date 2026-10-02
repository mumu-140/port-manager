using PortKiller.Models;
using PortKiller.Services;
using Xunit;

namespace PortKiller.Tests;

/// <summary>
/// Deterministic extraction tests for re-opening preset profiles.
/// Mirrors macOS ManagedServicePresetEditorTests extractor coverage.
/// </summary>
public sealed class ManagedServicePresetExtractorTests
{
    private const string Home = @"C:\\Users\\tester";

    private static ManagedServiceConfig Generated(string presetId, Dictionary<string, string> overrides, int port = 8123)
    {
        var preset = ManagedServicePresets.PresetWithId(presetId)!;
        var values = preset.DefaultFieldValues();
        foreach (var (key, value) in overrides)
        {
            values[key] = value;
        }
        return preset.Generate(new PresetGenerationContext
        {
            Id = Guid.NewGuid(),
            Name = "Demo",
            Port = port,
            HomeDirectory = Home,
        }, values);
    }

    [Fact]
    public void Directory_presets_extract_working_directory()
    {
        var preset = ManagedServicePresets.PresetWithId("static-file-share")!;
        var config = Generated("static-file-share", new() { ["directory"] = @"C:\\shares\\docs" });
        var values = ManagedServicePresetFieldExtractor.ExtractFieldValues(preset, config, Home);
        Assert.Equal(@"C:\\shares\\docs", values["directory"]);
    }

    [Fact]
    public void Dufs_mode_is_extracted_from_flags()
    {
        var preset = ManagedServicePresets.PresetWithId("dufs-file-share")!;
        var config = Generated("dufs-file-share", new() { ["mode"] = "read-write", ["directory"] = @"C:\\srv" });
        var values = ManagedServicePresetFieldExtractor.ExtractFieldValues(preset, config, Home);
        Assert.Equal("read-write", values["mode"]);
        Assert.Equal(@"C:\\srv", values["directory"]);
    }

    [Fact]
    public void Ssh_local_forward_round_trips()
    {
        var preset = ManagedServicePresets.PresetWithId("ssh-local-forward")!;
        var config = Generated("ssh-local-forward", new()
        {
            ["sshHost"] = "web.example.com",
            ["remotePort"] = "5432",
            ["extraOptions"] = "-o Compression=yes",
        }, 15432);
        var values = ManagedServicePresetFieldExtractor.ExtractFieldValues(preset, config, Home);
        Assert.Equal("web.example.com", values["sshHost"]);
        Assert.Equal("127.0.0.1", values["remoteHost"]);
        Assert.Equal("5432", values["remotePort"]);
        Assert.Equal("15", values["keepaliveInterval"]);
        Assert.Equal("3", values["keepaliveCount"]);
        Assert.Equal("-o Compression=yes", values["extraOptions"]);
    }

    [Fact]
    public void Ssh_reverse_forward_round_trips_remote_bind()
    {
        var preset = ManagedServicePresets.PresetWithId("ssh-reverse-forward")!;
        var config = Generated("ssh-reverse-forward", new()
        {
            ["sshHost"] = "box.lan",
            ["remoteBind"] = "127.0.0.1",
            ["remotePort"] = "8080",
        });
        var values = ManagedServicePresetFieldExtractor.ExtractFieldValues(preset, config, Home);
        Assert.Equal("box.lan", values["sshHost"]);
        Assert.Equal("127.0.0.1", values["remoteBind"]);
        Assert.Equal("8080", values["remotePort"]);
    }

    [Fact]
    public void Socks5_proxy_extracts_host_and_keepalives()
    {
        var preset = ManagedServicePresets.PresetWithId("ssh-socks5-proxy")!;
        var config = Generated("ssh-socks5-proxy", new() { ["sshHost"] = "box.lan" });
        var values = ManagedServicePresetFieldExtractor.ExtractFieldValues(preset, config, Home);
        Assert.Equal("box.lan", values["sshHost"]);
        Assert.Equal("15", values["keepaliveInterval"]);
    }

    [Fact]
    public void Garbage_commands_keep_defaults()
    {
        var preset = ManagedServicePresets.PresetWithId("ssh-local-forward")!;
        var config = new ManagedServiceConfig
        {
            Id = Guid.NewGuid(),
            Name = "X",
            Port = 1,
            Host = "localhost",
            WorkingDirectory = Home,
            StartCommand = "not a generated command",
            PresetId = "ssh-local-forward",
        };
        var values = ManagedServicePresetFieldExtractor.ExtractFieldValues(preset, config, Home);
        Assert.Equal("", values["sshHost"]);
        Assert.Equal("127.0.0.1", values["remoteHost"]);
    }
}
