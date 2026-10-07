using PortKiller.Services;
using Xunit;

namespace PortKiller.Tests;

/// <summary>
/// Covers the bulk command-line lookup that replaced one WMI query per process.
/// </summary>
public class ProcessCommandLineProviderTests
{
    [Fact]
    public void SnapshotCoversEveryRunningProcess()
    {
        var provider = new ProcessCommandLineProvider();

        var snapshot = provider.Snapshot();

        Assert.True(provider.LastSnapshotCount > 0, "the bulk WMI read should return running processes");
        Assert.True(snapshot.ContainsKey(Environment.ProcessId));
    }

    [Fact]
    public void GetCommandLineReturnsTheCurrentProcessCommandLine()
    {
        var provider = new ProcessCommandLineProvider();

        var commandLine = provider.GetCommandLine(Environment.ProcessId);

        Assert.False(string.IsNullOrWhiteSpace(commandLine));
    }

    [Fact]
    public void GetCommandLineRejectsUnknownProcessIds()
    {
        var provider = new ProcessCommandLineProvider();

        Assert.Null(provider.GetCommandLine(0));
        Assert.Null(provider.GetCommandLine(-1));
        Assert.Null(provider.GetCommandLine(int.MaxValue));
    }

    [Fact]
    public void RepeatedReadsReuseOneBulkSnapshot()
    {
        var provider = new ProcessCommandLineProvider(TimeSpan.FromMinutes(1));

        var first = provider.Snapshot();
        var second = provider.Snapshot();

        Assert.NotEmpty(first);
        Assert.Same(first, second);
    }

    [Fact]
    public void InvalidateForcesAFreshBulkSnapshot()
    {
        var provider = new ProcessCommandLineProvider(TimeSpan.FromMinutes(1));
        var first = provider.Snapshot();

        provider.Invalidate();
        var second = provider.Snapshot();

        Assert.NotEmpty(second);
        Assert.NotSame(first, second);
    }

    [Fact]
    public void ExpiredSnapshotIsRefreshed()
    {
        var provider = new ProcessCommandLineProvider(TimeSpan.Zero);

        var first = provider.Snapshot();
        var second = provider.Snapshot();

        Assert.NotEmpty(second);
        Assert.NotSame(first, second);
    }
}
