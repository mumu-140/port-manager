# Presets + Exposure UX v1 — Research

**Status:** DRAFT FOR REVIEW
**Date:** 2026-10-01
**Repository:** `mumu-140/port-manager`
**Base SHA:** `3e007d4` (main, verified up to date with `origin/main` at research time)
**Scope:** macOS + Windows. Linux, Tailscale, MCP, CLI, frp, auto-install, credential storage, and system-level persistence are out of scope (v1).

Access date for every external source in this document: **2026-10-01**.

---

## 0. Research questions

| # | Question |
|---|---|
| Q1 | What exactly do the current macOS/Windows Managed Service implementations provide that presets can reuse? |
| Q2 | Where do macOS and Windows differ in ways that affect presets and exposure UX? |
| Q3 | Can presets be modelled purely as editor-layer generation over the existing `ManagedServiceConfig`? |
| Q4 | Can the existing Named Tunnel functionality be surfaced without redesigning it? |
| Q5 | Does current code already provide dependency discovery, and what must be generalized? |
| Q6 | OpenSSH: safe defaults for -L / -R / -D, keepalive, failure semantics, ssh-config alias handling? |
| Q7 | Windows OpenSSH client: availability, detection, syntax parity? |
| Q8 | Python `http.server`: capabilities, limits, safe defaults? |
| Q9 | Dufs: platforms, CLI, permission flags, auth, detection, distribution? |
| Q10 | JupyterLab: CLI, safe defaults, auth behavior, detection? |
| Q11 | Cloudflare Quick Tunnel: lifecycle and persistence guarantees per official docs? |
| Q12 | Cloudflare Named Tunnel: what does the existing integration support vs official docs; what would OS-service mode require? |
| Q13 | What would a future "Keep Alive / Start at boot" SSH tunnel require (research only)? |

---

## 1. Baseline audit (Phase 1 findings)

### 1.1 Frozen baseline — what exists today

The Managed Service increment (design doc `docs/plans/2026-09-30-service-manager-design-and-implementation.md`, status READY FOR IMPLEMENTATION, already implemented on both platforms) froze this shape:

**Persisted profile** — identical on both platforms:

```
ManagedServiceConfig
- id: UUID / Guid
- name: String
- port: Int (1...65535)
- host: String (display + Open URL only; never interpolated into the command)
- workingDirectory: String (must exist at save time)
- startCommand: String (only {port} placeholder allowed)
```

**Runtime model:** semantic states `stopped / starting / running / stopping / conflict / failed` shared by both platforms (macOS `ManagedServiceStatus`, Windows `ManagedServiceStatus` enum). Readiness: poll the configured port (macOS 250 ms interval, 20 s timeout; Windows equivalent). Conflict = configured port occupied by a process the session does not own.

**Ownership invariants (verified in code, not just docs):**

- macOS `ManagedServiceProcessController.launch` runs the command via `/bin/zsh -lc <command>` (`platforms/macos/Sources/Services/ManagedServiceProcessController.swift`, ~L102-104); working directory is set via `currentDirectoryURL` (process API, not shell `cd`).
- Windows `ManagedServiceRuntimeLauncher.Launch` runs the command via `cmd.exe /d /s /c "<command>"` (`platforms/windows/PortKiller/Services/ManagedServiceRuntimeLauncher.cs` L163-167); working directory via `lpCurrentDirectory` (L174); root created suspended inside a Job Object, so a stop terminates the whole owned tree.
- Termination only ever signals tracked runtimes: macOS SIGTERM→3 s grace→SIGKILL on root + descendants (L208-228); Windows job-object termination. Conflict kill requires explicit user confirmation and only the user-confirmed PID snapshot (`resolveConflictAndStart`, snapshot taken before any signal).
- Reconciliation proves ownership: a running profile stays Running only while the port is served by PIDs the session owns (`reconcileRunning`); after relaunch a surviving listener is unowned Conflict.
- Runtime output goes to per-service files, never parent-owned pipes, so a child may outlive Port Manager (`ManagedServiceRuntimeLogStore` / `PORT_MANAGER_SERVICE_ID` env var).

**Quick Tunnel integration (both platforms):**

- macOS: `TunnelManager` (Quick only) + `NamedTunnelManager` + `CloudflaredService` actor. `stop(id:)` in the manager calls `tunnelCoordinator?.stopTunnel(for: state.port)` **before** terminating the process — Stop service stops its temporary Quick Tunnel. Restart does not re-share.
- Windows: `TunnelViewModel` implements `IManagedServiceTunnelHost`; `TunnelService` launches `tunnel --url localhost:{port} --protocol {arg}`, keys processes by tunnel `Guid`, and the service-tunnel association is **by port** (`FirstOrDefault(t => t.Port == state.Config.Port)`). Tests prove `StartLeavesTunnelsAlone` / `StopReleasesTheAssociatedTunnel` / `RestartReleasesTheTunnelWithoutSharingAgain`.
- Tunnel URL parsing on both platforms: regex `https://[a-z0-9-]+\\.trycloudflare\\.com` from cloudflared stdout/stderr.
- Orphan cleanup at startup: `pkill -9 -f 'cloudflared.*tunnel.*--url'` (macOS) / command-line scan (Windows).

**Delete behavior (current):**

- macOS: manager `remove(id:)` stops the owned runtime first (which stops the Quick Tunnel via coordinator), removes profile + runtime logs, persists.
- Windows: `Delete_Click` (`ManagedServicesView.xaml.cs` L88-109) — transitioning guard first (`MessageBox OK` "Wait for "X" to finish its current operation." caption "Delete service", icon Information); then state-mapped message:
  - Running: `Delete "X"? The owned service is stopped first.`
  - Conflict: `Delete "X"? The process using port N is left running.`
  - Default (Stopped/Starting/Failed): `Delete "X"?`
  - Buttons `OKCancel`, icon Warning, caption "Delete service". Single "Delete" button — no Stop & Delete / Delete Configuration Only variants. Quick Tunnel not mentioned in the delete copy. No "Don't ask again" anywhere.
