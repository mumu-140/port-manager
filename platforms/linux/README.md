# PortKiller for Linux

> Part of **[Port Manager](https://github.com/mumu-140/port-manager)** (`mumu-140/port-manager`) — an independently maintained cross-platform port-management project. The tray app keeps the **PortKiller** product name for compatibility.
>
> **Fork provenance:** this code began as a fork of [productdevbook/port-killer](https://github.com/productdevbook/port-killer); upstream authorship and the MIT license are preserved. This fork does not use the upstream release feed, Homebrew tap, or sponsor data. See [FORK_NOTICE.md](../../FORK_NOTICE.md).

A GTK 3 system-tray app for monitoring listening ports and terminating the processes behind them, with Kubernetes port-forward and Cloudflare tunnel helpers. Pure Python 3 — no build step.

## Features

- 🔍 Listening TCP ports via `ss` (with an `lsof` fallback), including the owning process
- ⚡ Kill processes from the tray window; copy port details to the clipboard
- ☸️ Kubernetes port-forward support (`src/services/k8s.py`)
- ☁️ Cloudflare tunnel inspection (`src/services/cloudflare.py`)
- 🖥️ AppIndicator tray icon with a GTK 3 window and port detail dialogs
- 🚀 Installer that sets up the desktop entry, icon, and autostart

## Requirements

- A GTK 3 desktop with PyGObject: `python3-gi`, `gir1.2-gtk-3.0`
- An AppIndicator implementation: `gir1.2-ayatanaappindicator3-0.1` (or `gir1.2-appindicator3-0.1`)
- Python 3.9 or later (CI covers 3.9 and 3.12)
- `iproute2` (`ss`) and/or `lsof` for scanning

## Installation

### Installer (recommended)

```bash
git clone https://github.com/mumu-140/port-manager.git
cd port-manager/platforms/linux
./install.sh
```

`install.sh` verifies the GTK/AppIndicator runtime first, then installs the app into `~/.local/share/port-killer` and adds:

- `~/.local/share/applications/port-killer.desktop` (launcher entry)
- the app icon under `~/.local/share/icons/hicolor/scalable/apps`
- an autostart entry in `~/.config/autostart`

### Run without installing

```bash
python3 platforms/linux/port-killer.py
```

### AppImage

Releases publish `PortKiller-*-linux-x86_64.AppImage`, built from `src/` + `port-killer.py` + icon + desktop entry in [`.github/workflows/release.yml`](../../.github/workflows/release.yml).

## Tests

```bash
python3 -m unittest discover -s platforms/linux/tests -v
```

## Architecture

### Technology stack

- **Language:** Python 3
- **UI:** GTK 3 through PyGObject; tray icon via `AppIndicator3` / `AyatanaAppIndicator3`
- **Entry point:** `port-killer.py` → `src/main.py`
- **Config:** JSON at `~/.config/port-killer/config.json` (favorites, settings)

### Layout

```
platforms/linux/
├── port-killer.py        # launcher (adds src/ to sys.path, calls src.main)
├── install.sh            # runtime checks, install, desktop entry, autostart
├── src/
│   ├── main.py           # GTK application bootstrap
│   ├── config.py         # ~/.config/port-killer/config.json
│   ├── scanner.py        # ss first, lsof fallback
│   ├── services/         # k8s.py, cloudflare.py, clipboard.py
│   └── ui/               # tray.py, window.py, dialogs.py, styles.css
└── tests/                # unittest suite (scanner, k8s)
```

### The Rust core

`portkiller-core` at the repository root is a port-scanning and process-management library under development for this app. It is built, tested, linted, and formatted in CI (`cargo build`, `cargo test`, `cargo clippy -- -D warnings`, `cargo fmt --check`) but is **not yet wired into the tray app**, which uses the Python scanner.

## Continuous integration

[`ci-linux.yml`](../../.github/workflows/ci-linux.yml) runs two jobs:

- **Rust Core (Linux):** `cargo build`, `cargo test`, `cargo clippy -- -D warnings`, `cargo fmt --check` (with `lsof`, `iproute2`, `procps` installed).
- **Linux Tray App:** Python 3.9 and 3.12 — `compileall` syntax check, the unittest suite, installer validation, and a GTK import smoke test.

## Troubleshooting

### No tray icon appears

Install an AppIndicator implementation: `gir1.2-ayatanaappindicator3-0.1` (Debian/Ubuntu) or `libappindicator-gtk3` (Fedora), then restart the session.

### `ImportError: No module named gi`

Install PyGObject and GTK 3 bindings: `python3-gi`, `gir1.2-gtk-3.0`.

### Ports are missing or processes are unnamed

Scanning prefers `ss`, so install `iproute2` (keep `lsof` as a fallback). Ports and command lines owned by other users can be hidden without sufficient privileges.

### Stop the app from starting at login

Remove `~/.config/autostart/port-killer.desktop`.

## Comparison with the Windows app

| Feature | Linux | Windows |
| --- | --- | --- |
| Port scanning | `ss`, then `lsof` | `GetExtendedTcpTable` (P/Invoke) |
| Process killing | `kill` / process signals | `Process.CloseMainWindow()` / `Process.Kill()` |
| UI framework | GTK 3 (PyGObject) | WPF |
| System tray | AppIndicator | `Hardcodet.NotifyIcon.Wpf` |
| Settings storage | `~/.config/port-killer/config.json` | `settings.json` in `%LOCALAPPDATA%` |

## Contributing

See [CONTRIBUTING.md](../../CONTRIBUTING.md).

## License

MIT — see [LICENSE](../../LICENSE).

## Credits

- **Original project:** [productdevbook/port-killer](https://github.com/productdevbook/port-killer) — the Linux tray app, macOS app, and Windows app all started there. Original authorship and the MIT license are preserved.
- **This fork:** maintained independently at [mumu-140/port-manager](https://github.com/mumu-140/port-manager), which owns this repository's roadmap, CI, and release infrastructure. Full provenance statement: [FORK_NOTICE.md](../../FORK_NOTICE.md).
