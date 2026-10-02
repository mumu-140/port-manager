# Presets + Exposure UX v1 — Design and Implementation Plan

**Status:** DRAFT FOR REVIEW — do not implement until reviewed
**Date:** 2026-10-01
**Repository:** `mumu-140/port-manager`
**Base SHA:** `3e007d4` (main)
**Companion research:** `docs/research/2026-10-01-presets-exposure-research.md`
**Prior frozen design:** `docs/plans/2026-09-30-service-manager-design-and-implementation.md`
**Target platforms:** macOS + Windows

This increment makes common local-service and tunnel workflows easy to configure **without** weakening the Managed Service ownership and safety model. The macOS and Windows Managed Service implementations are stable and frozen; presets are additive, editor-layer only.

---

## 1. Product scope

**In v1:**

1. **Service presets** — picker + form flows that generate ordinary `ManagedServiceConfig` profiles run through the existing `ManagedServiceManager`: Custom Service (the existing editor), Static File Share (Python http.server), SSH Local Forward, SSH SOCKS5 Proxy, SSH Reverse Forward, Dufs File Share (advanced), Jupyter Lab (advanced).
2. **Exposure / Network Access grouping** in the service detail view (replaces the Quick-Tunnel-only section; §7).
3. **Delete confirmation semantics** — unified state→copy→button mapping (§8).
4. **Dependency discovery layer** — generalizes the existing cloudflared path-probe pattern (§9).

**Out of v1 (constraints unchanged):** Tailscale, MCP, CLI, Linux Service Manager, frp, automatic dependency installation, credential/password/token/private-key storage in presets, system-level persistence, persistent keep-alive tunnels (future phase, §14).

**Non-goals preserved from the frozen design:** no OS service management, no in-place socket mutation (Stop → Edit → Start), no implicit kills of any process this session does not own.

---

## 2. Final v1 preset list

| Preset | id | Category | Dependency | Tier |
|---|---|---|---|---|
| Custom Service | `custom` | General | none | Core (existing editor) |
| Static File Share | `static-file-share` | File share | `python3` / `python` | Core |
| SSH Local Forward | `ssh-local-forward` | Tunnel | `ssh` | Core |
| SSH SOCKS5 Proxy | `ssh-socks5-proxy` | Tunnel | `ssh` | Advanced |
| Dufs File Share | `dufs-file-share` | File share | `dufs` binary | Advanced |
| Jupyter Lab | `jupyter-lab` | Notebook | `jupyter` (pip) | Advanced |

Rationale (full evaluation §13): the two zero-extra-dependency presets (Static File Share, SSH Local) are core — they work out of the box on both platforms and cover the most common workflows. The SSH family shares one architecture, so SOCKS5 costs little after Local exists. Dufs and Jupyter are advanced: external installs, shipped with detection gates and "not installed" states, never auto-install.

> **Review decision (v1):** the SSH Reverse Forward preset is **not shipped in v1**. Its lifecycle
> contradicts the ManagedService contract: Start requires {port} to be free plus a local listener
> ready, and a reverse forward (`-R`) is a remote-side bind with no local listener at all — the
> readiness model cannot observe it. SSH Reverse Forward moves to the future
> Exposure/provider design (or a readiness-model design). The GatewayPorts findings from the
> research are retained for that future work.

---

## 3. UX flows

### 3.1 Preset picker (creation)

- The list view "+" opens a **preset picker** (menu/popover), not the raw editor.
- Picker entries: Custom + the 5 presets, each with icon + localized title + one-line description. Entries whose dependency is missing stay selectable but show a "not installed" tag; their form shows the dependency state with an install-documents link (never auto-install).
- **Custom Service** opens the existing editor exactly as today (backwards compatible).
- Preset forms prefill every field; the user edits and saves. Saving produces a normal profile through the existing validator + manager — the picker never bypasses validation or persistence.

### 3.2 File Share flow (lowest friction)

`+ → Static File Share` (or Dufs):

