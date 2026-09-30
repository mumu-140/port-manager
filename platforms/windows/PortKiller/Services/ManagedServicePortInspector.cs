using PortKiller.Models;

namespace PortKiller.Services;

/// <summary>
/// Adapter over the existing scanner and killer services. Confirmed conflict
/// resolution goes through here so the manager never issues a port-based kill.
/// </summary>
public sealed class ManagedServicePortInspector : IManagedServicePortInspector
{
    private readonly PortScannerService _scanner;
    private readonly ProcessKillerService _killer;

    public ManagedServicePortInspector(PortScannerService scanner, ProcessKillerService killer)
    {
        _scanner = scanner;
        _killer = killer;
    }

    public async Task<IReadOnlyList<PortInfo>> ScanAsync(CancellationToken cancellationToken = default) =>
        await _scanner.ScanPortsAsync();

    public async Task<IReadOnlyList<PortInfo>> InspectAsync(int port, CancellationToken cancellationToken = default)
    {
        var ports = await _scanner.ScanPortsAsync();
        return ports.Where(p => p.Port == port).ToList();
    }

    public async Task<bool> IsReadyAsync(int port, CancellationToken cancellationToken = default) =>
        (await InspectAsync(port, cancellationToken)).Count > 0;

    public Task<bool> KillAsync(int pid, bool force, CancellationToken cancellationToken = default) =>
        _killer.KillProcessAsync(pid, force);
}