- Behavior split lives in the ViewModel (`DeleteAsync`): running owned service is stopped first; conflict profile is deleted without ever signalling the occupant ("Could not stop X; it was not deleted." on stop failure).

**macOS delete confirmation specifics (verified in view code):** SwiftUI `.confirmationDialog(..., titleVisibility: .visible)` in ManagedServiceDetailView.swift:36-48 and ManagedServicesListView.swift:51-67. Title "Delete Service"; destructive button "Delete"; Cancel (role .cancel). Message keyed on `isOwned` only: stopped/failed → "Delete “%@”?"; owned running → "“%@” is running and will be stopped before deletion." Conflict never reaches the dialog (Delete disabled while transitioning). No Quick Tunnel mention. No Stop & Delete / Delete Configuration Only. No "Don't ask again".

**Editor (current):** both platforms show Name / Port / Host / Working directory / Start command. Windows: 480×520 "Service profile" window, multiline command box, helper copy "Use {port} in the command if the command should automatically follow future port edits." and "Commands are stored in plain text. Prefer environment variables over embedding secrets." macOS editor adds helper captions: "Use {port} to follow future port edits.", "Run the server in the foreground; daemonized commands are not supported.", "Avoid embedding passwords or tokens; prefer environment variables."; working directory has an NSOpenPanel "Choose..." button. **No preset/template picker exists on either platform. No working-directory picker on Windows (plain TextBox; zero dialog hits).**

**Services view (current):** header "Local Services"; list (Name, Port, Status); detail (command, working directory, error, Start/Stop/Restart/Open/Edit/Delete). Quick Tunnel card only for a running service: title "Cloudflare Quick Tunnel" (Windows) / "Quick Tunnel" (macOS detail section), status text mapping (Not shared / Tunnel starting / Public endpoint active / Tunnel stopping / Tunnel error / Tunnel idle), URL shown when active, buttons Share / Stop Tunnel / Copy URL / Open Tunnel (Windows) and Start Tunnel / Copy / Open / Stop Tunnel / Retry (macOS). Named tunnels: not surfaced from Local Services on either platform. Windows `CloudflareTunnelsView` is dead code (zero instantiation sites).

**Persistence:** macOS `Defaults[.managedServices]` (UserDefaults key `managedServices`); Windows `%LOCALAPPDATA%\\PortKiller\\settings.json` → `ManagedServices` list. Runtime state never persisted. A preset system must keep both shapes backward-compatible.

### 1.2 Existing dependency discovery (Q5)

- `CloudflaredService.cloudflaredPath` (macOS): custom path from Defaults first, then `/opt/homebrew/bin/cloudflared`, `/usr/local/bin/cloudflared` via `FileManager.fileExists`; `isInstalled`, `isUsingCustomPath`, `autoDetectedPath`. Cached in `TunnelState.isCloudflaredInstalled` with `recheckInstallation()`.
- Windows `TunnelService.CloudflaredPaths`: Program Files / Program Files (x86) / Chocolatey / LocalApplicationData paths, then PATH via `where`; surfaced as `IsCloudflaredInstalled` + "cloudflared Not Found" dialog listing installation options.
- Also present (outside Managed Services): `DependencyChecker` (kubectl/socat) + `DependencyWarningBanner` in PortForwarder views; `AlertBanner` design-system component "Generalizes DependencyWarningBanner and CloudflaredMissingBanner" (Views/Components/DesignSystem/AlertBanner.swift:4) — a reusable banner already exists if Managed Services needs one.
- This is per-binary path probing — exactly the pattern a generalized dependency layer should reuse (known paths + PATH probe + cached result + recheck action). No shell output parsing, no secrets, no destructive checks.

### 1.3 macOS vs Windows differences that matter for this increment

| Area | macOS | Windows | Consequence |
|---|---|---|---|
| Shell | `/bin/zsh -lc` (login shell) | `cmd.exe /d /s /c` | Preset escaping must be per-platform; see §7 |
| Process tree | ps-derived descendants + signals | Job Object | No impact on presets |
| Persistence | UserDefaults (plist) | settings.json | Both schema-compatible with optional extra fields |
| Working-dir picker | NSOpenPanel exists | plain TextBox, no dialog | Preset file-share flow must add a picker on Windows |
| Tunnel association | port-keyed coordinator protocol | port-keyed VM lookup | Port-keyed association is the frozen convention |
| Delete dialog | SwiftUI confirmationDialog | MessageBox OKCancel | Copy semantics must match; visuals stay platform-native |
| Tests | model/manager/editor-viewmodel/log/tree/survival suites | 51 managed-service tests incl. survival smokes | New preset tests must not disturb existing suites |

### 1.4 Answers to Phase-1 questions (Q1-Q5)

- **Q1 Reusable:** the entire lifecycle stack (manager, controller, validator, renderer seams, storage, tunnel coordinator protocols, conflict model, reconciliation). Presets only add an editor-layer generator producing `ManagedServiceConfig`.
- **Q2 Differences:** shell (zsh vs cmd.exe), working-dir picker availability, delete-dialog API, persistence backend, test coverage. None block presets; all are editor-layer concerns.
- **Q3 Presets as editor-layer generation:** yes — `ManagedServiceConfig` is a closed value type with six fields; a preset only needs to fill it. No manager changes required.
- **Q4 Named Tunnel surfacing:** `NamedTunnelManager` (macOS) is self-contained (discovery gated behind the tunnels UI to avoid account hits; `PortExposure` struct already exists). Windows has no named-tunnel support at all — surfacing must be macOS-first with a "not available" state on Windows, or linked as a global feature.
- **Q5 Dependency discovery:** only cloudflared, per-binary path probing on both platforms; plus kubectl/socat DependencyChecker in Port Forwarder. Generalizable as-is.