- **Directory:** `[ Choose… ]` — macOS: existing NSOpenPanel; **Windows: add FolderBrowserDialog** (Windows has no directory picker today; scoped to preset flows).
- **Mode:** Read only (default) · Upload allowed (Dufs only) · Read/write (Dufs only). Static File Share is read-only by nature; its mode control is hidden.
- **Port:** prefilled suggestion (8123 static / 5000 Dufs), user-editable, validated by the existing rules.
- **Exposure:** `Local only` (default) · `Temporary public via Cloudflare Quick`. Local-only is the forced default; public exposure is a deliberate choice made here **or later** from the detail view's Exposure panel (§7). If chosen at creation, the profile saves as a normal local-only service with a hint; the Quick Tunnel is started from the detail view after the service reaches Running — creation never starts tunnels itself (a starting service has no port to tunnel to yet).

### 3.3 SSH preset flows

**SSH Local Forward** — fields: SSH host (**v1: manual free-text only** — Host alias or `user@host`; alias enumeration is deferred with the SSH-config parsing research: Host lines only, never keys or IdentityFile values), Remote host (default `127.0.0.1`), Remote port (1...65535). Advanced (collapsed): ServerAlive interval (default 15), ServerAlive count (default 3). The listener bind is explicit — `-L 127.0.0.1:{port}:` — and never depends on ssh_config GatewayPorts. There are **no extra SSH options**: free-form fragments could re-enable non-loopback binds, alter the single-port lifecycle, or point ssh at key material, so v1 offers only the structured fields. Generated command previewable but collapsed by default.

**SSH Reverse Forward** — *not a v1 preset* (see the §2 review decision).

**SSH SOCKS5 Proxy** — fields: SSH host, Local bind (`127.0.0.1`, locked to loopback — no `0.0.0.0` choice offered in v1), Local port, Advanced (keepalive). Never defaults to `0.0.0.0`.

Both SSH presets: `-N` and `-o ExitOnForwardFailure=yes` always included and not user-editable.

### 3.4 Jupyter Lab flow

Fields: working directory (`[ Choose… ]`, never a root volume — explicit validation error), port (default 8888). Fixed flags rendered by the preset: `--no-browser --ip 127.0.0.1 --port-retries=0`. Authentication stays server-generated (token in output); the preset never disables auth and never stores tokens. The detail view's Open action must use the tokened URL the server prints (copied from the log), not a token-less `http://host:port`.

---

## 4. Data model

### 4.1 The only model change: optional `presetID`

`ManagedServiceConfig` gains one optional field on both platforms:

- macOS: `var presetID: String?` — Codable; missing key decodes to nil.
- Windows: `public string? PresetId` — System.Text.Json tolerant of absence.

- Absent on all existing profiles → decodes to nil → **backwards compatible with every persisted profile today** (no migration).
- Set at save time when the profile is created or edited through a preset form. Used **only** for editing/presentation: the editor re-opens the preset form pre-filled; the list/detail may show a small preset badge.
- Never written into runtime ownership state, never read by the manager lifecycle, never used to alter behavior. A profile with a presetID behaves exactly like a custom profile.
- If a preset is later removed/renamed, profiles with unknown presetIDs degrade to custom editing. No migration.
- Deliberately the **smallest** model change that avoids a corner: without presetID, "re-edit with preset defaults" would require guessing intent from command text (rejected — inferring from similarity violates the ownership-inference spirit).

### 4.2 What presets are

A preset is a **static, code-level definition** (compiled in, not persisted, not user-editable in v1), conceptually:

- id (stable string)
- localized title / one-line description
- icon
- category (general | fileShare | tunnel | notebook)
- dependency requirement (§9, optional)
- ordered form fields (typed descriptors: text, port, directory, single-select — with per-field validators)
- field-level validator
- **pure generator: field values → complete `ManagedServiceConfig`**
- optional explanatory/warning copy keys

- The generator produces the same six persisted fields as the custom editor; the profile then goes through the **existing** `ManagedServiceValidator` → `ManagedServiceManager.add/update`. No second runtime/lifecycle engine, no manager changes.
- Presets are not persisted as objects; only the resulting ordinary profile (plus `presetID`) is persisted.

