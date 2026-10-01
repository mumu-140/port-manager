namespace PortKiller.Services;

/// <summary>
/// Coordinates the single shared port scan. The services panel reuses this
/// path so a normal refresh reconciles managed services without a second
/// independent polling loop (design notes, section 6.4).
/// </summary>
public interface IPortScanCoordinator
{
    Task RefreshPortsAsync();
}
