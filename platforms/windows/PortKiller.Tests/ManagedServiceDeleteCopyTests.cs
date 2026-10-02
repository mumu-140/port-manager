using PortKiller.Services;
using Xunit;

namespace PortKiller.Tests;

/// <summary>
/// Pure mapping tests for the delete confirmation (design section 8.1).
/// Mirrors macOS ManagedServiceDeleteConfirmationTests. Behavior tests are
/// unchanged; this covers copy and button text only.
/// </summary>
public sealed class ManagedServiceDeleteCopyTests
{
    private static ManagedServiceDeleteContext Context(
        bool isOwnedRunning = false, bool isConflict = false, bool hasQuickTunnel = false) => new()
    {
        Name = "Web",
        Port = 8080,
        IsOwnedRunning = isOwnedRunning,
        IsConflict = isConflict,
        HasQuickTunnel = hasQuickTunnel,
    };

    [Fact]
    public void Stopped_service_warns_only_about_saved_configuration()
    {
        var copy = ManagedServiceDeleteCopy.For(Context());
        Assert.Contains("Delete service", copy.Message);
        Assert.Contains("Web", copy.Message);
        Assert.Contains("saved configuration", copy.Message);
        Assert.Equal("Delete", copy.ButtonText);
    }

    [Fact]
    public void Owned_running_service_says_stop_and_delete()
    {
        var copy = ManagedServiceDeleteCopy.For(Context(isOwnedRunning: true));
        Assert.Contains("Stop and delete", copy.Message);
        Assert.Contains("Web", copy.Message);
        Assert.Equal("Stop & Delete", copy.ButtonText);
    }

    [Fact]
    public void Owned_running_with_quick_tunnel_names_the_tunnel()
    {
        var copy = ManagedServiceDeleteCopy.For(Context(isOwnedRunning: true, hasQuickTunnel: true));
        Assert.Contains("temporary public tunnel", copy.Message);
        Assert.Equal("Stop & Delete", copy.ButtonText);
    }

    [Fact]
    public void Conflict_says_configuration_only_and_names_the_port()
    {
        var copy = ManagedServiceDeleteCopy.For(Context(isConflict: true));
        Assert.Contains("Delete configuration", copy.Message);
        Assert.Contains("8080", copy.Message);
        Assert.Contains("will not be terminated", copy.Message);
        Assert.Equal("Delete Configuration Only", copy.ButtonText);
    }

    [Fact]
    public void Conflict_wins_over_running_and_tunnel()
    {
        var copy = ManagedServiceDeleteCopy.For(Context(isConflict: true, hasQuickTunnel: true));
        Assert.Contains("Delete configuration", copy.Message);
    }
}