### 4.3 Windows parity

The same conceptual struct exists in C# (`ManagedServicePreset`, static registry). Preset definitions stay in structural lockstep across platforms (same ids, field sets, defaults); a conformance checklist in the implementation plan enforces it.

---

## 5. Architecture (smallest that works)

- **macOS:** new files under `Sources/Services/Presets/` (definitions + generators + validators) and `Sources/Views/ManagedServices/` (picker + forms). The editor's existing `ManagedServiceEditorTarget` gains a preset mode; the custom editor is untouched.
- **Windows:** new files under `PortKiller/Services/Presets/`; preset picker + forms prefill the single existing `ManagedServiceEditorWindow`; FolderBrowserDialog added for directory fields.
- **Zero changes** to: `ManagedServiceManager` (both platforms), `ManagedServiceProcessController`/`RuntimeLauncher`, reconciliation, conflict handling, tunnel managers, storage backends (only the config struct gains an optional field), persistence formats.
- One narrowly scoped addition to the command layer: a **preset command renderer** that safely renders user-controlled values into the start command (§10). The existing custom-command renderer remains byte-for-byte unchanged (custom service stays "user-authored shell input, nothing escaped").

---

## 6. Lifecycle semantics (unchanged, stated for the record)

- Runtime ownership remains current-session only. Presets add nothing to ownership: a preset-generated profile is owned exactly like a custom profile.
- Normal Stop terminates only the tracked runtime; Conflict occupants are never killed without explicit, per-PID-snapshot confirmation.
- Service profiles persist; runtime state does not; surviving listeners after relaunch are unowned Conflict.
- Quick Tunnel remains part of the local Port Manager lifecycle; Stop service stops its temporary Quick Tunnel; Restart never re-shares. Preset flows do not alter any of this — File Share's "public exposure at creation" is a hint plus the existing Share button flow, not a new tunnel engine.
- SSH forward presets are services: the ssh process IS the managed runtime, with the standard states. ExitOnForwardFailure=yes makes bind failures fail fast (Failed state) instead of hanging as an idle ssh — this is what makes the existing readiness/stop model correct for tunnels.

---

## 7. Exposure model

### 7.1 Decision: UI grouping in v1 — no provider protocol

The three candidate providers have fundamentally different lifecycle semantics:

| Provider | Runtime owner | Lifecycle | Stable hostname | Where it lives today |
|---|---|---|---|---|
| Cloudflare Quick Tunnel | Port Manager child process | Starts/stops with service + app; port-keyed | No (random) | TunnelManager (macOS) / TunnelViewModel (Windows) |
| Cloudflare Named Tunnel | Global tunnels feature (macOS only) | User-managed; discovery-gated; not service-bound | Yes | NamedTunnelManager + Cloudflare tunnels UI |
| SSH Reverse Forward | The managed service itself | The service IS the tunnel | n/a (remote host decides) | ManagedServiceManager runtime |

Forcing these behind one provider protocol would require a lowest-common-denominator lifecycle API that matches none of them (Quick is service-scoped; Named is global and account-backed; Reverse is not a separate runtime at all). **v1 is therefore a UI grouping, not a provider protocol and not a configuration model.**

### 7.2 Detail view: "Network Access" section

The existing Quick Tunnel section slot (macOS `tunnelSection`; Windows Quick Tunnel card) becomes a **Network Access** section with progressive disclosure:

- **Local** (always first, when running): `http://localhost:<port>` + Open/Copy. This formalizes what Open already does.
- **Temporary public:** existing Quick Tunnel UI unchanged underneath (Start/Stop/Copy/Open + starting/active/error states + cloudflared-not-installed state). Wording changes from implementation-specific to intent-based: section label "Temporary public"; helper copy "Uses a Cloudflare Quick Tunnel. The address is random and disappears when the tunnel or Port Manager stops."
- **Stable public (macOS):** a link row "Cloudflare Named Tunnel — configure or view in Tunnels" that deep-links to the existing global tunnels UI. No new runtime; no manager coupling. **Windows:** the row shows a localized "Not available on Windows in this version" caption (or is hidden — hidden is preferred to reduce noise; decision left to review).
- **SSH Reverse:** not an exposure provider — and not a v1 preset (§2 review decision), so no section branch is needed. HTTP presets (static/Dufs/Jupyter) show the full section; SSH presets and Custom keep Local-only behavior (Custom stays as-is for compatibility).

