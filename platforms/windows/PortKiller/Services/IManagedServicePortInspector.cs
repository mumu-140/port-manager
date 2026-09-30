using PortKiller.Models;

namespace PortKiller.Services;

public interface IManagedServicePortInspector
{
    Task<IReadOnlyList<PortInfo>> ScanAsync(CancellationToken cancellationToken = default);
    Task<IReadOnlyList<PortInfo>> InspectAsync(int port, CancellationToken cancellationToken = default);
    Task<bool> IsReadyAsync(int port, CancellationToken cancellationToken = default);
    Task<bool> KillAsync(int pid, bool force, CancellationToken cancellationToken = default);
}
