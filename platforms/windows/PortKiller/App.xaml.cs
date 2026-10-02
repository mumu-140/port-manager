using System.Windows;
using Microsoft.Extensions.DependencyInjection;
using PortKiller.Services;
using PortKiller.ViewModels;

namespace PortKiller;

public partial class App : Application
{
    public static IServiceProvider Services { get; private set; } = null!;

    public App()
    {
        // WinForms TaskDialog (delete confirmations) requires visual styles to
        // be enabled once before the first dialog; WPF does not do it itself.
        System.Windows.Forms.Application.EnableVisualStyles();

        // Runtime logs are disposable artifacts of the previous session. Never
        // delete profile configuration here, and never stop a managed service:
        // services are deliberately allowed to outlive Port Manager.
        ManagedServiceRuntimeLogStore.RemoveAll();

        // Add global exception handling
        this.DispatcherUnhandledException += (s, e) =>
        {
            System.Diagnostics.Debug.WriteLine($"Unhandled exception: {e.Exception.Message}");
            System.Diagnostics.Debug.WriteLine($"Stack trace: {e.Exception.StackTrace}");
            MessageBox.Show($"An error occurred: {e.Exception.Message}\n\nStack trace:\n{e.Exception.StackTrace}",
                "Error", MessageBoxButton.OK, MessageBoxImage.Error);
            e.Handled = true;
        };

        // Setup dependency injection
        var services = new ServiceCollection();
        ConfigureServices(services);
        Services = services.BuildServiceProvider();
    }

    private void ConfigureServices(IServiceCollection services)
    {
        // Services
        services.AddSingleton<PortScannerService>();
        services.AddSingleton<ProcessKillerService>();
        services.AddSingleton<SettingsService>();
        services.AddSingleton<NotificationService>();
        services.AddSingleton<TunnelService>();
        services.AddSingleton<IManagedServiceProcessController, ManagedServiceProcessController>();
        services.AddSingleton<IManagedServicePortInspector, ManagedServicePortInspector>();
        services.AddSingleton<IManagedServiceStorage, SettingsManagedServiceStorage>();
        services.AddSingleton<IManagedServiceDirectoryValidator, FileSystemManagedServiceDirectoryValidator>();
        services.AddSingleton<IManagedServiceTunnelCoordinator, TunnelViewModelCoordinator>();
        services.AddSingleton<IManagedServiceStateDispatcher>(
            new WpfManagedServiceStateDispatcher(System.Windows.Threading.Dispatcher.CurrentDispatcher));
        services.AddSingleton<ManagedServiceManager>();

        // ViewModels
        services.AddSingleton<MainViewModel>(sp => new MainViewModel(
            sp.GetRequiredService<PortScannerService>(),
            sp.GetRequiredService<ProcessKillerService>(),
            sp.GetRequiredService<SettingsService>(),
            NotificationService.Instance,
            System.Windows.Threading.Dispatcher.CurrentDispatcher,
            sp.GetRequiredService<ManagedServiceManager>()
        ));
        services.AddSingleton<IPortScanCoordinator>(sp => sp.GetRequiredService<MainViewModel>());
        services.AddSingleton<TunnelViewModel>(sp => new TunnelViewModel(
            sp.GetRequiredService<TunnelService>(),
            NotificationService.Instance,
            sp.GetRequiredService<SettingsService>()
        ));
        services.AddSingleton<ManagedServicesViewModel>(sp => new ManagedServicesViewModel(
            sp.GetRequiredService<ManagedServiceManager>(),
            sp.GetRequiredService<TunnelViewModel>(),
            sp.GetRequiredService<IPortScanCoordinator>()
        ));
    }
}