Rationale for keeping Quick Tunnel runtime untouched: the existing port-keyed association, auto-stop-with-service, orphan cleanup, and URL parsing are tested and frozen. The grouping is presentational.

### 7.3 Rejected alternatives

- Provider protocol + config model: premature abstraction (three providers, three semantics, no fourth on the roadmap). Revisit if a genuinely provider-shaped fourth feature appears.
- Making Named Tunnel a per-service attachment: wrong model — named tunnels are account/global resources with their own ingress; binding them to service profiles would redesign a working feature (violates the freeze).

---

## 8. Delete confirmation design

### 8.1 Semantics (both platforms, single mapping)

A pure function maps semantic state → (message, destructive button label). Inputs: status (stopped/failed/running/conflict; starting/stopping never reach the dialog — Delete stays disabled as today), tunnel presence (owned running + active Quick Tunnel), port (for conflict copy).

| State | Message (EN) | Message (zh-CN) | Destructive button |
|---|---|---|---|
| Stopped / Failed | Delete service "%@"? This removes the saved configuration. | 删除服务"%@"？这将移除已保存的配置。 | Delete / 删除 |
| Running (owned) | Stop and delete "%@"? The owned service will be stopped first. | 停止并删除"%@"？将先停止该本应用管理的服务。 | Stop & Delete / 停止并删除 |
| Running (owned) + Quick Tunnel active | Stop and delete "%@"? The owned service and its temporary public tunnel will both be stopped. | 停止并删除"%@"？该服务及其临时公网隧道都将被停止。 | Stop & Delete / 停止并删除 |
| Conflict | Delete configuration "%@"? The external process using port %ld will not be terminated. | 删除配置"%@"？不会终止占用端口 %ld 的外部进程。 | Delete Configuration Only / 仅删除配置 |
| Transitioning | (dialog never shown; Delete disabled as today) | — | — |

Rules:

- Wording matches actual behavior exactly: Running = the owned service IS stopped first (existing manager behavior); Conflict = the external process is NEVER terminated (existing behavior); the +tunnel variant explicitly names the temporary tunnel (existing auto-stop behavior).
- The destructive action remains explicit and role-marked destructive on macOS / MessageBoxIcon.Warning with explicit button text on Windows.
- **No "Don't ask again"** — no suppression state, matching both platforms today.
- Buttons: macOS keeps `.confirmationDialog` with the destructive button label per the table; Windows keeps MessageBox but upgrades `OKCancel` to `YesNo` with per-state destructive button text ("Stop & Delete" / "Delete" / "Delete Configuration Only"), caption "Delete service". Both remain platform-native — researched tradeoff (§12.1): forcing a shared custom dialog adds a Windows custom-control maintenance burden for zero semantic gain; semantics live in the shared mapping, not the visuals.
- Windows' transitioning guard message ("Wait for "X" to finish its current operation.") is kept, localized.

### 8.2 Where the mapping lives

- macOS: new pure type `ManagedServiceDeleteConfirmation` (state in → localized strings out), unit-tested without UI. Views consume it.
- Windows: new static `ManagedServiceDeleteCopy` (same mapping), unit-tested; `Delete_Click` consumes it.
- The existing behavior tests (`removeStopsOwnedServiceAndDeletesProfile`, `removeConflictOnlyServiceKillsNothing`, `DeleteRunningServiceStopsOwnedRuntimeThenRemovesProfile`, `DeleteConflictProfileNeverKillsTheOccupant`, `deleteConfirmationsIncludeServiceName`) must stay green — the mapping changes copy/buttons only, never behavior.

---

