using PortKiller.Models;
namespace PortKiller.Services;
public interface IManagedServiceStorage { IReadOnlyList<ManagedServiceConfig> Load(); void Save(IEnumerable<ManagedServiceConfig> services); }
public sealed class SettingsManagedServiceStorage : IManagedServiceStorage
{
 private readonly SettingsService _settings; public SettingsManagedServiceStorage(SettingsService settings)=>_settings=settings;
 public IReadOnlyList<ManagedServiceConfig> Load()=>_settings.GetManagedServices();
 public void Save(IEnumerable<ManagedServiceConfig> services)=>_settings.SaveManagedServices(services.ToList());
}
