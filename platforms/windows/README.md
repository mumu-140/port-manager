# PortKiller for Windows

> Part of **[Port Manager](https://github.com/mumu-140/port-manager)** (`mumu-140/port-manager`) — an independently maintained cross-platform port-management project. The desktop app keeps the **PortKiller** product/executable name for compatibility.
>
> **Fork provenance:** this code began as a fork of [productdevbook/port-killer](https://github.com/productdevbook/port-killer); upstream authorship and the MIT license are preserved. This fork does not use the upstream release feed, sponsor data, Homebrew tap, or update infrastructure. See [FORK_NOTICE.md](../../FORK_NOTICE.md).

A native Windows app for finding and killing the processes that hold your listening ports — 3000, 8080, 5173, 22, … — plus Cloudflare tunnel inspection and managed local services. Built with **WPF on .NET 9**.

## Features

- 🔍 Auto-discovers listening TCP ports (IPv4 and IPv6) with their owning process
- ⚡ One-click kill: graceful shutdown first, then force kill, with a deep-kill that takes the process tree
- 🔄 Auto-refresh on a configurable interval
- 🔎 Search across port, process name, PID, address, user, and command line
- ⭐ Favorites, 👁️ watched ports, labels and notes
- 🗂️ Process-type categories: Web service, Database, Development, System, Other
- 🧩 Managed local services with five built-in presets, exposure warnings, and per-service runtime logs
- ☁️ Cloudflare Tunnel (quick and named) inspection with start/stop
- 🌏 English / 简体中文 UI, light / dark / system theme
- 🔔 System tray integration and a compact mini window
- 🛡️ Runs elevated (manifest) so it can terminate other users' and services' processes

## Requirements

- Windows 10 version 1809 (build 17763) or later; Windows 11 recommended
- [.NET 9 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/9.0) — release packages are framework-dependent
- Administrator privileges: `app.manifest` requests elevation

## Installation

### Option 1 — Download a release (recommended)

1. Open this fork's [GitHub Releases](https://github.com/mumu-140/port-manager/releases).
2. Download the latest `PortKiller-*-windows-x64.zip` (use the `arm64` package on ARM devices).
3. Extract the ZIP and run `PortKiller.exe`.

### Option 2 — Build from source

```bash
git clone https://github.com/mumu-140/port-manager.git
cd port-manager/platforms/windows
dotnet restore PortKiller.sln
dotnet build PortKiller/PortKiller.csproj -c Debug
dotnet run --project PortKiller/PortKiller.csproj
```

### Option 3 — Visual Studio

1. Open `platforms/windows/PortKiller.sln` in Visual Studio 2022 17.8 or later.
2. Build the solution (Ctrl+Shift+B), then run (F5).

### Option 4 — Package for distribution

```bash
# Framework-dependent, matches the CI artifacts
dotnet publish PortKiller/PortKiller.csproj -c Release -r win-x64 --self-contained false

# Self-contained single file
dotnet publish PortKiller/PortKiller.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

## Usage

### Basic operations

- The list shows every listening TCP port with its process, PID, address, and owning user; select a row for details including the command line.
- **Kill** closes the window gracefully first and force-kills only if that fails; the deep-kill option also terminates child processes.
- The search box filters on port, process name, PID, address, user, and command line; the sidebar narrows by category, favorites, or watched ports.
- Settings control the refresh interval, notifications, language, and theme.

### Watched ports

- Select a port → watch it → get a notification when it starts or stops listening.
- Watched ports are managed from the sidebar. (Notifications are raised in-app today; Windows toast integration is a planned enhancement.)

### Managed services

- The **Services** tab starts, stops, and supervises local services defined by a profile.
- Five built-in presets generate a profile from a short form — no shell command writing required:
  - **Static file share** — `python3 -m http.server`, read-only, loopback-bound
  - **SSH local forward** — your existing SSH agent/config, keepalives and `ExitOnForwardFailure` fixed
  - **SSH SOCKS5 proxy** — a dynamic forward from the same form
  - **Dufs file share** — read-only / upload / read-write modes (external binary, detected on `PATH`)
  - **Jupyter Lab** — notebook server profile
- Profiles that bind beyond loopback raise an exposure warning; runtime logs are stored per service.

### Cloudflare tunnels

- Inspect quick and named tunnels, their ingress configuration, and runtime state.
- Start/stop supported local tunnel workflows and copy public URLs.

### System tray and mini window

- Left-click the tray icon to show/hide the window, right-click for the context menu.
- The mini window keeps a compact always-available view of the port list.

## Architecture

### Technology stack

- **Language:** C# on **.NET 9** (`net9.0-windows`)
- **UI:** **WPF** with shared design tokens (`DesignTokens.xaml`) and `Hardcodet.NotifyIcon.Wpf` for the tray
- **Architecture:** MVVM via `CommunityToolkit.Mvvm`; DI via `Microsoft.Extensions.DependencyInjection`
- **Windows APIs:** `GetExtendedTcpTable` (P/Invoke) for the listening table, `System.Management` (WMI) for command lines

### Project structure

```
platforms/windows/
├── PortKiller/
│   ├── Models/        # PortInfo, ProcessType, PortFilter, ManagedService, CloudflareTunnel, AppLanguage, AppTheme
│   ├── Services/      # PortScannerService, ProcessKillerService, SettingsService, NotificationService,
│   │                  # LocalizationService, ThemeService, TunnelService, ManagedService*
│   │   └── Presets/   # ManagedServicePresets, ManagedServicePresetFieldExtractor
│   ├── ViewModels/    # MainViewModel, ManagedServicesViewModel, TunnelViewModel
│   ├── Views/         # ManagedServicesView, SettingsView, ManagedServiceEditorWindow
│   ├── Helpers/       # LocExtension, ValueConverters, WindowBlurHelper
│   ├── MainWindow.xaml, CloudflareTunnelsView.xaml, MiniPortKillerWindow.xaml
│   └── App.xaml
├── PortKiller.Tests/  # xUnit tests for the scan, kill, settings, and managed-service paths
├── scripts/           # smoke-gui.ps1, smoke-service-survival.ps1
└── PortKiller.sln
```

### How it works

#### Port scanning

`GetExtendedTcpTable` returns the listening TCP table (IPv4 and IPv6) together with the owning PIDs in a single call, so filtering happens in the OS rather than in the app. Process names, owners, and command lines are resolved afterwards: command lines come from one bulk `Win32_Process` WMI query that is cached per scan and bounded by a timeout, so a wedged WMI provider host degrades the command-line column instead of stalling the scan (`Services/ProcessCommandLineProvider.cs`).

#### Process termination

1. Try a graceful close with `Process.CloseMainWindow()`.
2. Fall back to `Process.Kill(entireProcessTree: true)`, which also covers child processes.

#### Settings and state

Settings live in `settings.json` under `%LOCALAPPDATA%\PortKiller`. Favorites, watched ports, and managed-service profiles are stored alongside it.

## Development

### Prerequisites

- .NET 9 SDK (`dotnet --version` ≥ 9.0) or Visual Studio 2022 17.8+
- Windows 10 1809+ / Windows 11

### Build

```bash
dotnet build platforms/windows/PortKiller/PortKiller.csproj -c Debug
```

### Test

```bash
dotnet test platforms/windows/PortKiller.sln -c Debug
```

### Smoke scripts

```powershell
pwsh platforms/windows/scripts/smoke-gui.ps1
pwsh platforms/windows/scripts/smoke-service-survival.ps1
```

### Continuous integration

[`.github/workflows/ci-windows.yml`](../../.github/workflows/ci-windows.yml) restores the solution, runs the tests in Debug, publishes `win-x64` and `win-arm64`, and uploads `PortKiller-windows-x64` / `PortKiller-windows-arm64` artifacts on `windows-latest`.

## Known limitations

- Killing another user's process or a service requires elevation; the manifest requests it at startup.
- Protected system processes cannot be killed (by design).
- Only TCP listeners are listed — UDP sockets are out of scope.
- Command lines require WMI; while the provider host is unresponsive they are omitted and the app retries once it recovers.

## Troubleshooting

### "Access denied" when killing a process

Run the app elevated (right-click → "Run as administrator"). The manifest normally prompts already; if the app was started from a non-elevated shell, restart it.

### The port list is empty and the status stays at "Ready"

The scan waits on WMI for command lines. Check that the **Windows Management Instrumentation** (`Winmgmt`) service is running — `services.msc` → Windows Management Instrumentation → Restart. The app recovers on the next refresh without a restart.

### The app does not start

1. Confirm Windows 10 1809+ or Windows 11.
2. Install the [.NET 9 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/9.0).

## Comparison with the macOS app

| Feature | macOS | Windows |
| --- | --- | --- |
| Port scanning | `lsof` / libproc | `GetExtendedTcpTable` (P/Invoke) |
| Process killing | `kill -15/-9` | `Process.CloseMainWindow()` / `Process.Kill()` |
| UI framework | SwiftUI | WPF |
| System tray | `MenuBarExtra` | `Hardcodet.NotifyIcon.Wpf` |
| Settings storage | `UserDefaults` | `settings.json` in `%LOCALAPPDATA%` |

## Contributing

See [CONTRIBUTING.md](../../CONTRIBUTING.md) and [STYLE_GUIDE.md](../../STYLE_GUIDE.md).

## License

MIT — see [LICENSE](../../LICENSE).

## Credits

- **Original project:** [productdevbook/port-killer](https://github.com/productdevbook/port-killer) — the Windows app, macOS app, and Linux tray app all started there. Original authorship and the MIT license are preserved.
- **This fork:** maintained independently at [mumu-140/port-manager](https://github.com/mumu-140/port-manager), which owns this repository's roadmap, localization, CI, and release infrastructure. Full provenance statement: [FORK_NOTICE.md](../../FORK_NOTICE.md).
