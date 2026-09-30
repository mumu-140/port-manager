using PortKiller.Models;

namespace PortKiller.Services;

/// <summary>
/// Launches, observes and terminates managed-service runtimes.
///
/// Ownership is keyed by <c>serviceId</c> for the lifetime of this controller
/// instance. Only a runtime that this instance launched and still tracks may
/// ever be signalled; a PID that merely matches a stale value is never treated
/// as owned and is never killed.
/// </summary>
public interface IManagedServiceProcessController
{
    event EventHandler<ManagedServiceOutputEventArgs>? Output;

    /// <summary>Launches the rendered command and returns the root PID.</summary>
    Task<int> StartAsync(ManagedServiceConfig config, CancellationToken cancellationToken = default);

    /// <summary>
    /// Terminates the runtime this instance tracks for <paramref name="serviceId"/>.
    /// No-ops when the service is not tracked here.
    /// </summary>
    Task StopAsync(Guid serviceId, CancellationToken cancellationToken = default);

    /// <summary>
    /// True only while this instance tracks a live runtime it launched for the
    /// service. An untracked service is never reported as running.
    /// </summary>
    bool IsRunning(Guid serviceId);

    /// <summary>Root PID of the tracked runtime, or null when untracked.</summary>
    int? RootPid(Guid serviceId);
}

public sealed class ManagedServiceOutputEventArgs : EventArgs
{
    public ManagedServiceOutputEventArgs(Guid serviceId, ManagedServiceLogStream stream, string text)
    {
        ServiceId = serviceId;
        Stream = stream;
        Text = text;
    }

    public Guid ServiceId { get; }
    public ManagedServiceLogStream Stream { get; }
    public string Text { get; }
}
