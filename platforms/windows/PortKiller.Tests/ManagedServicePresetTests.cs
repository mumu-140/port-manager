using PortKiller.Models;
using PortKiller.Services;
using Xunit;

namespace PortKiller.Tests;

/// <summary>
/// Pure preset tests: registry integrity, charset validation, generator output
/// shape, and the constrain-and-quote rendering contract. Mirrors macOS
/// ManagedServicePresetTests. No process layer is touched.
/// </summary>
public sealed class ManagedServicePresetTests
{
    private const string Directory = @"C:\shares\docs";
    private const string Home = @"C:\Users\tester";

    private static PresetGenerationContext Context(int port = 8123) => new()
    {
        Id = Guid.NewGuid(),
        Name = "Preset Demo",
        Port = port,
        HomeDirectory = Home,
    };

    private static Dictionary<string, string> Values(ManagedServicePreset preset, Dictionary<string, string>? overrides = null)
    {
        var values = preset.DefaultFieldValues();
        if (overrides is not null)
        {
            foreach (var (key, value) in overrides)
            {
                values[key] = value;
            }
        }
        return values;
    }

    private static string GeneratedCommand(string presetId, Dictionary<string, string>? overrides = null, int port = 8123)
    {
        var preset = ManagedServicePresets.PresetWithId(presetId)!;
        var config = preset.Generate(Context(port), Values(preset, overrides));
        return config.StartCommand;
    }

    private static ManagedServicePreset Preset(string id) => ManagedServicePresets.PresetWithId(id)!;

    // Registry

    [Fact]
    public void Preset_ids_are_unique()
    {
        var ids = ManagedServicePresets.All.Select(p => p.Id).ToList();
        Assert.Equal(ids.Count, ids.Distinct().Count());
    }

    [Fact]
    public void Registry_resolves_every_preset_by_id()
    {
        foreach (var preset in ManagedServicePresets.All)
        {
            Assert.Equal(preset.Id, ManagedServicePresets.PresetWithId(preset.Id)?.Id);
        }
    }

    [Fact]
    public void Unknown_preset_id_resolves_to_null()
    {
        Assert.Null(ManagedServicePresets.PresetWithId("custom"));
        Assert.Null(ManagedServicePresets.PresetWithId("removed-preset"));
    }

    // Generators produce valid profiles

    [Fact]
    public void Static_file_share_generator_produces_valid_profile()
    {
        var config = Preset("static-file-share").Generate(Context(), Values(Preset("static-file-share"), new() { ["directory"] = Directory }));
        Assert.Equal("static-file-share", config.PresetId);
        Assert.Equal(Directory, config.WorkingDirectory);
        Assert.Equal("localhost", config.Host);
        Assert.Null(ManagedServiceValidator.Validate(config, Array.Empty<ManagedServiceConfig>(), new ExistingDirectoryStub()));
    }

    [Fact]
    public void Ssh_local_forward_generator_produces_valid_profile()
    {
        var config = Preset("ssh-local-forward").Generate(Context(15432), Values(Preset("ssh-local-forward"), new() { ["sshHost"] = "web.example.com", ["remotePort"] = "5432" }));
        Assert.Equal(15432, config.Port);
        Assert.Equal(Home, config.WorkingDirectory);
        Assert.Null(ManagedServiceValidator.Validate(config, Array.Empty<ManagedServiceConfig>(), new ExistingDirectoryStub()));
    }

    [Fact]
    public void Ssh_socks5_and_reverse_generators_produce_valid_profiles()
    {
        foreach (var id in new[] { "ssh-socks5-proxy", "ssh-reverse-forward" })
        {
            var config = Preset(id).Generate(Context(), Values(Preset(id), new() { ["sshHost"] = "box.lan", ["remotePort"] = "8080" }));
            Assert.Null(ManagedServiceValidator.Validate(config, Array.Empty<ManagedServiceConfig>(), new ExistingDirectoryStub()));
        }
    }