## 9. Dependency discovery layer

### 9.1 Generalize the existing pattern

Both platforms already probe cloudflared the same way (custom path preference → known paths → PATH probe → cached result + explicit recheck). That pattern becomes a small reusable layer:

```
DependencyRequirement
- binaryName            // "python3" | "python" | "ssh" | "dufs" | "jupyter" | "cloudflared"
- knownPaths (per platform)
- pathProbe             // PATH lookup: macOS via FileManager/which-equivalent; Windows via where.exe
- versionArgs           // ["--version"] (display only)
- installDocumentsURL (per platform)
```

States: **available**(path) · **notInstalled** · **unsupported(platform)** · **needsConfiguration**(available but unusable, e.g. python3 exists but is the stub without CLT — v1 may collapse this into notInstalled with tailored copy).

- Probes are strictly read-only: fileExists + PATH lookup + optional --version execution. No installs, no network, no config writes (research §11.7).
- Known paths mirror the research: ssh → %SystemRoot%\\System32\\OpenSSH\\ssh.exe (System32 preferred over Git-bundled); python → /usr/bin/python3 + PATH (macOS) / python, py + PATH (Windows); dufs → /opt/homebrew/bin, /usr/local/bin + PATH (macOS) / scoop shim PATH + %USERPROFILE%\\scoop\\shims (Windows); jupyter → PATH + ~/.local/bin fallback.
- Results cached with the existing recheck affordance (cloudflared pattern). Discovery runs when a preset picker/form needs it — never at app launch, never ambient.
- **No auto-install ever.** The notInstalled state shows a localized explanation + a platform-appropriate install-documents link (Optional Features for ssh; python.org/downloads or brew; dufs GitHub releases / brew / scoop; jupyter.org install docs).

### 9.2 What it is used for

- Preset picker: availability tag per preset.
- Preset form: dependency banner (available at <path> / not installed + install link) — reuses the AlertBanner design-system component on macOS ("Generalizes DependencyWarningBanner and CloudflaredMissingBanner") and the existing banner pattern on Windows.
- Nothing at runtime: the manager never consults dependencies; a missing binary surfaces naturally as the existing launch-failure (Failed) path.

---

## 10. Security model

### 10.1 Command rendering (the blocker check, resolved)

The task asked: does the single-string startCommand representation fundamentally prevent robust safe escaping? **No — resolved, no blocker, no model change.** The app owns preset rendering and validation:

- **macOS:** the renderer wraps every field value in single quotes with the POSIX escape (quote → quote-backslash-quote-quote-quote). Empirically verified 2026-10-01 through the app's exact model (a /bin/zsh process reading the command string) with adversarial values (quotes, &, $, backticks, backslashes): byte-identical round-trip.
- **Windows:** escape nothing, constrain everything: per-field character allow-lists (host/alias: A-Za-z0-9 . _ - plus optional @ and :; ports: integers; paths: reject double-quote, percent, CR/LF) + renderer wraps path-like values in double quotes. This sidesteps the cmd % expansion / quote-stripping / backslash-quote minefield entirely (research §9).
- Newlines rejected in all preset fields on both platforms. The rendering function is pure + table-driven, unit-tested against an adversarial fixture matrix on both platforms.
- The existing custom renderer stays untouched: Custom Service remains user-authored shell by design.

### 10.2 Fixed invariants carried into presets

- **No credentials, ever:** no password/token/key-path fields in any preset (research §11.2). Dufs v1 has no auth field; Jupyter token stays server-generated; SSH uses the user's existing agent/config.
- **Loopback-only binding:** every listening preset binds 127.0.0.1 explicitly (python's default is all-interfaces; Dufs' is 0.0.0.0) — including the SSH local forward's listener. No non-loopback bind is offered in v1.
- **No arbitrary option fragments:** SSH presets expose structured fields only (host, remote host/port, keepalives); no free-form extra-options field that could bypass the loopback/GatewayPorts rules, the single-port lifecycle, or the no-credential design.
- **Exposure double-warning:** writable Dufs + Quick Tunnel = explicit warning; public Jupyter = strong warning (public Jupyter = arbitrary code execution).
- **Serving-scope guardrails:** File Share shows the chosen directory; choosing the home directory root warns and suggests a narrower folder; presets never enable symlink exposure flags.
- **Jupyter --port-retries=0 fixed** so a busy port becomes a Conflict, never a silent port move (which would break readiness and ownership).
- **Read-only probes only** (§9.1); SSH alias enumeration parses Host lines only — never keys or IdentityFile values; ssh config is read, never written.

