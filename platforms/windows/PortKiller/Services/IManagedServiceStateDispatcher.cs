using System.Windows.Threading;

namespace PortKiller.Services;

/// <summary>
/// Marshals managed-service state mutations onto the thread that owns the
/// WPF-bound observable objects.
///
/// Every mutation of a <see cref="Models.ManagedServiceState"/> performed by
/// <see cref="ManagedServiceManager"/> — including lifecycle continuations and
/// background output — goes through this interface. Worker threads never touch
/// bound state directly, and no code path calls
/// <c>Dispatcher.CurrentDispatcher</c> from a worker thread.
/// </summary>
public interface IManagedServiceStateDispatcher
{
    /// <summary>Runs <paramref name="action"/> on the state thread, blocking until it completes.</summary>
    void Invoke(Action action);

    /// <summary>Queues <paramref name="action"/> on the state thread without blocking.</summary>
    void Post(Action action);
}

/// <summary>Runs the action immediately on the calling thread. Used by tests and headless hosts.</summary>
public sealed class ImmediateManagedServiceStateDispatcher : IManagedServiceStateDispatcher
{
    public void Invoke(Action action) => action();

    public void Post(Action action) => action();
}

/// <summary>WPF <see cref="Dispatcher"/>-backed implementation.</summary>
public sealed class WpfManagedServiceStateDispatcher : IManagedServiceStateDispatcher
{
    private readonly Dispatcher _dispatcher;

    public WpfManagedServiceStateDispatcher(Dispatcher dispatcher) => _dispatcher = dispatcher;

    public void Invoke(Action action)
    {
        if (_dispatcher.CheckAccess()) action();
        else _dispatcher.Invoke(action);
    }

    public void Post(Action action)
    {
        if (_dispatcher.CheckAccess()) action();
        else _dispatcher.BeginInvoke(action);
    }
}