    [Fact]
    public void Dufs_and_jupyter_generators_produce_valid_profiles()
    {
        foreach (var id in new[] { "dufs-file-share", "jupyter-lab" })
        {
            var config = Preset(id).Generate(Context(), Values(Preset(id), new() { ["directory"] = Directory }));
            Assert.Null(ManagedServiceValidator.Validate(config, Array.Empty<ManagedServiceConfig>(), new ExistingDirectoryStub()));
        }
    }

    // Fixed invariants

    [Fact]
    public void Every_generated_command_keeps_the_port_placeholder()
    {
        foreach (var preset in ManagedServicePresets.All)
        {
            var config = preset.Generate(Context(), Values(preset));
            Assert.Contains("{port}", config.StartCommand);
        }
    }

    [Fact]
    public void Listening_presets_bind_loopback_explicitly()
    {
        Assert.Contains("--bind 127.0.0.1", GeneratedCommand("static-file-share"));
        Assert.Contains("--bind 127.0.0.1", GeneratedCommand("dufs-file-share"));
        Assert.Contains("--ip 127.0.0.1", GeneratedCommand("jupyter-lab"));
        Assert.Contains("-D 127.0.0.1:{port}", GeneratedCommand("ssh-socks5-proxy"));
    }

    [Fact]
    public void Jupyter_fixed_flags_are_present_exactly_once()
    {
        var command = GeneratedCommand("jupyter-lab", new() { ["directory"] = Directory });
        Assert.Equal(1, command.Split("--no-browser").Length - 1);
        Assert.Equal(1, command.Split("--port-retries=0").Length - 1);
    }

    [Fact]
    public void Ssh_presets_always_carry_N_and_ExitOnForwardFailure()
    {
        foreach (var id in new[] { "ssh-local-forward", "ssh-socks5-proxy", "ssh-reverse-forward" })
        {
            var command = GeneratedCommand(id);
            Assert.Contains("-N", command);
            Assert.Contains("-o ExitOnForwardFailure=yes", command);
            Assert.Contains("-o ServerAliveInterval=15", command);
            Assert.Contains("-o ServerAliveCountMax=3", command);
        }
    }

    [Fact]
    public void Ssh_local_forward_renders_forward_spec()
    {
        var command = GeneratedCommand("ssh-local-forward", new() { ["sshHost"] = "web.example.com", ["remoteHost"] = "127.0.0.1", ["remotePort"] = "5432" }, 15432);
        Assert.Contains("-L {port}:127.0.0.1:5432", command);
        Assert.EndsWith("web.example.com", command);
    }

    [Fact]
    public void Ssh_reverse_forward_renders_remote_bind_first()
    {
        var command = GeneratedCommand("ssh-reverse-forward", new() { ["sshHost"] = "box.lan", ["remoteBind"] = "127.0.0.1", ["remotePort"] = "8080" });
        Assert.Contains("-R 127.0.0.1:8080:127.0.0.1:{port}", command);
    }

    [Fact]
    public void Dufs_modes_render_permission_flags()
    {
        Assert.DoesNotContain("--allow-", GeneratedCommand("dufs-file-share", new() { ["mode"] = "read-only" }));
        Assert.Contains("--allow-upload", GeneratedCommand("dufs-file-share", new() { ["mode"] = "upload" }));
        Assert.DoesNotContain("--allow-delete", GeneratedCommand("dufs-file-share", new() { ["mode"] = "upload" }));
        var readWrite = GeneratedCommand("dufs-file-share", new() { ["mode"] = "read-write" });
        Assert.Contains("--allow-upload", readWrite);
        Assert.Contains("--allow-delete", readWrite);
    }

