using PortKiller.Models;
using PortKiller.Services;
using Xunit;

namespace PortKiller.Tests;

/// <summary>
/// Pure mapping tests for M7 warnings (design section 10.2).
/// Mirrors macOS ManagedServicePresetWarningTests.
/// </summary>
public sealed class ManagedServiceExposureWarningTests
{
    private const string Home = @"C:\\Users\\tester";

    private static ManagedServiceConfig Generate(string presetId, Dictionary<string, string> overrides)
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
            Port = 5000,
            HomeDirectory = Home,
        }, values);
    }

    [Fact]
    public void Writable_dufs_shares_with_explicit_warning()
    {
        var config = Generate("dufs-file-share", new() { ["directory"] = @"C:\\public", ["mode"] = "read-write" });
        Assert.Equal("exposure.warning.dufsWritablePublic", ManagedServiceExposureWarning.MessageFor(config));
    }

    [Fact]
    public void Upload_mode_counts_as_writable()
    {
        var config = Generate("dufs-file-share", new() { ["directory"] = @"C:\\public", ["mode"] = "upload" });
        Assert.Equal("exposure.warning.dufsWritablePublic", ManagedServiceExposureWarning.MessageFor(config));
    }

    [Fact]
    public void Read_only_dufs_shares_with_no_auth_warning()
    {
        var config = Generate("dufs-file-share", new() { ["directory"] = @"C:\\public" });
        Assert.Equal("exposure.warning.dufsPublic", ManagedServiceExposureWarning.MessageFor(config));
    }

    [Fact]
    public void Jupyter_shares_with_strong_warning()
    {
        var config = Generate("jupyter-lab", new() { ["directory"] = @"C:\\notebooks" });
        Assert.Equal("exposure.warning.jupyterPublic", ManagedServiceExposureWarning.MessageFor(config));
    }

    [Fact]
    public void Custom_and_other_presets_share_without_extra_warning()
    {
        var custom = new ManagedServiceConfig
        {
            Name = "Custom",
            Port = 8080,
            Host = "localhost",
            WorkingDirectory = Home,
            StartCommand = "python3 -m http.server {port}",
        };
        Assert.Null(ManagedServiceExposureWarning.MessageFor(custom));
        var ssh = Generate("ssh-local-forward", new() { ["sshHost"] = "box.lan", ["remotePort"] = "5432" });
        Assert.Null(ManagedServiceExposureWarning.MessageFor(ssh));
    }

    [Fact]
    public void Active_warnings_suppress_gatewayports_at_default_bind()
    {
        var preset = ManagedServicePresets.PresetWithId("ssh-reverse-forward")!;
        var keys = preset.ActiveWarningKeys(preset.DefaultFieldValues(), Home);
        Assert.DoesNotContain("preset.ssh-reverse-forward.warning.gatewayports", keys);
    }

    [Fact]
    public void Active_warnings_include_gatewayports_beyond_loopback()
    {
        var preset = ManagedServicePresets.PresetWithId("ssh-reverse-forward")!;
        var values = preset.DefaultFieldValues();
        values["remoteBind"] = "0.0.0.0";
        var keys = preset.ActiveWarningKeys(values, Home);
        Assert.Contains("preset.ssh-reverse-forward.warning.gatewayports", keys);
    }

    [Fact]
    public void Home_root_directory_adds_scope_warning()
    {
        var preset = ManagedServicePresets.PresetWithId("static-file-share")!;
        var values = preset.DefaultFieldValues();
        values["directory"] = Home;
        var keys = preset.ActiveWarningKeys(values, Home);
        Assert.Contains("preset.file-share.warning.homeRoot", keys);
        var deeper = preset.DefaultFieldValues();
        deeper["directory"] = Home + @"\\Sites";
        Assert.DoesNotContain("preset.file-share.warning.homeRoot", preset.ActiveWarningKeys(deeper, Home));
    }
}