---

## 2. OpenSSH (Q6)

Sources (accessed 2026-10-01):
- https://man.openbsd.org/ssh — ssh(1) man page (OpenBSD current)
- https://man.openbsd.org/ssh_config — ssh_config(5)
- https://man.openbsd.org/sshd_config — sshd_config(5)
- Local verification: `ssh -V` on this machine → OpenSSH_10.3p1 (macOS); `~/.ssh/config` enumeration test: 22 non-wildcard Host entries parse cleanly without reading any key material.

### 2.1 Local forwarding (-L)

Verified from ssh(1): "-L [bind_address:]port:host:hostport ... connections to the given TCP port ... on the local (client) host are to be forwarded to the given host and port ... on the remote side."

- **Local bind default:** "By default, the local port is bound in accordance with the GatewayPorts setting" of the **client** ssh_config; ssh_config(5) GatewayPorts default is `no` → loopback. Explicit `bind_address` overrides: `localhost` = local-only, empty or `*` = all interfaces.
- **Safe default:** pass explicit `-L 127.0.0.1:PORT:DEST:PORT`. Never rely on config inheritance.
- **Privileged ports (<1024)** require superuser — preset should reject/annotate ports below 1024 as "requires admin" rather than fail mysteriously.
- **macOS/Windows behavior:** identical semantics; both ship OpenSSH clients (see §3 for Windows distribution).

### 2.2 ExitOnForwardFailure

From ssh_config(5): "Specifies whether ssh(1) should terminate the connection if it cannot set up all requested dynamic, tunnel, local, and remote port forwardings, (e.g. if either end is unable to bind and listen on a specified port). ... The argument must be yes or no (the default)."

- Default `no`: ssh keeps a dead session alive even when the forward failed — useless as a managed service. **Every forwarding preset must send `-o ExitOnForwardFailure=yes`** so the readiness model (port becomes occupied ⇒ Running; process exit ⇒ Failed) matches reality: with it, a bind failure = ssh exits nonzero = Failed state, exactly what the existing manager expects.
- Note the documented boundary: ExitOnForwardFailure does NOT cover failure of connections to the forwarding destination — only the bind.

### 2.3 Keepalives

- `ServerAliveInterval`: default 0 (disabled). "Sets a timeout interval in seconds after which if no data has been received from the server, ssh(1) will send a message through the encrypted channel to request a response."
- `ServerAliveCountMax`: default 3. If the threshold is reached, ssh disconnects. Encrypted-channel probes are unspoofable.
- `TCPKeepAlive`: TCP-level, spoofable; docs explicitly contrast it with server-alive messages. **Verdict: TCPKeepAlive adds nothing meaningful for managed forwarders** — the encrypted server-alive mechanism is strictly better. Presets expose only ServerAliveInterval/ServerAliveCountMax (defaults 15/3 proposed; 15×3 = 45 s dead-peer detection per man page example).
- A forwarding preset should also pass `-N` (no remote command) — the ssh process exists purely to carry forwards.

### 2.4 Reverse forwarding (-R) — the security-critical one

Verified from ssh(1): "Specifies that connections to the given TCP port or Unix socket on the remote (server) host are to be forwarded to the local side. ... **By default, TCP listening sockets on the server will be bound to the loopback interface only.** This may be overridden by specifying a bind_address. An empty bind_address, or the address '*', indicates that the remote socket should listen on all interfaces. **Specifying a remote bind_address will only succeed if the server's GatewayPorts option is enabled (see sshd_config(5)).**"

sshd_config(5) GatewayPorts: "no to force remote port forwardings to be available to the local host only, yes to force remote port forwardings to bind to the wildcard address, or clientspecified to allow the client to select."

Security analysis:
- Remote loopback = only processes on the SSH server itself can reach the forwarded port. This is the safe default and must be the preset default.
- `-R 0.0.0.0:port:...` binds the remote port on **all interfaces of the SSH server** — anyone who can reach that server can reach the user's local service. It only works when sshd has `GatewayPorts clientspecified` (or yes). Many hardened servers set `no`.
- Therefore: the preset default remote bind MUST be `127.0.0.1`; choosing `0.0.0.0` (or `*`) requires an explicit opt-in with a strong warning that states: (a) the port becomes reachable by anyone who can reach the SSH server, subject to that server's GatewayPorts policy; (b) the attempt can silently fail at the server side if GatewayPorts forbids it — with ExitOnForwardFailure=yes this becomes a clean Failed state instead of a false "running" tunnel.
- **Review decision (v1):** the SSH reverse forward preset is **not shipped in v1** — its lifecycle contradicts the ManagedService contract (Start requires {port} free + a local listener ready; `-R` has no local listener to observe). These findings are retained for the future Exposure/provider design or readiness-model design.

### 2.5 Dynamic/SOCKS forwarding (-D)

From ssh(1): "-D [bind_address:]port — Specifies a local 'dynamic' application-level port forwarding... ssh will act as a SOCKS server. Currently the SOCKS4 and SOCKS5 protocols are supported." Same bind rules as -L (client GatewayPorts governs the default; explicit bind wins).

- Safe default: `-D 127.0.0.1:PORT`. SOCKS4/5 both served; document SOCKS5 as the expected protocol for clients.
- No destination fields — the only inputs are host, bind address, port, keepalive options.

### 2.6 SSH config / host aliases

