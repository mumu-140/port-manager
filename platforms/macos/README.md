# PortKiller for macOS

> Part of **[Port Manager](https://github.com/mumu-140/port-manager)** (`mumu-140/port-manager`) — an independently maintained cross-platform port-management project. The desktop app keeps the **PortKiller** product/bundle name for compatibility.
>
> **Fork provenance:** this code began as a fork of [productdevbook/port-killer](https://github.com/productdevbook/port-killer); upstream authorship and the MIT license are preserved. This fork does not use the upstream release feed, Sparkle appcast, Homebrew tap, or sponsor data. See [FORK_NOTICE.md](../../FORK_NOTICE.md).

A native macOS menu-bar app for finding and killing the processes behind your listening ports, managing `kubectl` port forwards, inspecting Cloudflare tunnels, and running local services from presets. Built with **SwiftUI** on Swift 6.2.

## Features

- 🔍 Listening TCP ports discovered with `lsof`, including process, user, and command line
- ⚡ Graceful terminate, force kill, and process-group handling
- 🔎 Search and filters, ⭐ favorites, 👁️ watched ports, labels and notes
- 🗂️ Process-type categories with notifications, plus port health checks
- 🔄 Auto-refresh and auto-kill rules
- ☸️ Kubernetes port forwarding: contexts, namespaces, services, monitoring, conflict resolution
- ☁️ Cloudflare Tunnels (quick and named) with ingress inspection and start/stop
- 🧩 Managed local services with presets, exposure warnings, and runtime logs
- ⌨️ Keyboard shortcuts, launch at login, onboarding, menu-bar extra and main window
- 🌏 English / 简体中文 UI
- 💛 Sponsors window reads **this fork's** sponsor and contributor data

## Requirements

- macOS 15 (Sequoia) or later
- Swift 6.2 toolchain — full Xcode, or Command Line Tools (`scripts/` pin the 26.5 SDK when Xcode is absent)
- Optional: `kubectl` for port forwarding, `cloudflared` for tunnels

## Installation

### Build from source

```bash
git clone https://github.com/mumu-140/port-manager.git
cd port-manager/platforms/macos
./scripts/build-app.sh
open .build/apple/Products/Release/PortKiller.app
```

`build-app.sh` produces a universal (`arm64` + `x86_64`) `PortKiller.app`.

### Download a release

This fork publishes `PortKiller-*-macos-universal.zip` from `v*` tags on [GitHub Releases](https://github.com/mumu-140/port-manager/releases). Builds are not Developer ID signed or notarized yet, so Gatekeeper may require right-click → **Open** the first time.

## Tests

```bash
./scripts/test.sh                       # swift test, runs with Command Line Tools only
./scripts/smoke-service-survival.sh     # managed-service survival smoke test
```

## Architecture

### Technology stack

- **Language:** Swift 6.2 (`swift-tools-version: 6.2`), SwiftPM executable target `PortKiller`, macOS 15+
- **UI:** SwiftUI; `LSUIElement` menu-bar app (bundle id `com.portkiller.app`)
- **Dependencies:** `KeyboardShortcuts`, `Defaults` (UserDefaults storage), `LaunchAtLogin-Modern`, `Sparkle` (updates disabled until this fork owns a signing key and feed)

### Layout

```
platforms/macos/
├── Package.swift
├── Sources/
│   ├── PortKillerApp.swift, PortScanner.swift, Constants.swift
│   ├── AppState+*.swift     # feature slices: favorites, watched ports, labels, notes,
│   │                        # port operations, auto-refresh, shortcuts, managed services
│   ├── Services/            # dependency checks, cloudflared, notifications, managed services
│   │   ├── ManagedServices/, Presets/
│   ├── Managers/            # PortForward*, KubernetesDiscovery, AutoKill, NamedTunnel,
│   │                        # ManagedService, Sponsor
│   ├── ViewModels/, Views/  # MainWindow, PortTable, PortForwarder, CloudflareTunnels,
│   │                        # ManagedServices, MenuBar, Onboarding, Settings
│   ├── Models/, State/, Protocols/, Extensions/
│   ├── DesignSystem/, Localization/   # English / 简体中文
├── Tests/                   # 17 test files
├── Resources/               # Info.plist, AppIcon, ToolbarIcon
└── scripts/                 # build-app.sh, test.sh, smoke-service-survival.sh
```

### How it works

- **Scanning:** `lsof -iTCP -sTCP:LISTEN -P -n +c 0`, parsed into `PortInfo`; `ps` and `kill` back the process operations.
- **Kubernetes:** `PortForwardManager` / `PortForwardProcessManager` drive `kubectl port-forward`, with monitoring and conflict resolution.
- **Tunnels:** `CloudflaredService` and `NamedTunnelManager` inspect and control quick and named tunnels.
- **Services:** `ManagedServiceManager` supervises profiles built from presets, with runtime logs and exposure warnings.
- **Permissions:** `PermissionService` checks and requests accessibility and notification permissions.

## Development

```bash
swift build
swift test --parallel
```

[`ci.yml`](../../.github/workflows/ci.yml) builds on `macos-latest` with the latest stable Xcode, checks for warnings, runs the tests, and packages a universal app bundle as a CI artifact.

## Troubleshooting

### The app has no Dock icon

By design — it is an `LSUIElement` menu-bar app. Use the menu-bar icon to show the window.

### Kubernetes or Cloudflare features are unavailable

Install `kubectl` / `cloudflared` and make sure they are on `PATH`; the app discovers both at runtime (`DependencyChecker`, `CloudflaredDiscoveryService`).

### Gatekeeper blocks the downloaded build

This fork has no Developer ID certificate yet: right-click the app → **Open**, or build from source.

### Automatic updates

Sparkle checks are intentionally disabled until this fork publishes its own signed feed. Update manually from [Releases](https://github.com/mumu-140/port-manager/releases).

## Comparison with the Windows app

| Feature | macOS | Windows |
| --- | --- | --- |
| Port scanning | `lsof` | `GetExtendedTcpTable` (P/Invoke) |
| Process killing | `kill -15/-9` | `Process.CloseMainWindow()` / `Process.Kill()` |
| UI framework | SwiftUI | WPF |
| System tray | `MenuBarExtra` | `Hardcodet.NotifyIcon.Wpf` |
| Settings storage | `UserDefaults` | `settings.json` in `%LOCALAPPDATA%` |

## Contributing

See [CONTRIBUTING.md](../../CONTRIBUTING.md) and [STYLE_GUIDE.md](../../STYLE_GUIDE.md), which documents the macOS Swift conventions.

## License

MIT — see [LICENSE](../../LICENSE).

## Credits

- **Original project:** [productdevbook/port-killer](https://github.com/productdevbook/port-killer) — the macOS app, Windows app, and Linux tray app all started there. Original authorship and the MIT license are preserved.
- **This fork:** maintained independently at [mumu-140/port-manager](https://github.com/mumu-140/port-manager), which owns this repository's roadmap, localization, CI, and release infrastructure. Full provenance statement: [FORK_NOTICE.md](../../FORK_NOTICE.md).