---

## 11. Localization

- All new user-facing strings go through the existing mechanisms: macOS `ManagedServiceStrings.entries` ([String: (en, zh)]) merged by `LocalizationTables`, consumed via `L()`; Windows resource dictionary (existing pattern).
- **en + zh-Hans only**, both languages always provided for every key (existing tests enforce completeness and format-specifier parity — new keys must pass `formatSpecifiersMatchAcrossLanguages`).
- Naming: new keys live under `preset.*`, `exposure.*`, `dependency.*` namespaces; delete-confirmation keys extend the existing `service.delete.*` group.
- Missing key behavior stays as today (DEBUG log + raw key); the localization regression tests must be extended to cover the new namespaces.
- Rough new-key estimate: ~70 keys (picker ~15, forms ~20, dependency states ~8, exposure panel ~10, delete mapping ~10, warnings ~7). Finalized per milestone.

---

## 12. Alternatives considered (recorded decisions)

### 12.1 Delete dialog: shared custom dialog vs platform-native

A single shared custom dialog would guarantee identical visuals. Rejected: Windows already uses MessageBox everywhere; a custom shared dialog adds a Windows custom-control + a11y burden for zero semantic gain. Decision: **shared semantic mapping (§8.1), platform-native presentation.**

### 12.2 Exposure control inside the preset form vs separate panel

Putting the exposure choice inside every preset form vs only the detail-view panel. Chosen: **detail-view panel is the home; the File Share creation flow offers an optional exposure hint** (§3.2) because file sharing is the one workflow where "share this right now" is the common case. Other presets do not carry exposure choices at creation. Revisit only if usage shows a second workflow needing creation-time exposure.

### 12.3 Presets persisted as first-class objects vs static definitions

Persisted preset objects (user-editable templates) were rejected for v1: they add a persistence layer, migration, and UI (template management) with no demonstrated need; static definitions + ordinary profiles cover the workflows. The `presetID` field keeps the door open without committing.

### 12.4 SSH reverse as a separate "exposure provider" vs a service preset

SSH reverse could be modeled as an exposure action on an existing service (publish running service X to host Y). Rejected for v1: the reverse tunnel is itself a long-lived process that must appear in the service list with standard lifecycle (start/stop/conflict/logs), and it often tunnels things that are not Port Manager services. It is a service preset; the detail view adds only an informational hint (§7.2).

---

## 13. Candidate evaluation (final classification)

| Candidate | Decision | Rationale (research ref) |
|---|---|---|
| Custom Service | v1 — Core | Existing editor; becomes the picker's baseline entry |
| Static File Share | v1 — Core | Zero extra deps both platforms; read-only; highest usefulness/risk ratio (§3) |
| SSH Local Forward | v1 — Core | ssh present both platforms; safe defaults; common workflow (§2, §9) |
| SSH SOCKS5 Proxy | v1 — Advanced | Same architecture as Local after it exists; loopback-locked |
| SSH Reverse Forward | Not in v1 | Lifecycle contract mismatch (§2 review decision); future Exposure/provider design |
| Dufs File Share | v1 — Advanced | External binary; detection gate + install docs; no-auth modes with warnings (§4) |
| Jupyter Lab | v1 — Advanced | External pip package; fixed safe flags; token preserved (§8) |
| Cloudflare Quick Tunnel | v1 — already exists | Surfaced under Exposure grouping; runtime untouched (§7) |
| Cloudflare Named Tunnel | v1 — link only | macOS feature link from Exposure panel; Windows hidden (§6, §7.2) |
| autossh | Reject | No Windows build; redundant with OS restart mechanisms (§7) |
| frp / Tailscale / MCP / CLI / Linux svc | Reject | Task constraints |
| OS-persistent tunnels | Defer | Future phase; path reserved (§14) |