- OpenSSH natively resolves `Host` aliases from `~/.ssh/config` (plus `/etc/ssh/ssh_config` and includes): hostname, user, port, identityfile, proxyjump etc. all come from the alias — **the preset should treat the alias as the single connection input** while still allowing an explicit `user@host:port` override for people without config entries. This matches the task's preferred direction: reuse existing aliases, never read or store key contents.
- **Review decision (v1):** alias enumeration is **deferred** — v1 ships manual free-text entry (Host alias or `user@host`) only; no SSH-config parsing ships in v1, and keys/IdentityFile values are never read.
- **Alias enumeration:** parse only `Host` / `Match` line starts in `~/.ssh/config` (and `Include`d files, bounded), skipping wildcard/complement patterns (`*`, `!`). awk/Grep-style line scan touches no key material, follows no secrets, and never executes ssh. Alternatives rejected: `ssh -G` (executes ssh with full config evaluation; heavier and prints resolved identity data — only safe to run on demand for one user-chosen alias, never to enumerate); reading config fully into memory (unnecessary). Port Manager should render alias suggestions from the line scan and let the user type a free-form destination as fallback. Local test: 22 alias entries enumerated by name-only scan without printing any content.
- **Failure semantics:** with `ExitOnForwardFailure=yes` + `-N`, all failure modes (auth failure, unreachable host, bind conflict, remote bind refused by GatewayPorts) collapse into "ssh exits nonzero" → existing manager marks Failed with exit code; output log shows the reason. Auth prompts (password) on a foreground ssh in a managed runtime hang until timeout — presets must advise key-based auth (agent or default keys) and note that interactive password auth is unsupported for managed runtimes.

---

## 3. Python static file server (Q8)

Sources (accessed 2026-10-01):
- https://docs.python.org/3/library/http.server.html — official docs, Python 3.14.8
- https://docs.python.org/3/using/mac.html — macOS Python usage
- https://docs.python.org/3/using/windows.html — Windows Python usage

Findings:

- CLI: `python -m http.server [OPTIONS] [port]` (default port **8000**). `-b/--bind <address>` (since 3.4), `-d/--directory <dir>` (since 3.7), `--protocol HTTP/1.1` (since 3.11), TLS flags since 3.14.
- **Default bind is all interfaces** — docs verbatim: "By default, the server binds itself to all interfaces." The preset MUST pass `-b 127.0.0.1` explicitly.
- **No authentication.** "http.server is not recommended for production. It only implements basic security checks."
- **Directory listing exposure:** requests mapping to a directory with no index page generate a full listing via `list_directory()`.
- **Symlinks:** SimpleHTTPRequestHandler **follows symbolic links** — files outside the served directory can be served. Security section also documents header-injection assumptions and (pre-3.12) terminal control-code injection via logs.
- GET/HEAD only; no upload. The CLI runs a ThreadingHTTPServer (threads since 3.7).
- Naming: **macOS → `python3`** (Apple ships an older /usr/bin/python3 tied to CLT; plain `python` does not exist by default). **Windows → `python` or `py`** (`python3` exists only as a POSIX-misuse trap, "not meant to be widely used").

Verdict: viable as the zero-dependency "Static File Share" (macOS ships python3 via CLT; most Windows dev machines have python). Defaults: bind 127.0.0.1, user-chosen directory, read-only, port user-chosen. External exposure must be a deliberate Exposure choice (Quick Tunnel), never a default.

---

## 4. Dufs (Q9)

Sources (accessed 2026-10-01):
- https://raw.githubusercontent.com/sigoden/dufs/main/README.md (CLI, auth, WebDAV, install, license)
- https://crates.io/api/v1/crates/dufs (versions, license)
- https://api.github.com/repos/sigoden/dufs/releases (assets per platform, latest v0.46.0)
- https://raw.githubusercontent.com/sigoden/dufs/main/src/args.rs (default bind, allow-all semantics, auth-method)
- https://formulae.brew.sh/api/formula/dufs.json · https://github.com/ScoopInstaller/Main/blob/master/bucket/dufs.json · https://api.github.com/repos/microsoft/winget-pkgs/contents/manifests/s/sigoden

Findings:

- **Versioning: 0.x line; latest 0.46.0.** No "2.x" exists — detection must expect `dufs 0.4x.x` output from `dufs -V`.
- **Platforms:** macOS (x86_64 + aarch64) and Windows (x86_64 + aarch64) official prebuilt archives on GitHub Releases; `brew install dufs` (macOS), `scoop install dufs` (Windows). **Not in winget.** License: MIT OR Apache-2.0. Single self-contained binary; no runtime deps.
- CLI: `dufs [OPTIONS] [serve-path]`. `-b/--bind <addr>` (default **0.0.0.0 + ::** when IPv6 — exposes to the whole LAN), `-p/--port <port>` (default **5000**).
- **Permission flags:** default behavior IS read-only. Writes are opt-in: `--allow-upload`, `--allow-delete`, `--allow-search`, `--allow-symlink` (symlinks outside root!), `--allow-archive`, `--allow-hash`. `-A/--allow-all` = upload + delete + search + symlink + archive + hash (verified in src/args.rs L370-392). There is **no** `-r/--read-only`/`--allow-write` flag pair (task premise corrected).
- **Auth:** `-a, --auth <rules>` repeatable, format `user:pass@/path:rw`; anonymous rule `@/`; `--auth-method basic|digest` (default **digest**). Hashed passwords: sha-512 only, `$6$` prefix, must be single-quoted in shell; digest auth does not work with hashed passwords.
- **Credentials on the command line are visible** in process lists / shell history — a preset must either use `DUFS_AUTH` env or warn; plaintext dufs passwords in `ps` output are the main hazard.
- **WebDAV built in** (PUT/MKCOL/MOVE/DELETE/PROPFIND work with standard clients) — relevant only for read/write mode.
- Dependency detection: `dufs -V` presence probe; liveness endpoint `GET /__dufs__/health`.

