using PortKiller.Models;
using PortKiller.ViewModels;

namespace PortKiller.Services;

/// <summary>
/// Coarse resource a managed service can attach to (Cloudflare Quick Tunnel).
/// Mirrors the macOS ManagedServiceTunnelCoordinating protocol: stopping a
/// service releases the public endpoint so no stale tunnel is left active.
/// </summary>
public interface IManagedServiceTunnelCoordinator
{
    Task StopTunnelForPortAsync(int port, CancellationToken cancellationToken = default);
}

/// <summary>Routes tunnel coordination through the existing TunnelViewModel.</summary>
public sealed class TunnelViewModelCoordinator : IManagedServiceTunnelCoordinator
{
    private readonly TunnelViewModel _tunnels;

    public TunnelViewModelCoordinator(TunnelViewModel tunnels) => _tunnels = tunnels;

    public async Task StopTunnelForPortAsync(int port, CancellationToken cancellationToken = default)
    {
        var tunnel = _tunnels.Tunnels.FirstOrDefault(t => t.Port == port);
        if (tunnel is not null)
        {
            await _tunnels.StopTunnelAsync(tunnel).ConfigureAwait(true);
        }
    }
}
