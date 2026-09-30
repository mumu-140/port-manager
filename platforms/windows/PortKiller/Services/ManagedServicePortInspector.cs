using PortKiller.Models;
namespace PortKiller.Services;
public sealed class ManagedServicePortInspector : IManagedServicePortInspector
{
 private readonly PortScannerService _scanner; public ManagedServicePortInspector(PortScannerService scanner)=>_scanner=scanner;
 public async Task<IReadOnlyList<PortInfo>> InspectAsync(int port,CancellationToken cancellationToken=default)=>(await _scanner.ScanPortsAsync()).Where(x=>x.Port==port).ToList();
 public async Task<bool> IsReadyAsync(int port,CancellationToken cancellationToken=default)=>(await InspectAsync(port,cancellationToken)).Count>0;
}
