using System.Collections.ObjectModel;
using PortKiller.Models;

namespace PortKiller.Services;

/// <summary>
/// The narrow slice of tunnel behaviour the managed-services ViewModel needs.
/// Keeps the ViewModel testable without constructing the real cloudflared
/// orchestration.
/// </summary>
public interface IManagedServiceTunnelHost
{
    ObservableCollection<CloudflareTunnel> Tunnels { get; }

    Task StartTunnelAsync(int port);

    Task StopTunnelAsync(CloudflareTunnel tunnel);

    void CopyUrlToClipboard(string url);

    void OpenUrlInBrowser(string url);
}