---

## 14. Future path: persistent tunnels (explicitly deferred, research only)

v1 reserves the path (no code): preset-rendered ssh commands stay **self-contained** (all options on the command line, no wrapper script), so a future "Keep Alive / Start at boot" phase can reuse the exact argv inside a LaunchAgent (login, user-level) or Task Scheduler logon task. That phase must separately solve unattended key access, elevated installation for boot variants, and the outside-user-session threat model — all documented in research §7. Nothing in v1 may preclude it; equally, nothing in v1 implements it.

---

## 15. Testing strategy

### 15.1 New tests (both platforms unless noted)

1. **Preset generator purity + output validity:** every preset × representative field sets → generated config passes the existing `ManagedServiceValidator`; ids/ports/host/workingDirectory correct; fixed flags present exactly once (e.g. --no-browser, -N, ExitOnForwardFailure, -b 127.0.0.1, --port-retries=0).
2. **Preset renderer adversarial matrix:** adversarial values (quotes, dollar, backtick, percent, caret, ampersand, pipe, semicolon, unicode, empty, 1000-char) per field type → rendered command is inert (macOS: assert escaped form matches the single-quote rule; Windows: assert validator rejects disallowed chars and quoting of allowed ones). The macOS round-trip was empirically verified during research; the test suite encodes it.
3. **Field validators:** charset rejections (host/alias/path rules), port bounds, newline rejection, home-root warning for File Share.
4. **Dependency mapping:** dependency requirement → probe stub states (available/notInstalled/unsupported) drive correct picker tag + banner copy; probes themselves thin (fileExists/PATH) with one integration-style test per platform using temp dirs.
5. ~~SSH config alias scan~~ — **deferred with the alias enumeration feature** (v1 ships manual SSH-host entry only); the fixture plan stays here for the future work.
6. **Delete confirmation mapping:** state × tunnel-presence matrix → exact message keys + button labels (table §8.1), including zh-CN variants; pure-function tests, no UI.
7. **Backwards compatibility:** round-trip decode of profiles WITHOUT presetID → nil; with unknown presetID → custom-editor fallback; existing storage suites untouched.
8. **Localization completeness:** new namespaces pass the existing table tests (both languages, format-specifier parity).
9. **Exposure panel (macOS):** Named Tunnel link row appears when tunnels exist; Windows: row hidden/not-available copy (snapshot-style view-model tests).

### 15.2 Existing suites must stay green

macOS: 77 managed-service tests (model 21, manager 29, editor VM 11, process tree 5, runtime log 6, localization 6, cloudflared discovery 5, survival smoke 2 env-gated). Windows: 51 managed-service tests (manager 29, survival smoke 2, tunnel coordination 3, ...). The delete-copy change extends `deleteConfirmationsIncludeServiceName`; behavior tests (`removeStopsOwnedServiceAndDeletesProfile`, `removeConflictOnlyServiceKillsNothing`, Windows delete-mapping tests) unchanged.

### 15.3 What is NOT tested (explicit limits)

- No real SSH server in the suite: tunnel presets are validated at the generated-command level; a manual QA pass covers one live forward per platform (documented checklist in the implementation plan).
- No real cloudflared/dufs/jupyter installs required: dependency layer tested with probe stubs; one manual smoke per binary documented.
- Windows builds/tests run on Windows infrastructure as today (repository already gates the Windows test target accordingly).

---

## 16. Implementation milestones (suggested order, each independently shippable)

