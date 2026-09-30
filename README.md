# Port Manager

<p align="center">
  <img src="platforms/macos/Resources/AppIcon.svg" alt="PortKiller icon" width="128" height="128">
</p>

<p align="center">
  <a href="https://github.com/mumu-140/port-manager/actions/workflows/ci.yml"><img src="https://github.com/mumu-140/port-manager/actions/workflows/ci.yml/badge.svg" alt="macOS CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-15%2B-brightgreen" alt="macOS 15+"></a>
  <a href="https://www.microsoft.com/windows"><img src="https://img.shields.io/badge/Windows-10%2B-0078D6" alt="Windows 10+"></a>
</p>

Port Manager is an independently maintained cross-platform port-management project. The current desktop application keeps the **PortKiller** product/executable name for compatibility while this repository develops its own roadmap, localization, CI, runtime data sources, and release infrastructure.

> **Fork provenance:** this repository began as a fork of [productdevbook/port-killer](https://github.com/productdevbook/port-killer). Original upstream authorship and the MIT license are preserved. Development in `mumu-140/port-manager` is now maintained independently; upstream release feeds, sponsor data, Homebrew publishing, and update infrastructure are not used by this fork. See [FORK_NOTICE.md](FORK_NOTICE.md).

## Current status

| Area | Status |
| --- | --- |
| macOS native app | Active |
| macOS English / Simplified Chinese UI | Phase 1 frozen |
| Kubernetes port-forward management | Active |
| Cloudflare Tunnel integration | Active |
| Windows native app | Active |
| Linux tray app / AppImage | Active |
| GitHub Actions CI artifacts | Active |
| Independent GitHub Releases | Available from `v*` tags |
| macOS Developer ID signing / notarization | Not yet configured for this fork |
| Sparkle automatic updates | Intentionally disabled until this fork has its own signing key/feed |
| Upstream Homebrew tap | Not used |

The repository is the source of truth for this fork:

`https://github.com/mumu-140/port-manager`

## Screenshots

### macOS

<p align="center">
  <img src=".github/assets/macos.png" alt="PortKiller on macOS" width="800">
</p>

### Windows

<p align="center">
  <img src=".github/assets/windows.jpeg" alt="PortKiller on Windows" width="800">
</p>

## Features

### Port management

- Discover listening TCP ports and owning processes.
- Graceful termination, force kill, and deep-kill workflows.
- Search, filtering, favorites, watched ports, labels, and notes.
- Process-type categorization and configurable notifications.
- Auto-refresh and auto-kill rules.

### Kubernetes port forwarding

- Create and manage `kubectl port-forward` connections.
- Browse contexts, namespaces, services, and ports.
- Auto-reconnect, connection logs, and status monitoring.
- Optional proxy handling and dependency checks.

### Cloudflare Tunnels

- Inspect quick and named tunnels.
- View ingress configuration and runtime state.
- Start/stop supported local tunnel workflows.
- Open or copy public URLs directly from the app.

### macOS localization

The macOS application supports:

- English
- Simplified Chinese
- Follow System

Localization is implemented through the repository-local `L("key")` registry. CI guards format-specifier parity, missing keys, and common hardcoded-English regressions.

## Installation

### macOS

The fork does **not** use the upstream Homebrew tap.

For development and testing, use a CI artifact from the latest successful [macOS CI workflow](https://github.com/mumu-140/port-manager/actions/workflows/ci.yml), or build from source:

```bash
git clone https://github.com/mumu-140/port-manager.git
cd port-manager/platforms/macos
./scripts/build-app.sh
open .build/apple/Products/Release/PortKiller.app
```

CI/test macOS builds are not Developer-ID notarized. macOS may therefore require an explicit first launch through Finder → **Open**.

### Windows

Build from source:

```powershell
git clone https://github.com/mumu-140/port-manager.git
cd port-manager\platforms\windows\PortKiller
dotnet run
```

Tagged releases may also include x64 and ARM64 ZIP artifacts.

### Linux

Run directly:

```bash
git clone https://github.com/mumu-140/port-manager.git
cd port-manager
./platforms/linux/port-killer.py
```

Or use the local installer:

```bash
./platforms/linux/install.sh
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for dependency details.

## Repository layout

```text
platforms/
├── macos/                  Swift / SwiftUI application
├── windows/                .NET / WPF application
└── linux/                  Python / GTK tray application

portkiller-core/            Rust core used by Linux-side work
.github/workflows/          CI, PR artifact builds, independent releases
appcast.xml                 Reserved fork-local Sparkle feed
sponsors.json               Fork-local supporter data
```

## CI and release model

Normal development uses platform-specific CI:

- `.github/workflows/ci.yml` — macOS build, tests, Universal app artifact.
- `.github/workflows/ci-windows.yml` — Windows x64/ARM64 validation.
- `.github/workflows/ci-linux.yml` — Rust, Python, GTK/import validation.
- `.github/workflows/pr-build.yml` — optional macOS PR test artifact.

The release workflow is repository-local. A pushed `v*` tag creates a GitHub Release in **this repository** and attaches independently built artifacts. Manual dispatch produces test artifacts and does not create a production release.

For the current release limitations and signing policy, see [RELEASES.md](RELEASES.md).

## Update policy

The previous upstream Sparkle URL and upstream EdDSA key have been removed.

Automatic in-app updates are intentionally disabled until this fork provisions:

1. its own Apple Developer ID/signing identity,
2. its own notarization credentials,
3. its own Sparkle EdDSA key pair,
4. a release feed generated from this repository.

This prevents builds from silently switching back to an upstream release channel.

## Fork history and attribution

This project contains substantial work originating from the upstream PortKiller project. That history is intentionally acknowledged rather than hidden.

- Upstream: [productdevbook/port-killer](https://github.com/productdevbook/port-killer)
- Independent fork: [mumu-140/port-manager](https://github.com/mumu-140/port-manager)
- License: MIT
- Compatibility name retained: PortKiller

See [FORK_NOTICE.md](FORK_NOTICE.md) for the detailed provenance policy.

## Support the project

There is currently no upstream funding account or upstream sponsor feed attached to this fork.

Useful ways to support this project are:

- report reproducible bugs,
- propose focused improvements,
- test macOS/Windows/Linux artifacts,
- improve localization,
- submit reviewed pull requests,
- star the repository if it is useful.

The in-app Community page reads contributor data from this repository and optional supporter data from the repository-local `sponsors.json`.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before submitting changes. In particular:

- keep upstream attribution intact,
- do not reintroduce upstream runtime/update/release dependencies,
- keep user-visible macOS text inside the localization registry,
- run the relevant platform tests,
- keep changes scoped and reviewable.

## Security

See [SECURITY.md](SECURITY.md).

## License

MIT. The original PortKiller copyright notice is retained, with an additional notice for independent fork contributions. See [LICENSE](LICENSE).
