using PortKiller.Models;
namespace PortKiller.Services;
public interface IManagedServiceProcessController
{
 event EventHandler<ManagedServiceOutputEventArgs>? Output;
 Task<int> StartAsync(ManagedServiceConfig config, CancellationToken cancellationToken = default);
 Task StopAsync(int rootPid, CancellationToken cancellationToken = default);
 bool IsRunning(int rootPid);
}
public sealed class ManagedServiceOutputEventArgs : EventArgs
{
 public ManagedServiceOutputEventArgs(Guid serviceId, ManagedServiceLogStream stream, string text){ServiceId=serviceId;Stream=stream;Text=text;}
 public Guid ServiceId {get;} public ManagedServiceLogStream Stream {get;} public string Text {get;}
}