| # | Milestone | Contents | Notes |
|---|---|---|---|
| M1 | Preset core + model field | `presetID` field both platforms + preset definitions/generators/validators + generator/validator/compat tests | No UI yet |
| M2 | Dependency layer | DependencyRequirement + probes + states + tests | Reuses cloudflared pattern |
| M3 | Editor integration macOS | Preset picker + File Share + SSH trio forms + directory chooser reuse + live validation + localization | Custom flow byte-identical to today |
| M4 | Editor integration Windows | Same + FolderBrowserDialog + where.exe probes | Lockstep definitions checklist |
| M5 | Delete confirmation semantics | Shared mapping + per-platform wiring + copy (en/zh) + tests | Behavior untouched |
| M6 | Exposure panel | Network Access section both platforms + Named link (macOS) + copy | Quick runtime untouched |
| M7 | Dufs + Jupyter presets | Forms + dependency banners + warnings + localization | Depends on M2-M4 |
| M8 | Docs + manual QA pass | In-app help copy, README section, manual smoke checklist results | Before release |

M1-M2 can proceed in parallel; M3/M4 depend on M1+M2; M5/M6 are independent of M3/M4; M7 last. Localization keys land with the milestone that uses them (keeps table tests green per commit).

---

## 17. Final recommendation

**Implement the v1 scope of this document** — presets as editor-layer generators over the frozen Managed Service core, Network Access grouping, semantic delete confirmation, and the dependency discovery layer. It is additive (zero changes to manager/process/tunnel/storage behavior), preserves every ownership invariant, and removes the highest-friction workflows (file share, SSH forwards) without new security surface beyond the constrained renderer, which is tested and empirically grounded.

**Explicit answers to the eight open questions:**

1. **Presets as generators vs first-class entities:** generators (static definitions + ordinary profiles + optional `presetID`). First-class persisted templates rejected for v1 (§12.3).
2. **SSH reverse as managed service vs exposure provider:** managed service preset (the process needs standard lifecycle); exposure panel shows an informational hint only (§12.4).
3. **Named tunnels per-detail vs global link:** global link from the macOS Exposure panel; no per-service attachment; Windows hidden (§7.2, §12).
4. **Dufs despite being external:** include as Advanced with dependency gate + no-auth modes + warnings; no auto-install, no winget claims (§13).
5. **Python share despite limitations:** include as Core read-only with -b 127.0.0.1 forced and symlink/listing caveats in help copy (§3, §10.2).
6. **Jupyter core vs advanced:** Advanced (external pip dependency) with fixed safe flags; --port-retries=0 mandatory (§8, §3.4).
7. **What keep-alive/persistence means:** future phase = external restart mechanism (LaunchAgent/Task Scheduler) + unattended keys + elevated install for boot variants; v1 only keeps ssh argv self-contained (§14).
8. **Data model changes now:** exactly one — optional `presetID` on `ManagedServiceConfig`, backward compatible, presentation-only (§4).

**Open questions for review:**

- a) Windows Named Tunnel row: hide entirely vs show "not available" caption (§7.2 — reviewer preference).
- b) File Share default port suggestion (8123?) and Dufs default (5000 is dufs' default but commonly taken — alternative 5001?).
- c) SSH alias scan: deferred out of v1 with the alias enumeration feature (when it lands, proposal: ignore `Include` directives, documented).
- d) Whether M5 (delete copy) should also apply the new copy to the Windows transitioning guard, or keep that message as-is.

---

## 18. Security invariants checklist (must hold at every milestone)

- [ ] No process is ever signalled except runtimes this session owns, or conflict occupants with explicit per-PID confirmation (unchanged paths only).
- [ ] No credentials, tokens, passwords, or key material in profiles, commands, logs, or memory beyond what the user's own config already provides.
- [ ] Every listening preset binds loopback by default; non-loopback only behind explicit warnings.
- [ ] Dependency discovery is read-only; no installs, no network, no config writes.
- [ ] Quick Tunnel lifecycle unchanged: process-bound, auto-stopped with the service, never auto-restarted.
- [ ] Stop service stops its tunnels; restart never re-shares; relaunch leaves surviving listeners as unowned Conflict.
- [ ] Delete copy states exactly what will happen; conflict delete never touches the external occupant.
- [ ] No auto-restart/persistence of any service or tunnel; profiles reload as Stopped.
