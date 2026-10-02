namespace PortKiller.Services;

/// <summary>Semantic inputs for the delete confirmation (design section 8.1).</summary>
public sealed class ManagedServiceDeleteContext
{
    public string Name { get; init; } = string.Empty;
    public int Port { get; init; }
    /// <summary>Owned runtime active right now (Running with a root PID).</summary>
    public bool IsOwnedRunning { get; init; }
    /// <summary>Status == Conflict.</summary>
    public bool IsConflict { get; init; }
    /// <summary>An owned Quick Tunnel is attached to this port right now.</summary>
    public bool HasQuickTunnel { get; init; }
}

/// <summary>
/// Pure semantic mapping: delete state -> (message, destructive button text).
/// Mirrors macOS ManagedServiceDeleteConfirmation. The wording matches actual
/// behavior exactly: running = the owned service IS stopped first; conflict =
/// the external occupant is NEVER terminated; +tunnel names the temporary
/// tunnel (existing auto-stop behavior). Behavior never changes here —
/// copy and button labels only. English copy; the app has no localization
/// layer yet (same convention as the rest of the Windows UI).
/// </summary>
public static class ManagedServiceDeleteCopy
{
    public sealed class Copy
    {
        public string Message { get; init; } = string.Empty;
        public string ButtonText { get; init; } = string.Empty;
    }

    public static Copy For(ManagedServiceDeleteContext context)
    {
        if (context.IsConflict)
        {
            return new Copy
            {
                Message = "Delete configuration \""\" + context.Name + "\"? The external process using port "
                    + context.Port.ToString(System.Globalization.CultureInfo.InvariantCulture)
                    + " will not be terminated.",
                ButtonText = "Delete Configuration Only",
            };
        }
        if (context.IsOwnedRunning)
        {
            var message = context.HasQuickTunnel
                ? "Stop and delete \""\" + context.Name + "\"? The owned service and its temporary public tunnel will both be stopped."
                : "Stop and delete \""\" + context.Name + "\"? The owned service will be stopped first.";
            return new Copy
            {
                Message = message,
                ButtonText = "Stop & Delete",
            };
        }
        return new Copy
        {
            Message = "Delete service \""\" + context.Name + "\"? This removes the saved configuration.",
            ButtonText = "Delete",
        };
    }
}