Verdict: viable cross-platform first-class preset (binary-detect + "not installed" state + install link; never auto-install). Safe mode mapping: Read only (no flags) / Upload allowed (`--allow-upload`) / Read+write (`--allow-upload --allow-delete`). Writable modes must warn about unauthenticated writes when no auth rule is set; external exposure of a writable share must double-warn.

---

## 5. Cloudflare Quick Tunnel (Q11)

Sources (accessed 2026-10-01):
- https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/ (updated 2026-09-30)
- https://developers.cloudflare.com/tunnel/features/locally-managed-tunnels/configuration-file/
- https://developers.cloudflare.com/tunnel/reference/run-parameters/

Findings (official):

- Purpose: "Quick Tunnels are for testing and development. For production, create a Cloudflare Tunnel." No account, no domain, no config file, no login/cert.pem/credentials.
- URL: temporary random `*.trycloudflare.com` subdomain — "The hostname changes each time you create a Quick Tunnel." No stable hostname by design.
- **Persistence: "The URL stops working when you stop the cloudflared process." "Access ends for everyone when the process stops."** No uptime SLA; no documented URL expiry independent of the process — lifetime = process lifetime.
- Limits: max 200 in-flight requests per Quick Tunnel (excess → 429); no SSE.
- Syntax: `cloudflared tunnel --url http://localhost:PORT`; the URL is printed to stdout/log — a wrapper parses stdout (both platforms already do exactly this).

Verdict: Quick Tunnel is confirmed as "temporary public share", process-bound, unsuitable for persistence. The existing Port Manager integration (parse stdout, port-keyed association, auto-stop with the service) matches the documented model exactly. Documentation must state clearly: Quick Tunnel is NOT the keep-alive solution.

---

## 6. Cloudflare Named Tunnel (Q12)

Sources (accessed 2026-10-01):
- https://developers.cloudflare.com/tunnel/features/locally-managed-tunnels/create-local-tunnel/ (updated 2026-09-11)
- https://developers.cloudflare.com/tunnel/features/locally-managed-tunnels/tunnel-useful-commands/
- https://developers.cloudflare.com/tunnel/features/locally-managed-tunnels/local-tunnel-terms/
- https://developers.cloudflare.com/tunnel/features/locally-managed-tunnels/tunnel-permissions/
- https://developers.cloudflare.com/tunnel/features/locally-managed-tunnels/as-a-service/macos/ · .../windows/
- https://developers.cloudflare.com/tunnel/reference/tunnel-tokens/

Findings:

- Lifecycle: `cloudflared tunnel login` (writes account cert `~/.cloudflared/cert.pem`, account-wide power, ≥10 y validity) → `tunnel create <NAME>` (name↔UUID binding + run-only credentials file `<UUID>.json` + `<UUID>.cfargotunnel.com`) → `config.yml` (tunnel + credentials-file + ingress rules, top-down, must end with catch-all) → `tunnel route dns <NAME> <hostname>` (stable proxied CNAME) → `tunnel run <NAME>` (foreground process; each instance is a connector).
- **Stable hostname across restarts** (DNS record independent of tunnel state; tunnel down → Cloudflare error 1016).
- Crash hygiene: ungraceful kill leaves phantom connections — `tunnel cleanup <NAME>` before delete/re-run.
- **`tunnel run` vs `service install`:** run = ad-hoc foreground process in the invoking user's context; service install = persistent OS service. macOS: no-sudo install → LaunchAgent (starts at **login**, uses `~/.cloudflared`); sudo install → LaunchDaemon at `/Library/LaunchDaemons/com.cloudflare.cloudflared.plist` (starts at **boot**, config from `/etc/cloudflared`). Windows: SCM service named `Cloudflared` under **SYSTEM** (effective config dir becomes `C:\\Windows\\System32\\config\\systemprofile\\.cloudflared`), **admin required**, runs at boot; ImagePath registry edit pattern per docs.
- Token-based run: `cloudflared tunnel run --token <TUNNEL_TOKEN>` / `--token-file` (≥2025.4.0) — ingress lives server-side; "Anyone with the token can run the tunnel." Rotation via dashboard/API.
- **What a third-party wrapper needs for persistent background cloudflared:** no official wrapper SDK exists; the integration surface is CLI flags + env vars + config/credentials files + service commands + REST token API. A wrapper must decide the credential boundary (`cert.pem` = never; `<UUID>.json` = run-only; token = run-only, server-side ingress).

Comparison with existing Port Manager code:
- macOS `NamedTunnelManager` + `CloudflaredDiscoveryService` already implement the locally-managed model: discovery via `tunnel list` + local config.yml ingress parse (gated behind the tunnels UI, 30 s refresh, never at launch — correctly avoids account hits), `PortExposure` (hostname, publicURL, tunnelName, tunnelID), run/stop with runID tracking, "managedElsewhere" safety check before adding a second connector, log-line parsing for registration/connections/metrics.
- Windows: no named-tunnel support at all.
- Conclusion: Named Tunnel is already a complete, self-contained global feature on macOS. v1 should surface/link it, not redesign it. OS-service installation (launchd/SCM) is future work and would be an OS-boundary change (privileged helpers, config relocation under SYSTEM context on Windows) — deliberately out of v1.

---

## 7. Persistent SSH — future-phase context (Q13)

