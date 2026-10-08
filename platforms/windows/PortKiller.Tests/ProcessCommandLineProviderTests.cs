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

    [Fact]
    public void SnapshotGivesUpWhenTheWmiReadNeverAnswers()
    {
        using var release = new ManualResetEventSlim(false);
        var provider = new ProcessCommandLineProvider(
            TimeSpan.FromMinutes(1),
            TimeSpan.FromMilliseconds(150),
            () =>
            {
                release.Wait(TimeSpan.FromSeconds(30));
                return new Dictionary<int, string?> { [Environment.ProcessId] = "wedged" };
            },
            _ => null);

        var startedAt = Environment.TickCount64;
        var snapshot = provider.Snapshot();
        var elapsed = Environment.TickCount64 - startedAt;

        Assert.Empty(snapshot);
        Assert.True(elapsed < 5_000, $"the caller must not wait for a wedged read (waited {elapsed} ms)");
        release.Set();
    }

    [Fact]
    public void AWedgedReadIsNotRetriedForEveryRequest()
    {
        var reads = 0;
        using var release = new ManualResetEventSlim(false);
        var provider = new ProcessCommandLineProvider(
            TimeSpan.FromMinutes(1),
            TimeSpan.FromMilliseconds(150),
            () =>
            {
                Interlocked.Increment(ref reads);
                release.Wait(TimeSpan.FromSeconds(30));
                return new Dictionary<int, string?>();
            },
            _ =>
            {
                Interlocked.Increment(ref reads);
                return null;
            });

        Assert.Empty(provider.Snapshot());
        Assert.Empty(provider.Snapshot());
        Assert.Null(provider.GetCommandLine(Environment.ProcessId));

        Assert.Equal(1, Volatile.Read(ref reads));
        release.Set();
    }

    [Fact]
    public void CommandLinesResumeAfterAWedgedReadFinishes()
    {
        var reads = 0;
        using var release = new ManualResetEventSlim(false);
        var provider = new ProcessCommandLineProvider(
            TimeSpan.Zero,
            TimeSpan.FromMilliseconds(150),
            () =>
            {
                if (Interlocked.Increment(ref reads) == 1)
                {
                    release.Wait(TimeSpan.FromSeconds(30));
                }

                return new Dictionary<int, string?> { [Environment.ProcessId] = "cmd.exe" };
            },
            _ => null);

        Assert.Empty(provider.Snapshot());

        release.Set();
        var deadline = Environment.TickCount64 + 5_000;
        IReadOnlyDictionary<int, string?> snapshot = new Dictionary<int, string?>();
        while (Environment.TickCount64 < deadline)
        {
            snapshot = provider.Snapshot();
            if (snapshot.Count > 0)
            {
                break;
            }

            Thread.Sleep(25);
        }

        Assert.NotEmpty(snapshot);
        Assert.True(provider.LastSnapshotCount > 0);
    }
}
