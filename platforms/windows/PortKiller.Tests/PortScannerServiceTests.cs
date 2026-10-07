using PortKiller.Models;
using PortKiller.Services;
using Xunit;

namespace PortKiller.Tests;

/// <summary>
/// Covers the allocation-free port parsing and the dedupe/sort pass of the scanner.
/// The Win32 table reads themselves need a real Windows TCP stack and are exercised
/// by CI build/test plus the GUI smoke runs, not by unit tests.
/// </summary>
public class PortScannerServiceTests
{
    [Theory]
    [InlineData(0x00, 0x50, 80)]
    [InlineData(0x01, 0xBB, 443)]
    [InlineData(0x1F, 0x90, 8080)]
    [InlineData(0x00, 0x00, 0)]
    [InlineData(0xFF, 0xFF, 65535)]
    public void ParseBigEndianPortReadsNetworkOrder(int high, int low, int expected)
    {
        var bytes = new byte[] { (byte)high, (byte)low };

        Assert.Equal((ushort)expected, PortScannerService.ParseBigEndianPort(bytes));
    }

    [Fact]
    public void DedupeAndSortPortsKeepsFirstOccurrenceAndSortsByPort()
    {
        var ports = new List<PortInfo>
        {
            PortInfo.Active(port: 8080, pid: 123, processName: "first", address: "127.0.0.1", user: "u", command: "c"),
            PortInfo.Active(port: 80, pid: 1, processName: "web", address: "0.0.0.0", user: "u", command: "c"),
            PortInfo.Active(port: 8080, pid: 123, processName: "duplicate", address: "::1", user: "u", command: "c2"),
            PortInfo.Active(port: 8080, pid: 456, processName: "other-pid", address: "127.0.0.1", user: "u", command: "c"),
        };

        var result = PortScannerService.DedupeAndSortPorts(ports);

        Assert.Equal(3, result.Count);
        Assert.Equal(80, result[0].Port);
        Assert.Equal(8080, result[1].Port);
        Assert.Equal(8080, result[2].Port);
        Assert.Equal("first", result[1].ProcessName);
        Assert.Equal(456, result[2].Pid);
    }

    [Fact]
    public void DedupeAndSortPortsHandlesEmptyList()
    {
        Assert.Empty(PortScannerService.DedupeAndSortPorts(new List<PortInfo>()));
    }
}