Sources (accessed 2026-10-01):
- https://man.archlinux.org/man/autossh.1.en — autossh(1)
- https://formulae.brew.sh/formula/autossh — Homebrew autossh
- https://cygwin.com/packages/summary/autossh.html — Cygwin autossh; https://packages.msys2.org/package/autossh — MSYS2 404 (not packaged)
- https://www.launchd.info/ — launchd agents vs daemons
- https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html — Apple launchd docs
- https://keith.github.io/xcode-man-pages/launchd.plist.5.html — launchd.plist(5)
- https://learn.microsoft.com/en-us/windows/win32/taskschd/logontrigger — Task Scheduler LogonTrigger
- https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement — OpenSSH on Windows key management

Findings (research only — future phase, not v1):

- **autossh:** supervisor that restarts a dead ssh; its man page itself notes ServerAliveInterval/CountMax "may be a better solution than the monitoring port". macOS: brew formula exists. Windows: no native build (Cygwin only, not in MSYS2) — poor base for a portable feature. Its detect-and-restart value overlaps with launchd KeepAlive / Task Scheduler restart. Reject as a v1+ dependency.
- **macOS:** LaunchAgent (`~/Library/LaunchAgents`) runs at login as the user with user keychain/ssh-agent access — the right level for user tunnels. LaunchDaemon runs at boot as root — wrong privilege level. KeepAlive semantics: `KeepAlive=true` unconditional restart; dictionary form gates on SuccessfulExit/Crashed. Caveats: rapid-exit jobs are throttled; `NetworkState` is "no longer implemented" — no native wait-for-network.
- **Windows:** Task Scheduler **LogonTrigger** is the standard user-level answer (runs ssh as the user at logon; supports UserId/Delay; restart-on-failure settings weaker than launchd). Windows services exist for sshd/ssh-agent (both default off; ssh-agent settable to Automatic for unattended key loading); a service has no user session and cannot naturally use the interactive user's key store.
- **How far pure ssh options go:** ServerAliveInterval/CountMax (catch half-open TCP) + ExitOnForwardFailure (catch unbound ports) convert silent hangs into clean exits — "self-detecting, not self-healing". A dead ssh stays dead; restart requires an external mechanism.
- **What future "Keep Alive / Start at boot" would require:** (1) an external restart mechanism — macOS LaunchAgent at login / Windows Task Scheduler logon task (user-level), or boot-level LaunchDaemon/SYSTEM service (elevated); (2) unattended key access — passphrase-less key, pre-loaded agent, or credential storage (a real secret-at-rest decision); (3) once-elevated installation for boot variants; (4) acceptance that a persistent tunnel is a standing unmonitored connection when the user is absent — a different threat model from the session-scoped runtime Port Manager owns today.
- **Reserved future path:** keep preset-rendered ssh commands self-contained (all options on the command line, no shell script wrapper), so a future "install as LaunchAgent/logon task" can reuse the exact same argv without re-deriving it. This is the only forward-compatibility requirement v1 must honor.

---

## 8. JupyterLab (Q10)

Sources (accessed 2026-10-01):
- https://jupyterlab.readthedocs.io/en/stable/getting_started/starting.html
- https://jupyterlab.readthedocs.io/en/stable/getting_started/installation.html
- https://jupyter-server.readthedocs.io/en/latest/operators/security.html
- https://jupyter-server.readthedocs.io/en/latest/operators/public-server.html
- https://raw.githubusercontent.com/jupyter-server/jupyter_server/main/jupyter_server/serverapp.py (aliases/flags, ip="localhost", port=8888, root_dir, open_browser)
- https://raw.githubusercontent.com/jupyter-server/jupyter_server/main/jupyter_server/auth/identity.py (token traits)
- https://raw.githubusercontent.com/jupyterlab/jupyterlab/main/pyproject.toml (console scripts)
- https://raw.githubusercontent.com/jupyter/jupyter_core/main/jupyter_core/command.py (jupyter --version)

Findings:

- CLI: `jupyter lab`. Bind-address flag is **`--ip`** (`--bind` does NOT exist); default ip `localhost`, default port **8888** — docs: "By default, Jupyter Server runs locally at 127.0.0.1:8888", "accessible only from localhost".
- **Working directory:** default = process CWD. Set explicitly via `--notebook-dir PATH` (positional path also accepted; `--ServerApp.root_dir` is the trait form). Official docs warn against launching from a root volume (`/`, `C:\\`).
- **Browser auto-open is ON by default** — preset must pass `--no-browser`.
- **Token auth is ON by default**: random token generated at startup, printed in URLs (`?token=...`) and written to a runtime file. Disabling auth (`token=""` + `password=""`) is documented as **NOT RECOMMENDED** — "access to the Jupyter Server means access to running arbitrary code". Password via `jupyter server password` (argon2 hash in config). The preset must NEVER generate a no-auth or token-less public configuration; the token stays in the process output/log, and the Open action must go through the tokened URL the server prints.
- **Port-retries trap:** `port_retries=50` by default — if the configured port is busy, Jupyter silently binds a DIFFERENT port, which breaks the managed-service readiness model (the app polls the configured port). The preset must pass `--port-retries=0` so a busy port surfaces as a Conflict instead of a surprise port.
- Detection: `jupyter --version` (lists core package versions incl. jupyterlab/jupyter_server), PATH probe for `jupyter`/`jupyter-lab`, fallback `~/.local/bin/jupyter` (pip --user installs may not be on PATH).
- Public-interface warnings: binding `--ip='*'` is documented as running "on a public interface" and requires password + SSL + understanding of limitations; single-user server (use JupyterHub for multi-user).

Verdict: viable advanced preset. Defaults: `--no-browser --ip 127.0.0.1 --port-retries=0`, user-chosen working directory, token auth untouched (server-generated), port user-chosen. External exposure via Exposure provider must carry an explicit warning that a public Jupyter = arbitrary code execution risk; the preset must never pair `--ip='*'` with disabled auth.

