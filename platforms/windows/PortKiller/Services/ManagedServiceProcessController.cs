using System.Diagnostics;
using PortKiller.Models;
namespace PortKiller.Services;
public sealed class ManagedServiceProcessController : IManagedServiceProcessController
{
 private readonly object _gate=new(); private readonly Dictionary<int,Process> _processes=new();
 public event EventHandler<ManagedServiceOutputEventArgs>? Output;
 public async Task<int> StartAsync(ManagedServiceConfig config,CancellationToken cancellationToken=default)
 {
  var command=ManagedServiceCommandRenderer.Render(config.StartCommand,config.Port);
  var psi=new ProcessStartInfo("cmd.exe", $"/d /s /c \"{command.Replace("\"","\\\"")}\"") { WorkingDirectory=config.WorkingDirectory,UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true };
  psi.Environment["PORT_MANAGER_SERVICE_ID"]=config.Id.ToString("D");
  var p=new Process {StartInfo=psi,EnableRaisingEvents=true};
  p.OutputDataReceived+=(s,e)=>{if(e.Data!=null) Output?.Invoke(this,new(config.Id,ManagedServiceLogStream.StandardOutput,e.Data));};
  p.ErrorDataReceived+=(s,e)=>{if(e.Data!=null) Output?.Invoke(this,new(config.Id,ManagedServiceLogStream.StandardError,e.Data));};
  if(!p.Start()) throw new InvalidOperationException("Unable to start service process."); p.BeginOutputReadLine(); p.BeginErrorReadLine(); lock(_gate)_processes[p.Id]=p; return p.Id;
 }
 public async Task StopAsync(int rootPid,CancellationToken cancellationToken=default){Process? p; lock(_gate)_processes.TryGetValue(rootPid,out p); if(p==null){try{p=Process.GetProcessById(rootPid);}catch{return;}} if(!p.HasExited){try{p.Kill(true);}catch(InvalidOperationException){}} await Task.CompletedTask; lock(_gate)_processes.Remove(rootPid); p.Dispose();}
 public bool IsRunning(int rootPid){try{using var p=Process.GetProcessById(rootPid);return !p.HasExited;}catch{return false;}}
}
