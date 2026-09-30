using PortKiller.Models;
using PortKiller.Services;
using Xunit;

namespace PortKiller.Tests;

public sealed class ManagedServiceCommandRendererTests
{
    private sealed class ExistingDirectoryValidator : IManagedServiceDirectoryValidator
    {
        public bool IsExistingDirectory(string path) => path == "C:\\services";
    }

    private static ManagedServiceConfig Config() => new()
    {
        Name = "Demo", Port = 8080, Host = "localhost",
        WorkingDirectory = "C:\\services", StartCommand = "python -m http.server {port}"
    };

    [Fact]
    public void Render_replaces_every_port_placeholder()
    {
        Assert.Equal("serve 8080 then 8080", ManagedServiceCommandRenderer.Render("serve {port} then {port}", 8080));
    }

    [Fact]
    public void Render_preserves_command_without_placeholder()
    {
        Assert.Equal("serve", ManagedServiceCommandRenderer.Render("serve", 8080));
    }

    [Fact]
    public void UnsupportedPlaceholders_rejects_unknown_tokens()
    {
        Assert.Equal(new[] { "{host}", "{PORT}" }, ManagedServiceCommandRenderer.UnsupportedPlaceholders("run {host} {PORT}"));
    }

    [Fact]
    public void Validator_accepts_valid_profile()
    {
        Assert.Null(ManagedServiceValidator.Validate(Config(), Array.Empty<ManagedServiceConfig>(), new ExistingDirectoryValidator()));
    }

    [Fact]
    public void Validator_rejects_duplicate_name_case_insensitively()
    {
        var existing = Config();
        var candidate = Config(); candidate.Id = Guid.NewGuid(); candidate.Name = "demo"; candidate.Port = 8081;
        var error = ManagedServiceValidator.Validate(candidate, new[] { existing }, new ExistingDirectoryValidator());
        Assert.Equal(ManagedServiceValidationErrorKind.DuplicateName, error?.Kind);
    }

    [Fact]
    public void Validator_rejects_duplicate_port()
    {
        var existing = Config();
        var candidate = Config(); candidate.Id = Guid.NewGuid(); candidate.Name = "Other";
        var error = ManagedServiceValidator.Validate(candidate, new[] { existing }, new ExistingDirectoryValidator());
        Assert.Equal(ManagedServiceValidationErrorKind.DuplicatePort, error?.Kind);
    }

    [Fact]
    public void Validator_rejects_unknown_placeholder()
    {
        var candidate = Config(); candidate.StartCommand = "run {host}";
        var error = ManagedServiceValidator.Validate(candidate, Array.Empty<ManagedServiceConfig>(), new ExistingDirectoryValidator());
        Assert.Equal(ManagedServiceValidationErrorKind.UnsupportedPlaceholder, error?.Kind);
    }

    [Fact]
    public void Validator_rejects_missing_working_directory()
    {
        var candidate = Config(); candidate.WorkingDirectory = "C:\\missing";
        var error = ManagedServiceValidator.Validate(candidate, Array.Empty<ManagedServiceConfig>(), new ExistingDirectoryValidator());
        Assert.Equal(ManagedServiceValidationErrorKind.MissingWorkingDirectory, error?.Kind);
    }
}