---

## 9. Windows OpenSSH client (Q7)

Sources (accessed 2026-10-01):
- https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_overview
- https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse
- https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-server-configuration
- https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement
- https://learn.microsoft.com/en-us/windows/terminal/tutorials/ssh
- https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-non-language-fod?view=windows-11
- https://learn.microsoft.com/en-us/troubleshoot/windows-server/system-management-components/upgrade-in-box-openssh-to-latest-openssh-release
- https://github.com/PowerShell/Win32-OpenSSH/issues/1082 · /issues/2460

Findings:

- **Location:** canonical client path C:\\Windows\\System32\\OpenSSH\\ssh.exe; on the system PATH whenever the Feature on Demand is installed. Also seen via PATH: Git for Windows bundled ssh (C:\\Program Files\\Git\\usr\\bin\\ssh.exe) and fork builds (C:\\Program Files\\OpenSSH) — a detection probe must prefer System32.
- **Default install state:** officially "not installed" on Win10 1809+/Server 2019-2022 (installable FoD since 1709, capability OpenSSH.Client~~~~0.0.1.0, about 5.28 MB); Server 2025 ships the server side. **In practice many consumer Win10/11 machines already have the client capability installed** (inbox client was OpenSSH_9.5p2 on Win11 25H2). Conclusion: treat as *usually present, not guaranteed* — runtime detection required.
- **Detection strategy for the app:** (1) fileExists %SystemRoot%\\System32\\OpenSSH\\ssh.exe; (2) PATH probe via where ssh (with ssh -V version check to surface which ssh was found); (3) optional authoritative capability state via Get-WindowsCapability -Online. Never auto-install; the "not installed" state points to Settings > System > Optional features / the Add-WindowsCapability command in documents.
- **Syntax parity:** Windows OpenSSH is Microsoft's fork of portable OpenSSH — -L/-R/-D, ExitOnForwardFailure=yes, ServerAliveInterval/CountMax behave identically to macOS (both long predate the inbox 9.5p2). Differences that matter: config files at %USERPROFILE%\\.ssh\\config + %ProgramData%\\ssh\\ssh_config (resolution: -F then user then system); ssh-agent is a Windows service on a named pipe (no SSH_AUTH_SOCK); inbox version lags upstream.
- **cmd.exe quoting (relevant to the launcher):** cmd rewrites the command line before ssh sees it — %VAR% expansion happens even inside double quotes, ^ escapes, double-quote toggling, MSVCRT/CommandLineToArgvW backslash-quote rules (2n backslashes + quote = n literal backslashes + toggle; trailing backslashes before a closing quote must be doubled). Best practice for an app spawning processes is to spawn ssh.exe directly with argv (CreateProcess), not via cmd /c — then local cmd semantics do not apply. Port Manager's launcher does go through cmd /d /s /c, so the preset renderer must respect cmd quoting rules (see design doc section on security).
- **winget cannot install the FoD** — the winget package is a separate preview MSI (Microsoft.OpenSSH.Preview). Do not offer winget as the install path for ssh.

Verdict: SSH presets are viable on Windows with runtime detection; the "not installed" state is realistic on fresh Windows Server and some consumer machines and must be a first-class UI state.

---

## 10. Platform differences consolidated

| Area | macOS | Windows | v1 consequence |
|---|---|---|---|
| Shell / command execution | /bin/zsh -lc (login shell; PATH includes /opt/homebrew/bin via .zprofile) | cmd.exe /d /s /c (cmd parse semantics apply) | Preset renderer needs per-platform escaping strategy (section 11) |
| Python binary name | python3 (plain python absent by default) | python / py (python3 is a trap) | Preset renders the platform-appropriate binary name |
| ssh presence | Preinstalled (verified locally: OpenSSH_10.3p1) | Usually present (FoD), not guaranteed | Windows needs a first-class "not installed" state; macOS still probes |
| ssh config location | ~/.ssh/config | %USERPROFILE%\\.ssh\\config | Alias scan reads the platform path; read-only parse of Host lines only |
| Directory picker | NSOpenPanel (already in editor) | none today | Add FolderBrowserDialog scoped to preset flows |
| Jupyter install | pip/conda; jupyter / jupyter-lab on PATH (or ~/.local/bin) | same + %LOCALAPPDATA% scripts caveat | PATH probe + known-path fallback |
| dufs install | brew | scoop (not winget) | Install-documents links differ per platform |
| Persistence | UserDefaults plist | settings.json | Optional presetID field compatible with both |
| Delete dialog API | SwiftUI confirmationDialog | MessageBox | Shared semantic mapping, native visuals |
| Tunnel runtime | TunnelManager + NamedTunnelManager | TunnelViewModel (Quick only) | Named Tunnel row: macOS link vs Windows hidden / "not available" |

---

## 11. Security findings (cross-cutting)

1. **Shell escaping is the central preset risk.** Custom Service remains "user-authored shell input, nothing escaped" by design. Presets are different: the app composes the command from user-controlled field values, so the app owns safe rendering.
   - macOS (zsh): wrap every variable value in single quotes with the escape sequence quote-backslash-quote-quote-quote (the standard posix single-quote escape). Verified empirically 2026-10-01: a value containing quotes, ampersands, dollar signs, backticks, and backslashes round-trips byte-identically through the app's exact execution model (a /bin/zsh process reading the command string). Single-quote escaping makes zsh a non-issue.
   - Windows (cmd.exe): escaping is a minefield — see section 9. Robust strategy: **do not escape — constrain and quote.** Preset fields validate against per-field character allow-lists (ssh host/alias: letters, digits, dot, dash, underscore, plus optional @ and :; ports: integers; paths: reject double-quote, percent, CR/LF) and the renderer wraps path-like values in double quotes. Values that would need cmd metacharacters are excluded by the no-credentials rule anyway.
   - Newlines are rejected in every preset field on both platforms (the command is single-line).
   - The rendering function is pure and table-driven per platform — unit-tested against a fixture matrix of adversarial values (quotes, dollar, backtick, percent, caret, ampersand, pipe, unicode, empty, very long).
