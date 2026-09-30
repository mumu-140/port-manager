using PortKiller.Models;
namespace PortKiller.Services;
public sealed class ManagedServiceManager
{
 public const int MaxOutputLines=200; public static readonly TimeSpan ReadinessTimeout=TimeSpan.FromSeconds(20);
 private readonly IManagedServiceStorage _storage; private readonly IManagedServiceProcessController _processes; private readonly IManagedServicePortInspector _ports;
 private readonly Dictionary<Guid,ManagedServiceState> _states=new();
 public ManagedServiceManager(IManagedServiceStorage storage,IManagedServiceProcessController processes,IManagedServicePortInspector ports){_storage=storage;_processes=processes;_ports=ports;_processes.Output+=OnOutput;}
 public IReadOnlyList<ManagedServiceState> Load(){_states.Clear();foreach(var c in _storage.Load())_states[c.Id]=new ManagedServiceState(c);return _states.Values.ToList();}
 public ManagedServiceState Add(ManagedServiceConfig c){if(c.Id==Guid.Empty)c.Id=Guid.NewGuid();var s=new ManagedServiceState(c);_states[c.Id]=s;Persist();return s;}
 public bool Remove(Guid id){if(!_states.TryGetValue(id,out var s)||s.IsRunning)return false;_states.Remove(id);Persist();return true;}
 public async Task<bool> StartAsync(Guid id,CancellationToken ct=default){if(!_states.TryGetValue(id,out var s))return false;s.Status=ManagedServiceStatus.Starting;s.LastError=null;try{s.RootPid=await _processes.StartAsync(s.Config,ct);var until=DateTime.UtcNow+ReadinessTimeout;while(DateTime.UtcNow<until&&!ct.IsCancellationRequested){if(await _ports.IsReadyAsync(s.Config.Port,ct)){s.Status=ManagedServiceStatus.Running;s.StartedAt=DateTime.Now;return true;}await Task.Delay(250,ct);}s.LastError="Service did not listen on configured port.";await StopAsync(id,ct);s.Status=ManagedServiceStatus.Failed;return false;}catch(Exception ex){s.LastError=ex.Message;s.Status=ManagedServiceStatus.Failed;return false;}}
 public async Task<bool> StopAsync(Guid id,CancellationToken ct=default){if(!_states.TryGetValue(id,out var s))return false;if(!s.IsOwned){s.Status=ManagedServiceStatus.Stopped;return true;}s.Status=ManagedServiceStatus.Stopping;await _processes.StopAsync(s.RootPid!.Value,ct);s.ClearRuntime();s.Status=ManagedServiceStatus.Stopped;return true;}
 public Task<bool> RestartAsync(Guid id,CancellationToken ct=default)=>RestartCore(id,ct); private async Task<bool> RestartCore(Guid id,CancellationToken ct){await StopAsync(id,ct);return await StartAsync(id,ct);}
 public bool Update(Guid id,ManagedServiceConfig c){if(!_states.TryGetValue(id,out var s)||s.IsRunning)return false;c.Id=id;s.Config=c;Persist();return true;}
 private void Persist()=>_storage.Save(_states.Values.Select(x=>x.Config)); private void OnOutput(object? sender,ManagedServiceOutputEventArgs e){if(_states.TryGetValue(e.ServiceId,out var s))s.AppendOutput(e.Text,e.Stream);}
}