    [Fact]
    public void Paths_are_double_quoted_with_trailing_backslash_doubled()
    {
        var command = GeneratedCommand("static-file-share", new() { ["directory"] = @"C:\shares\docs" });
        Assert.Contains("--directory \"C:\\shares\\docs\"", command);

        var trailing = GeneratedCommand("static-file-share", new() { ["directory"] = @"C:\shares\docs\" });
        Assert.Contains("--directory \"C:\\shares\\docs\\\\\"", trailing);
    }

    // Field validation

    [Fact]
    public void Required_empty_fields_are_rejected()
    {
        var preset = Preset("static-file-share");
        Assert.Equal("directory", preset.FirstInvalidField(Values(preset, new() { ["directory"] = "  " })));
        Assert.Null(preset.FirstInvalidField(Values(preset, new() { ["directory"] = Directory })));
    }

    [Fact]
    public void Ssh_host_charset_rejects_shell_metacharacters()
    {
        var preset = Preset("ssh-local-forward");
        var field = preset.Fields.First(f => f.Id == "sshHost");
        Assert.Null(preset.ValidateField(field, "web.example.com"));
        Assert.Null(preset.ValidateField(field, "user@host:2222"));
        Assert.Equal(PresetFieldValueErrorKind.InvalidCharacters, preset.ValidateField(field, "a b"));
        Assert.Equal(PresetFieldValueErrorKind.InvalidCharacters, preset.ValidateField(field, "a;b"));
        Assert.Equal(PresetFieldValueErrorKind.InvalidCharacters, preset.ValidateField(field, "$(x)"));
        Assert.Equal(PresetFieldValueErrorKind.InvalidCharacters, preset.ValidateField(field, "it's"));
    }

    [Fact]
    public void Integer_charset_rejects_non_digits()
    {
        var preset = Preset("ssh-local-forward");
        var field = preset.Fields.First(f => f.Id == "remotePort");
        Assert.Null(preset.ValidateField(field, "5432"));
        Assert.Equal(PresetFieldValueErrorKind.NotAnInteger, preset.ValidateField(field, "5432x"));
        Assert.Equal(PresetFieldValueErrorKind.NotAnInteger, preset.ValidateField(field, "port"));
    }

    [Fact]
    public void Path_charset_rejects_quote_percent_and_newlines()
    {
        var preset = Preset("static-file-share");
        var field = preset.Fields.First(f => f.Id == "directory");
        Assert.Null(preset.ValidateField(field, @"C:\some folder"));
        Assert.Equal(PresetFieldValueErrorKind.InvalidCharacters, preset.ValidateField(field, @"C:\a""b"));
        Assert.Equal(PresetFieldValueErrorKind.InvalidCharacters, preset.ValidateField(field, @"C:a%b"));
    }

    [Fact]
    public void Extra_options_charset_rejects_quotes_dollars_and_backslashes()
    {
        var preset = Preset("ssh-local-forward");
        var field = preset.Fields.First(f => f.Id == "extraOptions");
        Assert.Null(preset.ValidateField(field, "-o Compression=yes"));
        Assert.Null(preset.ValidateField(field, "-L 80:bad"));
        Assert.Equal(PresetFieldValueErrorKind.InvalidCharacters, preset.ValidateField(field, "a'b"));
        Assert.Equal(PresetFieldValueErrorKind.InvalidCharacters, preset.ValidateField(field, "a$b"));
        Assert.Equal(PresetFieldValueErrorKind.InvalidCharacters, preset.ValidateField(field, @"a\b"));
        Assert.Equal(PresetFieldValueErrorKind.InvalidCharacters, preset.ValidateField(field, "a;b"));
    }

    [Fact]
    public void Generated_profiles_carry_preset_id()
    {
        var preset = Preset("static-file-share");
        var config = preset.Generate(Context(), Values(preset));
        Assert.Equal("static-file-share", config.PresetId);
    }

    [Fact]
    public void Preset_id_serializes_and_tolerates_absence()
    {
        var config = Preset("static-file-share").Generate(Context(), Values(Preset("static-file-share"), new() { ["directory"] = Directory }));
        var json = System.Text.Json.JsonSerializer.Serialize(config);
        Assert.Contains("\"PresetId\"", json);

        var legacy = "{\"Id\":\"00000000-0000-0000-0000-000000000001\",\"Name\":\"Legacy\",\"Port\":80,\"Host\":\"localhost\",\"WorkingDirectory\":\"C:\\\\x\",\"StartCommand\":\"serve {port}\"}";
        var decoded = System.Text.Json.JsonSerializer.Deserialize<ManagedServiceConfig>(legacy);
        Assert.NotNull(decoded);
        Assert.Null(decoded!.PresetId);
    }

    private sealed class ExistingDirectoryStub : IManagedServiceDirectoryValidator
    {
        public bool IsExistingDirectory(string path) => path is Directory or Home;
    }
}