2. **No credentials in presets (constraint, reaffirmed by research):** Dufs auth would put user:pass in the stored command AND in process argv (visible in ps) — the v1 Dufs preset therefore ships **without a password field** (modes: read-only / upload / read+write, with explicit "no authentication" warnings). Jupyter: the token stays server-generated in output; never stored, never passed. SSH: no key-path field, no password field — rely on the user's existing agent/config; keys are never read, stored, or generated by Port Manager.
3. **Bind-address discipline:** every preset that can listen binds loopback by default (Static File Share -b 127.0.0.1 — python's default is all-interfaces; Dufs -b 127.0.0.1 — default is 0.0.0.0; Jupyter --ip 127.0.0.1; SOCKS5 local bind locked to loopback). 0.0.0.0 / * choices exist only behind the SSH-reverse advanced warning (server-side GatewayPorts semantics; see section 2) and are never preset defaults.
4. **Exposure warnings:** writable Dufs + Quick Tunnel public exposure = double warning (unauthenticated writes reachable from the internet). Jupyter public exposure = strong warning (a public Jupyter server can execute arbitrary code). File Share over python: symlink-following + directory-listing caveats stated in the preset help copy; the chosen directory is displayed in the form so the user sees exactly what is shared.
5. **Directory traversal / serving scope:** python http.server follows symlinks outside the served root; Dufs has --allow-symlink (off by default; never enabled by the preset). The presets never enable symlink exposure. Serving the home directory root itself triggers a warning suggesting a narrower folder.
6. **Jupyter port-retries trap (section 8):** without --port-retries=0 a busy port silently moves the server — breaking the app readiness poll and ownership model. The flag is fixed in the preset.
7. **Dependency probes are read-only:** fileExists on known paths + where / command -v PATH probes + --version execution. No package-manager invocations, no network calls, no config writes. SSH alias enumeration parses only Host lines of the user's ssh config (never keys, never IdentityFile values).

---

## 12. Rejected / deferred candidates (evaluation summary)

| Candidate | Verdict | Key reason (evidence sections) |
|---|---|---|
| autossh | **Reject** | No native Windows build (Cygwin only, not in MSYS2) (§7); its value overlaps launchd KeepAlive / Task Scheduler restart; monitoring port redundant with ServerAliveInterval per its own man page |
| OS-persistent tunnels (launchd / Task Scheduler / boot services) | **Defer — future phase** | Requires elevated install + unattended key access + outside-user-session threat model (§7); path reserved (self-contained ssh argv), not v1 |
| frp | **Reject (constraint)** | Out of scope by task constraint; also an external daemon dependency |
| Tailscale / MCP / CLI / Linux service manager | **Reject (constraint)** | Task constraints exclude them |
| Named Tunnel as per-service attachment | **Reject (design)** | Named tunnels are account-level global resources; binding to service profiles would redesign a working frozen feature (§6) |
| Unified exposure provider protocol | **Reject for v1** | Three providers with three lifecycle semantics; premature abstraction (design doc §7.1) |
| Dufs auth in preset | **Reject for v1** | Credentials in stored command + argv-visible (§4); no-credentials constraint |
| python http.server upload mode | **Reject (n/a)** | GET/HEAD only, no upload exists (§3) |
| Winget as dufs/ssh install path | **Reject** | dufs not in winget (§4); winget cannot install the ssh FoD (§9) |

---

## 13. Answers to Phase-2 questions (Q6-Q13)

- **Q6 OpenSSH safe defaults:** -L/-R/-D exist; server-side -R binds loopback unless server GatewayPorts allows more; ExitOnForwardFailure=yes makes bind failures fail fast; ServerAliveInterval/CountMax (15/3) detect dead connections through the encrypted channel and are preferred over TCPKeepAlive; -N for no-command sessions. The ssh-config alias namespace is a legitimate, safe default source for the host field (read-only Host-line parse).
- **Q7 Windows OpenSSH:** usually present (FoD), not guaranteed; detect System32 path first, then PATH; syntax identical to macOS for everything the presets use; config paths differ.
- **Q8 python http.server:** default binds ALL interfaces (must pass -b 127.0.0.1); no auth; follows symlinks; GET/HEAD only; python3 on macOS / python or py on Windows.
- **Q9 Dufs:** cross-platform single binary; default 0.0.0.0 (must pass -b 127.0.0.1); read-only by default with opt-in upload/delete flags; digest auth via -a but credentials land in argv; brew/scoop, not winget; 0.46.0.
- **Q10 JupyterLab:** localhost:8888 by default; token auth on by default (never disable); --no-browser required; --notebook-dir for working dir; --port-retries=0 REQUIRED for the managed-service model; --ip (not --bind).
- **Q11 Quick Tunnel:** process-lifetime temporary URL, random hostname, documented as test/dev only; the existing integration matches the documented model.
- **Q12 Named Tunnel:** complete locally-managed lifecycle already implemented on macOS (run-mode, discovery-gated); stable hostname via route dns; OS-service installation is a separate privileged feature — future phase.
- **Q13 Persistent/keep-alive SSH (future):** needs external restart mechanism (LaunchAgent / Task Scheduler logon task), unattended key access, and acceptance of a standing connection outside the interactive session; v1 keeps ssh argv self-contained so a future phase can reuse the exact command.
